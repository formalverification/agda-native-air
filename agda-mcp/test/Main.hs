-- | Main.hs
--
-- File: agda-native-air/agda-mcp/test/Main.hs
--
-- Description:
--   Integration tests for agda-mcp.
--
--   Tests are organized in three tiers:
--   0. Pure unit tests (no IO, no Agda) — hole finding, marker parsing.
--   1. Fixture-file tests (IO for file read, no Agda) — 1a: the hole model
--      (issues #71/#73: all hole syntaxes, comment/prose decoys, literate
--      flavours); 1b: corpus loading, search_by_name, search_by_type,
--      get_dependencies.
--   2. Subprocess tests (needs agda on PATH) — full tool round-trips,
--      including 2d: hole-enumeration parity against batch Agda.
--
--   Tier 2 tests are skipped gracefully if Agda is not available, making the test
--   suite safe to run in CI without a Nix shell.
--
--   Planned Tests (v1):
--     We will add a third tier of tests that run the full MCP server and send
--     JSON-RPC requests to it, verifying end-to-end behavior from the client side.
--     Once third tier tests are added, remove this paragraph and add the following
--     to the list above:
--     3. MCP protocol tests (needs agda on PATH) — send JSON-RPC, verify response.
--

{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (catch, SomeException)
import Data.Char (isDigit)
import Data.Either (isLeft)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.ByteString as BS
import System.Directory (findExecutable, doesFileExist, getCurrentDirectory)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>), takeDirectory, takeFileName)
import System.IO (hPutStrLn, stderr)

import AgdaMCP.Agda
  ( parseGoalContext , defaultConfig
  , AgdaConfig (..)
  , runAgda , AgdaResult (..)
  )
import AgdaMCP.Holes
  ( LiterateFlavour (..) , flavourOf , maskNonCode
  , HoleSpan (..) , findHoles , findNthHole
  , injectReportExpr , substituteHole
  )
import AgdaMCP.Corpus (loadCorpus, searchByName, searchByType, getDeps)
import AgdaMCP.Tools.ProofState
  ( handleGetGoal, handleFillHole, handleCheckFile, handleGetDiagnostics
  , ensureDebugImport, moduleNameOf, errorTagsOf, onlyOpenHoleErrors )
import AgdaMCP.Tools.Search
  ( handleSearchByName, handleSearchByType, handleGetDependencies )
import AgdaMCP.Types


-- ---------------------------------------------------------------------------
-- Test harness (minimal, no extra dependencies)
-- ---------------------------------------------------------------------------

data TestResult = Pass | Fail String

runTest :: String -> IO TestResult -> IO Bool
runTest name action = do
  result <- action `catch` \(e :: SomeException) ->
    pure (Fail $ "Exception: " <> show e)
  case result of
    Pass   -> do hPutStrLn stderr $ "  ✓ " <> name; pure True
    Fail m -> do hPutStrLn stderr $ "  ✗ " <> name <> ": " <> m; pure False

assert :: String -> Bool -> IO TestResult
assert _   True  = pure Pass
assert msg False = pure (Fail msg)

assertEqual :: (Show a, Eq a) => String -> a -> a -> IO TestResult
assertEqual label expected actual
  | expected == actual = pure Pass
  | otherwise = pure . Fail $
      label <> ": expected " <> show expected <> ", got " <> show actual


-- ---------------------------------------------------------------------------
-- Fixture source texts
-- ---------------------------------------------------------------------------

fixture01 :: Text
fixture01 = T.unlines
  [ "module Fixture01 where"
  , ""
  , "open import Agda.Builtin.Unit"
  , "open import AgdaDojang.Debug"
  , ""
  , "id : {A : Set} → A → A"
  , "id x = {!!}"
  , ""
  , "trivial : ⊤"
  , "trivial = {!!}"
  ]

fixtureLambda :: Text
fixtureLambda = T.unlines
  [ "module FixtureLambda where"
  , ""
  , "foo : {A : Set} → A → A"
  , "foo = λ x → {!!}"
  ]


-- ---------------------------------------------------------------------------
-- Tier 0: Pure tests (no Agda required)
-- ---------------------------------------------------------------------------

pureTests :: IO [Bool]
pureTests = do
  hPutStrLn stderr "\n── Pure unit tests ──"
  sequence
    [ runTest "findHoles: fixture01 has 2 holes" $ do
        let holes = findHoles PlainAgda fixture01
        assertEqual "hole count" 2 (length holes)

    , runTest "findHoles: fixtureLambda has 1 hole" $ do
        let holes = findHoles PlainAgda fixtureLambda
        assertEqual "hole count" 1 (length holes)

    , runTest "findNthHole: index 0 exists" $
        assert "should be Just" (isJust $ findNthHole PlainAgda 0 fixture01)

    , runTest "findNthHole: index 99 is Nothing" $
        assert "should be Nothing" (isNothing $ findNthHole PlainAgda 99 fixture01)

    , runTest "injectReportExpr: replaces hole with macro" $ do
        case injectReportExpr (reportExpr defaultConfig) PlainAgda 0 fixture01 of
          Nothing -> pure (Fail "injectReportExpr returned Nothing")
          Just patched -> assert "should contain reportGoalCtx"
            ("reportGoalCtx ?" `T.isInfixOf` patched)

    , runTest "substituteHole: replaces hole with candidate" $ do
        case substituteHole PlainAgda 0 "x" fixture01 of
          Nothing -> pure (Fail "substituteHole returned Nothing")
          Just patched -> do
            assert "should contain 'x' in place of hole"
              ("id x = x" `T.isInfixOf` patched)

    , runTest "parseGoalContext: basic marker block" $ do
        let stderr' = T.unlines
              [ "noise before"
              , "AGDADOJANG_REQ_BEGIN"
              , "AGDADOJANG_GOAL: A"
              , "AGDADOJANG_CTX_BEGIN"
              , "AGDADOJANG_CTX:0:visible:x: A"
              , "AGDADOJANG_CTX:1:hidden:A: Set₀"
              , "AGDADOJANG_REQ_END"
              , "noise after"
              ]
        case parseGoalContext stderr' of
          Nothing -> pure (Fail "parseGoalContext returned Nothing")
          Just (goal, ctx) -> do
            r1 <- assertEqual "goal" "A" goal
            case r1 of
              Fail m -> pure (Fail m)
              Pass -> do
                r2 <- assertEqual "ctx length" 2 (length ctx)
                case r2 of
                  Fail m -> pure (Fail m)
                  Pass ->
                    case ctx of
                      (c:_) -> assertEqual "ctx[0].name" "x" (ctxName c)
                      []    -> pure (Fail "context was empty")

    , runTest "parseGoalContext: multiline goal" $ do
        let stderr' = T.unlines
              [ "AGDADOJANG_REQ_BEGIN"
              , "AGDADOJANG_GOAL: ¬ (x ∧ y) ≈"
              , "  ¬ x ∨ ¬ y"
              , "AGDADOJANG_CTX_BEGIN"
              , "AGDADOJANG_CTX:0:visible:y: Bool"
              , "AGDADOJANG_REQ_END"
              ]
        case parseGoalContext stderr' of
          Nothing -> pure (Fail "parseGoalContext returned Nothing")
          Just (goal, _) ->
            assert "goal should contain ∨" ("∨" `T.isInfixOf` goal)

    , runTest "parseGoalContext: no markers → Nothing" $
        assert "should be Nothing" (isNothing $ parseGoalContext "no markers here")

    -- ensureDebugImport: the get_goal import-injection heuristic (issue #66 review).
    , runTest "ensureDebugImport: no-op when already imported" $ do
        let s = T.unlines
              [ "module M where", "open import AgdaDojang.Debug", "foo = {!!}" ]
        assertEqual "unchanged" s (ensureDebugImport PlainAgda s)

    , runTest "ensureDebugImport: recognizes a private-qualified import (no duplicate)" $ do
        let s = T.unlines
              [ "module M where", "private open import AgdaDojang.Debug", "foo = {!!}" ]
        assertEqual "unchanged" s (ensureDebugImport PlainAgda s)

    , runTest "ensureDebugImport: a longer name (.Debug.Extra) is not the module" $ do
        let s = T.unlines
              [ "module M where", "open import AgdaDojang.Debug.Extra", "foo = {!!}" ]
        assert "injects the real import"
          ("open import AgdaDojang.Debug" `elem` T.lines (ensureDebugImport PlainAgda s))

    , runTest "ensureDebugImport: a comment mention does not count as an import" $ do
        let s = T.unlines
              [ "module M where"
              , "open import Data.Nat  -- also see AgdaDojang.Debug"
              , "foo = {!!}" ]
        assert "injects the real import"
          ("open import AgdaDojang.Debug" `elem` T.lines (ensureDebugImport PlainAgda s))

    , runTest "ensureDebugImport: 'where' in a header comment does not misplace the import" $ do
        let inp = [ "module M"
                  , "  {a : Level}  -- a level where needed"
                  , "  (X : Set a)"
                  , "  where"
                  , "foo = {!!}" ]
            out = T.lines (ensureDebugImport PlainAgda (T.unlines inp))
        r1 <- assert "header block is intact" (take 4 out == take 4 inp)
        case r1 of
          Fail m -> pure (Fail m)
          Pass   -> assert "import sits just after the real where"
                      (length out > 4 && out !! 4 == "open import AgdaDojang.Debug")

    , runTest "ensureDebugImport: a nested-module import does not suppress injection" $ do
        let s = T.unlines
              [ "module Top where"
              , "module Inner where"
              , "  open import AgdaDojang.Debug"
              , "foo = {!!}" ]
            out = T.lines (ensureDebugImport PlainAgda s)
        r1 <- assert "injects at top level, right after the header"
                (length out > 1 && out !! 1 == "open import AgdaDojang.Debug")
        case r1 of
          Fail m -> pure (Fail m)
          Pass   -> assert "the nested import is left in place"
                      ("  open import AgdaDojang.Debug" `elem` out)

    -- moduleNameOf: the goal's `module` field is the declared name, not the base name.
    , runTest "moduleNameOf: hierarchical name from the header" $
        assertEqual "name" (Just "FLRP.Bridge")
          (moduleNameOf (T.unlines [ "module FLRP.Bridge where", "foo = {!!}" ]))

    , runTest "moduleNameOf: parameterised header, comment ignored" $
        assertEqual "name" (Just "M")
          (moduleNameOf (T.unlines
            [ "module M {a : Level} where  -- not FLRP.Bridge", "x = {!!}" ]))

    , runTest "moduleNameOf: no header → Nothing" $
        assertEqual "name" Nothing
          (moduleNameOf (T.unlines [ "-- just a comment", "x = 1" ]))

    -- fill_hole verdict classification (issue #69): whitelist, not blacklist.
    , runTest "errorTagsOf: collects error names in order, skips warnings" $
        assertEqual "tags" ["UnsolvedMetaVariables", "UnsolvedInteractionMetas"]
          (errorTagsOf (T.unlines
            [ "Checking M (/tmp/M.agda)."
            , "/tmp/M.agda:11.5-17: error: [UnsolvedMetaVariables]"
            , "Unsolved metas at the following locations:"
            , "  /tmp/M.agda:11.5-17"
            , "/tmp/M.agda:3.1-10: warning: [UnknownFixityInMixfixDecl]"
            , "/tmp/M.agda:14.5-9: error: [UnsolvedInteractionMetas]"
            ]))

    , runTest "onlyOpenHoleErrors: only interaction metas → tolerated" $
        assert "should tolerate" (onlyOpenHoleErrors (T.unlines
          [ "/tmp/M.agda:14.5-9: error: [UnsolvedInteractionMetas]"
          , "Unsolved interaction metas at the following locations:"
          , "  /tmp/M.agda:14.5-9"
          ]))

    , runTest "onlyOpenHoleErrors: candidate-left metas are NOT tolerated (#69)" $
        assert "should not tolerate" (not (onlyOpenHoleErrors (T.unlines
          [ "/tmp/M.agda:11.5-17: error: [UnsolvedMetaVariables]"
          , "/tmp/M.agda:14.5-9: error: [UnsolvedInteractionMetas]"
          ])))

    , runTest "onlyOpenHoleErrors: a type error is NOT tolerated" $
        assert "should not tolerate" (not (onlyOpenHoleErrors
          "/tmp/M.agda:7.9-11: error: [UnequalTerms]"))

    , runTest "onlyOpenHoleErrors: unparsable failure output fails closed" $
        assert "should not tolerate" (not (onlyOpenHoleErrors
          "agda: internal panic, no error header here"))
    ]



-- ---------------------------------------------------------------------------
-- Tier 1a: Hole-model tests (issues #71/#73; IO for fixture reads, no Agda)
--
-- The hole model must (a) recognize every Agda hole syntax — {!!}, {! … !}
-- with nesting, standalone ? — (b) never count tokens in comments, strings,
-- pragmas, or literate prose, and (c) report spans in literate-file
-- coordinates.  The literate fixtures under test/resources/ carry decoy
-- tokens in prose above and below their single {! zero !} hole; tier 2d
-- verifies the same fixtures against real Agda for parity.
-- ---------------------------------------------------------------------------

-- | The source text a hole span covers.
sliceSpan :: Text -> HoleSpan -> Text
sliceSpan src h = T.take (hsEnd h - hsStart h) (T.drop (hsStart h) src)

-- | Expected position of the unique @n = {! zero !}@ hole in a literate
-- fixture, computed from the file text itself: (line, col) of the @{@,
-- 1-based, in literate-file coordinates.
expectedHolePos :: Text -> Maybe (Int, Int)
expectedHolePos src =
  case T.breakOn "n = {! zero !}" src of
    (_, rest) | T.null rest -> Nothing
    (pre, _) ->
      let toHole   = pre <> "n = "
          nLines   = T.count "\n" toHole
          lastLine = T.takeWhileEnd (/= '\n') toHole
      in  Just (nLines + 1, T.length lastLine + 1)

-- | Run one literate-fixture regression: exactly one hole, spanning
-- @{! zero !}@, at the position the literate file itself dictates.
literateFixtureTest :: FilePath -> IO TestResult
literateFixtureTest path = do
  src <- TIO.readFile path
  let holes = findHoles (flavourOf path) src
  case (holes, expectedHolePos src) of
    (_, Nothing) -> pure (Fail "fixture lacks the n = {! zero !} line")
    ([h], Just (ln, col)) -> do
      r1 <- assertEqual "hole slice" "{! zero !}" (sliceSpan src h)
      case r1 of
        Fail m -> pure (Fail m)
        Pass   -> assertEqual "(line, col)" (ln, col) (hsLine h, hsCol h)
    (hs, _) -> pure . Fail $ "expected exactly 1 hole, got " <> show (length hs)

holeModelTests :: IO [Bool]
holeModelTests = do
  hPutStrLn stderr "\n── Hole-model tests (tier 1a: no Agda, #71/#73) ──"
  variantsSrc <- TIO.readFile ("test" </> "resources" </> "HoleVariants.agda")
  sequence
    [ runTest "findHoles: HoleVariants has exactly the 4 real holes, in order" $ do
        let holes = findHoles PlainAgda variantsSrc
        assertEqual "hole slices" ["{!!}", "{! !}", "{!zero!}", "?"]
          (map (sliceSpan variantsSrc) holes)

    , runTest "findHoles: comment/string decoys alone contribute zero holes" $
        assertEqual "hole count" 0 . length . findHoles PlainAgda $ T.unlines
          [ "-- line comment decoys: {!!} and {! x !} and ?"
          , "{- block {!!} comment -}"
          , "s = \"a string {!!} with ? inside\""
          ]

    , runTest "findHoles: nested block comments hide holes to the outer close" $
        assertEqual "hole count" 1 . length . findHoles PlainAgda $
          "{- a {- nested {!!} -} still comment {!!} -} x = ?\n"

    , runTest "findHoles: a nested {! {! !} !} is a single hole" $ do
        let src   = "x = {! {! !} !}\n"
            holes = findHoles PlainAgda src
        assertEqual "hole slices" ["{! {! !} !}"] (map (sliceSpan src) holes)

    , runTest "findHoles: ? is a hole only as a lexically separate token" $ do
        let count = length . findHoles PlainAgda
        r1 <- assertEqual "op? / _≟_ / ?? are names" 0
                (count "f = op? x\ng = _≟_\nh = a ?? b\n")
        case r1 of
          Fail m -> pure (Fail m)
          Pass   -> assertEqual "bare / parenthesized / eol ? are holes" 3
                      (count "x = ?\ny = f (?) z\nw = λ t → ?\n")

    , runTest "findHoles: -- comments only at a token boundary (x--y is a name)" $ do
        let count = length . findHoles PlainAgda
        r1 <- assertEqual "x--y stays code" 1 (count "x--y = {!!}\n")
        case r1 of
          Fail m -> pure (Fail m)
          Pass   -> assertEqual "trailing comment hides its hole" 1
                      (count "x = {!!} -- not this one: {!!}\n")

    , runTest "findHoles: pragmas are skipped" $
        assertEqual "hole count" 1
          (length (findHoles PlainAgda "{-# OPTIONS --safe #-}\nx = ?\n"))

    -- Backslash is a name character (Lexer.x: $idchar includes \\, and
    -- @start admits \\ + non-alpha), so \? is one identifier, not a hole;
    -- lambda still works because \x cannot start a name.
    , runTest "findHoles: \\? is a name, not a hole; ? after λ-body space still is" $ do
        let count = length . findHoles PlainAgda
        r1 <- assertEqual "\\? applied / bare" 0 (count "f = \\? x\ng = \\?\n")
        case r1 of
          Fail m -> pure (Fail m)
          Pass   -> assertEqual "lambda body hole" 1 (count "h = \\x → ?\n")

    , runTest "findHoles: span carries the real (line, col) of a ? hole" $ do
        let src = "module M where\n\nd : Nat\nd = ?\n"
        case findHoles PlainAgda src of
          [h] -> assertEqual "(line, col, start, end)" (4, 5, 28, 29)
                   (hsLine h, hsCol h, hsStart h, hsEnd h)
          hs  -> pure . Fail $ "expected 1 hole, got " <> show (length hs)

    , runTest "substituteHole: splices the actual span of a ? hole" $
        assertEqual "patched" (Just "d = zero\n")
          (substituteHole PlainAgda 0 "zero" "d = ?\n")

    , runTest "substituteHole: splices the actual span of a {! e !} hole" $
        assertEqual "patched" (Just "n = zero\n")
          (substituteHole PlainAgda 0 "zero" "n = {! zero !}\n")

    , runTest "substituteHole: targets the real hole, not a preceding comment token" $
        case substituteHole PlainAgda 0 "42" variantsSrc of
          Nothing -> pure (Fail "substituteHole returned Nothing")
          Just patched -> do
            r1 <- assert "a = 42 spliced" ("a = 42" `T.isInfixOf` patched)
            case r1 of
              Fail m -> pure (Fail m)
              Pass   -> assert "comment decoys untouched"
                ("block-comment decoys: {!!}" `T.isInfixOf` patched)

    , runTest "injectReportExpr: saturated macro call over a ? hole (#70 shape)" $
        assertEqual "patched" (Just "d = reportGoalCtx ?\n")
          (injectReportExpr "reportGoalCtx" PlainAgda 0 "d = ?\n")

    , runTest "flavourOf: extension mapping" $
        assertEqual "flavours"
          [ PlainAgda, LiterateTeX, LiterateTeX, LiterateMd, LiterateMd
          , LiterateRsT, LiterateOrg, LiterateTree, PlainAgda
          ]
          (map flavourOf
            [ "A.agda", "A.lagda", "A.lagda.tex", "A.lagda.md", "A.lagda.typ"
            , "A.lagda.rst", "A.lagda.org", "A.lagda.tree", "A.txt"
            ])

    , runTest "maskNonCode: preserves length and blanks prose (md)" $ do
        src <- TIO.readFile ("test" </> "resources" </> "LiterateMd.lagda.md")
        let masked = maskNonCode LiterateMd src
        r1 <- assertEqual "length preserved" (T.length src) (T.length masked)
        case r1 of
          Fail m -> pure (Fail m)
          Pass -> do
            r2 <- assert "code survives" ("module LiterateMd where" `T.isInfixOf` masked)
            case r2 of
              Fail m -> pure (Fail m)
              Pass   -> assert "prose is blanked" (not ("Prose" `T.isInfixOf` masked))

    , runTest "literate regression: .lagda.md (prose decoys above and below)" $
        literateFixtureTest ("test" </> "resources" </> "LiterateMd.lagda.md")

    , runTest "literate regression: .lagda (TeX; commented \\begin{code} decoy)" $
        literateFixtureTest ("test" </> "resources" </> "LiterateTex.lagda")

    , runTest "literate regression: .lagda.rst" $
        literateFixtureTest ("test" </> "resources" </> "LiterateRst.lagda.rst")

    , runTest "literate regression: .lagda.org" $
        literateFixtureTest ("test" </> "resources" </> "LiterateOrg.lagda.org")

    , runTest "literate regression: .lagda.tree (Forester)" $
        literateFixtureTest ("test" </> "resources" </> "LiterateTree.lagda.tree")

    , runTest "literate: a non-Agda ```haskell fence stays prose (md)" $ do
        src <- TIO.readFile ("test" </> "resources" </> "LiterateMd.lagda.md")
        let masked = maskNonCode LiterateMd src
        assert "haskell block is blanked" (not ("print" `T.isInfixOf` masked))

    -- Agda's org begin regex has a greedy (.*) prefix, so a later
    -- "#+begin_src agda2" occurrence with trailing whitespace opens the
    -- block even when an earlier occurrence fails the whitespace check.
    , runTest "literate: org begin marker may match after a failed occurrence" $ do
        let src = T.unlines
              [ "text #+begin_src agda2x #+begin_src agda2"
              , "x = ?"
              , "#+end_src"
              ]
        assertEqual "hole count" 1 (length (findHoles LiterateOrg src))

    -- ensureDebugImport must scan the masked source: a prose line starting
    -- with "module" is not the header, and the import must land inside the
    -- code region, right after the real header.
    , runTest "ensureDebugImport: literate prose 'module …' is not the header" $ do
        let src = T.unlines
              [ "module Example where — prose decoy"
              , "```agda"
              , "module M where"
              , "x = ?"
              , "```"
              ]
            out = T.lines (ensureDebugImport LiterateMd src)
        assertEqual "import follows the real header"
          (Just "open import AgdaDojang.Debug") (nth 3 out)

    -- ensureDebugImport must keep the inserted import inside an
    -- indentation-delimited code block (.lagda.rst): an unindented line
    -- would terminate the block.
    , runTest "ensureDebugImport: rst import inherits the block's indentation" $ do
        let src = T.unlines
              [ "The code follows::"
              , ""
              , "  module M where"
              , "  x = ?"
              ]
            out = T.lines (ensureDebugImport LiterateRsT src)
        assertEqual "indented import follows the header"
          (Just "  open import AgdaDojang.Debug") (nth 3 out)
    ]
  where
    nth i xs = if i < length xs then Just (xs !! i) else Nothing


-- ---------------------------------------------------------------------------
-- Tier 1b: Corpus / search tests (IO for file read, no Agda required)
--
-- These tests load a synthetic JSONL fixture and exercise the three search
-- tools: search_by_name, search_by_type, get_dependencies.
-- ---------------------------------------------------------------------------
-- | Path to the synthetic JSONL fixture (relative to agda-mcp/).
corpusFixturePath :: FilePath
corpusFixturePath = "test/resources/corpus-fixture.jsonl"
-- | Helper: load the corpus fixture and run a test against the index.
withCorpus :: String -> (CorpusIndex -> IO TestResult) -> IO Bool
withCorpus name f = runTest name $ do
  result <- loadCorpus corpusFixturePath
  case result of
    Left err  -> pure (Fail $ "loadCorpus failed: " <> T.unpack err)
    Right idx -> f idx
corpusTests :: IO [Bool]
corpusTests = do
  hPutStrLn stderr "\n── Corpus / search tests (tier 1b: no Agda) ──"
  sequence
    [ -- Corpus loading
      withCorpus "loadCorpus: fixture has 24 entries" $ \idx ->
        assertEqual "entry count" 24 (ciSize idx)
    , withCorpus "loadCorpus: expected keys present" $ \idx ->
        let entries = ciEntries idx
        in assert "Algebra, hom, Con should be present"
             (  Map.member "Algebras.Basic.Algebra" entries
             && Map.member "Homomorphisms.Basic.hom" entries
             && Map.member "Congruences.Basic.Con" entries
             )
    , withCorpus "loadCorpus: entry fields correct (Algebra)" $ \idx ->
        case Map.lookup "Algebras.Basic.Algebra" (ciEntries idx) of
          Nothing -> pure (Fail "Algebra entry not found")
          Just e  -> assert "field checks"
            (  cePrettyName e == "Algebra"
            && cePrettyModule e == "Algebras.Basic"
            && ceDefKind e == "record"
            && "Signature" `elem` ceDependencies e
            && not (ceHasBody e)
            )
    , withCorpus "loadCorpus: entry with body (Domain)" $ \idx ->
        case Map.lookup "Algebras.Basic.Domain" (ciEntries idx) of
          Nothing -> pure (Fail "Domain entry not found")
          Just e  -> assert "should have body" (ceHasBody e && isJust (ceBody e))
      -- search_by_name
    , withCorpus "search_by_name: 'Algebra' finds ≥1" $ \idx ->
        let results = searchByName "Algebra" Nothing idx
        in assert ("got " <> show (length results)) (length results >= 1)
    , withCorpus "search_by_name: 'hom' finds ≥3 (hom, is-homomorphism, ∘-hom)" $ \idx ->
        let results = searchByName "hom" Nothing idx
        in assert ("got " <> show (length results)) (length results >= 3)
    , withCorpus "search_by_name: case insensitive" $ \idx ->
        let upper = searchByName "ALGEBRA" Nothing idx
            lower = searchByName "algebra" Nothing idx
        in assertEqual "count should match" (length upper) (length lower)
    , withCorpus "search_by_name: no results for nonexistent" $ \idx ->
        let results = searchByName "nonexistent_xyz_999" Nothing idx
        in assert "should be empty" (null results)
    , withCorpus "search_by_name: respects limit" $ \idx ->
        let results = searchByName "a" (Just 3) idx
        in assert ("got " <> show (length results)) (length results <= 3)
    , withCorpus "search_by_name: unicode '≅' finds ≥4" $ \idx ->
        let results = searchByName "≅" Nothing idx
        in assert ("got " <> show (length results)) (length results >= 4)
    , withCorpus "search_by_name: module prefix 'Congruences'" $ \idx ->
        let results = searchByName "Congruences" Nothing idx
        in assert ("got " <> show (length results)) (length results >= 3)
      -- search_by_type
    , withCorpus "search_by_type: 'Algebra' in type finds ≥10" $ \idx ->
        let results = searchByType "Algebra" Nothing idx
        in assert ("got " <> show (length results)) (length results >= 10)
    , withCorpus "search_by_type: '→ Domain' finds ≥1" $ \idx ->
        let results = searchByType "→ Domain" Nothing idx
        in assert ("got " <> show (length results)) (length results >= 1)
    , withCorpus "search_by_type: 'Monad' finds 0" $ \idx ->
        let results = searchByType "Monad" Nothing idx
        in assert "should be empty" (null results)
    , withCorpus "search_by_type: case insensitive" $ \idx ->
        let upper = searchByType "SET" Nothing idx
            lower = searchByType "set" Nothing idx
        in assertEqual "count should match" (length upper) (length lower)
      -- get_dependencies
    , withCorpus "get_dependencies: ∘-hom depends on Algebra and hom" $ \idx ->
        case getDeps "Homomorphisms.Basic.∘-hom" Nothing idx of
          Left err  -> pure (Fail $ T.unpack err)
          Right dep -> assert "deps check"
            ("Algebra" `elem` depDependencies dep && "hom" `elem` depDependencies dep)
    , withCorpus "get_dependencies: not found → Left" $ \idx ->
        assert "should be Left" (isLeft $ getDeps "Nonexistent.foo" Nothing idx)
    , withCorpus "get_dependencies: expand=true includes Algebra neighbor" $ \idx ->
        case getDeps "Homomorphisms.Basic.∘-hom" (Just True) idx of
          Left err  -> pure (Fail $ T.unpack err)
          Right dep ->
            let names = map srPrettyQname (depNeighbors dep)
            in assert ("neighbors: " <> show names)
                 (any ("Algebra" `T.isInfixOf`) names)
    , withCorpus "get_dependencies: expand=false → empty neighbors" $ \idx ->
        case getDeps "Homomorphisms.Basic.hom" (Just False) idx of
          Left err  -> pure (Fail $ T.unpack err)
          Right dep -> assert "should be empty" (null (depNeighbors dep))
      -- Tool handler layer
    , withCorpus "handleSearchByName: 'Term' finds ≥2" $ \idx ->
        let params = SearchByNameParams { sbnPattern = "Term", sbnLimit = Just 10 }
        in case handleSearchByName idx params of
             Left err -> pure (Fail $ T.unpack err)
             Right rs -> assert ("got " <> show (length rs)) (length rs >= 2)
    , withCorpus "handleSearchByType: 'Pred' finds ≥1" $ \idx ->
        let params = SearchByTypeParams { sbtPattern = "Pred", sbtLimit = Just 5 }
        in case handleSearchByType idx params of
             Left err -> pure (Fail $ T.unpack err)
             Right rs -> assert ("got " <> show (length rs)) (length rs >= 1)
    , withCorpus "handleGetDependencies: free-lift depends on Term" $ \idx ->
        let params = GetDependenciesParams
              { gdpName = "Terms.Operations.free-lift", gdpExpand = Just True }
        in case handleGetDependencies idx params of
             Left err -> pure (Fail $ T.unpack err)
             Right dep -> assert "should depend on Term"
               ("Term" `elem` depDependencies dep)
    ]


-- ---------------------------------------------------------------------------
-- Tier 2: Subprocess tests (needs agda + agda-dojang on PATH)
-- ---------------------------------------------------------------------------

-- | probeAgdaEnv: check whether we can run integration tests
--
-- Checks the following:
--   1. agda binary is on PATH
--   2. fixture file exists
--   3. agda-dojang libraries file exists
-- Returns @Just (cfg, fixturePath, repoRoot)@ if everything is available,
-- @Nothing@ otherwise.
probeAgdaEnv :: IO (Maybe (AgdaConfig, FilePath, FilePath))
probeAgdaEnv = do
  mAgda <- findExecutable "agda"
  case mAgda of
    Nothing -> do
      hPutStrLn stderr "  [skip] agda not found on PATH"
      pure Nothing
    Just agdaPath -> do
      -- Resolve paths relative to repo root.
      -- When cabal test runs, cwd is typically agda-mcp/.
      cwd <- getCurrentDirectory
      let repoRoot    = takeDirectory cwd  -- go up from agda-mcp/
          fixturePath = repoRoot </> "agda-dojang" </> "data" </> "fixtures" </> "Fixture01.agda"
          -- The project-wide Agda libraries file lives at the repo root
          -- (agda/libraries), generated by the flake shellHook and used by
          -- .mcp.json and scripts/run-server.sh alike — not under agda-dojang/.
          libFile     = repoRoot </> "agda" </> "libraries"
          agdaDir     = repoRoot </> "agda-dojang" </> "agda"
      fixtureExists <- doesFileExist fixturePath
      libExists     <- doesFileExist libFile
      if not fixtureExists
        then do
          hPutStrLn stderr $ "  [skip] fixture not found: " <> fixturePath
          pure Nothing
        else if not libExists
          then do
            hPutStrLn stderr $ "  [skip] libraries file not found: " <> libFile
            pure Nothing
          else do
            let cfg = defaultConfig
                  { agdaBin   = agdaPath
                  , agdaFlags =
                      [ "-i", agdaDir
                      , "--library-file=" <> libFile
                      , "-l", "agda-dojang"
                      , "-l", "standard-library"
                      ]
                  }
            pure (Just (cfg, fixturePath, repoRoot))


-- | integrationTests: Tier 2 tests that call tool handlers on real fixture files
-- with a real Agda binary.
integrationTests :: AgdaConfig -> FilePath -> FilePath -> IO [Bool]
integrationTests cfg fixturePath repoRoot = do
  hPutStrLn stderr "\n── Integration tests (tier 2: Agda subprocess) ──"
  base <- sequence
    [ -- Issue #70 regression: the goal must be the hole's actual expected type,
      -- not the reporting macro's own unsolved application type.  Asserting the
      -- exact strings (rather than mere non-emptiness) is what catches a macro
      -- that "reports something" but reports the wrong thing.
      runTest "get_goal: Fixture01 hole 0 goal is exactly \"A\" (#70)" $ do
        let params = GetGoalParams { ggFilePath = fixturePath, ggHoleIndex = 0 }
        result <- handleGetGoal cfg params
        case result of
          Left err -> pure (Fail $ "get_goal failed: " <> T.unpack err)
          Right info -> assertEqual "goal" "A" (giGoal info)

    , runTest "get_goal: Fixture01 hole 1 goal is exactly \"⊤\" (#70)" $ do
        let params = GetGoalParams { ggFilePath = fixturePath, ggHoleIndex = 1 }
        result <- handleGetGoal cfg params
        case result of
          Left err -> pure (Fail $ "get_goal failed: " <> T.unpack err)
          Right info -> assertEqual "goal" "⊤" (giGoal info)

    , runTest "get_goal: Fixture01 hole 2 goal is exactly \"x ≡ x\" (#70)" $ do
        let params = GetGoalParams { ggFilePath = fixturePath, ggHoleIndex = 2 }
        result <- handleGetGoal cfg params
        case result of
          Left err -> pure (Fail $ "get_goal failed: " <> T.unpack err)
          Right info -> assertEqual "goal" "x ≡ x" (giGoal info)

    , runTest "get_goal: Fixture01 hole 0 context contains 'x : A'" $ do
        let params = GetGoalParams { ggFilePath = fixturePath, ggHoleIndex = 0 }
        result <- handleGetGoal cfg params
        case result of
          Left err -> pure (Fail $ "get_goal failed: " <> T.unpack err)
          Right info ->
            let names = map ctxName (giContext info)
            in  assert "'x' should be in context" ("x" `elem` names)

    , runTest "fill_hole: Fixture01 hole 0 with 'x' succeeds" $ do
        let params = FillHoleParams
              { fhFilePath  = fixturePath
              , fhHoleIndex = 0
              , fhCandidate = "x"
              }
        result <- handleFillHole cfg params
        case result of
          Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack err)
          Right fr -> assertEqual "status" FillOk (frStatus fr)

    , runTest "fill_hole: Fixture01 hole 0 with 'tt' fails (type error)" $ do
        let params = FillHoleParams
              { fhFilePath  = fixturePath
              , fhHoleIndex = 0
              , fhCandidate = "tt"
              }
        result <- handleFillHole cfg params
        case result of
          Left err -> pure (Fail $ "fill_hole failed unexpectedly: " <> T.unpack err)
          Right fr -> assertEqual "status" FillTypeError (frStatus fr)

    , runTest "check_file: Fixture01 reports holes" $ do
        let params = CheckFileParams { cfFilePath = fixturePath }
        result <- handleCheckFile cfg params
        case result of
          Left err -> pure (Fail $ "check_file failed: " <> T.unpack err)
          Right fcr ->
            assert "should report at least 1 hole" (fcrHolesCount fcr > 0)

    , runTest "get_diagnostics: Fixture01 reports holes" $ do
        let params = GetDiagnosticsParams { gdFilePath = fixturePath }
        result <- handleGetDiagnostics cfg params
        case result of
          Left err -> pure (Fail $ "get_diagnostics failed: " <> T.unpack err)
          Right dr ->
            assert "should report at least 1 hole" (not . null $ drHoles dr)
    ]
  hier <- hierIntegrationTests cfg repoRoot
  verdict <- fillVerdictTests cfg
  holes <- holeModelIntegrationTests cfg
  pure (base <> hier <> verdict <> holes)


-- | hierIntegrationTests: issue #66 regression.
--
-- get_goal / fill_hole must work on a hierarchically-named module embedded in a
-- library that imports across directories (the shape that broke the old temp-copy
-- path with ModuleDefinedInOtherFile).  The fixture library's src root is placed on
-- the include path via @-i@, the way a caller's @-l \<lib\>@ supplies it in real use.
-- The fixture deliberately does not import @AgdaDojang.Debug@, so get_goal here also
-- exercises the transient import injection.  Skipped (with a note) if absent.
hierIntegrationTests :: AgdaConfig -> FilePath -> IO [Bool]
hierIntegrationTests cfg repoRoot = do
  let hierSrc = repoRoot </> "agda-dojang" </> "data" </> "fixtures"
                        </> "hier-lib" </> "src"
      useFile = hierSrc </> "Proofs" </> "Use.agda"
      hierCfg = cfg { agdaFlags = agdaFlags cfg <> ["-i", hierSrc] }
  exists <- doesFileExist useFile
  if not exists
    then do
      hPutStrLn stderr $ "\n  [skip] hier fixture not found: " <> useFile
      pure []
    else do
      hPutStrLn stderr
        "\n── Integration tests (tier 2b: library-embedded module, #66) ──"
      before <- BS.readFile useFile
      results <- sequence
        [ runTest "get_goal: Proofs.Use (hierarchical) returns a non-empty goal" $ do
            let params = GetGoalParams { ggFilePath = useFile, ggHoleIndex = 0 }
            result <- handleGetGoal hierCfg params
            case result of
              Left err   -> pure (Fail $ "get_goal failed: " <> T.unpack err)
              Right info -> assert "goal should be non-empty" (not . T.null $ giGoal info)

        , runTest "get_goal: Proofs.Use reports its declared (hierarchical) module name" $ do
            let params = GetGoalParams { ggFilePath = useFile, ggHoleIndex = 0 }
            result <- handleGetGoal hierCfg params
            case result of
              Left err   -> pure (Fail $ "get_goal failed: " <> T.unpack err)
              Right info -> assertEqual "module" (Just "Proofs.Use") (giModule info)

        , runTest "get_goal: Proofs.Use context contains 'x' (Debug import injected)" $ do
            let params = GetGoalParams { ggFilePath = useFile, ggHoleIndex = 0 }
            result <- handleGetGoal hierCfg params
            case result of
              Left err   -> pure (Fail $ "get_goal failed: " <> T.unpack err)
              Right info ->
                assert "'x' should be in context"
                  ("x" `elem` map ctxName (giContext info))

        , runTest "fill_hole: Proofs.Use with cross-directory 'thing' succeeds" $ do
            let params = FillHoleParams
                  { fhFilePath = useFile, fhHoleIndex = 0, fhCandidate = "thing" }
            result <- handleFillHole hierCfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack err)
              Right fr -> assertEqual "status" FillOk (frStatus fr)

        , runTest "fill_hole: Proofs.Use with ill-typed 'tt' is a type error" $ do
            let params = FillHoleParams
                  { fhFilePath = useFile, fhHoleIndex = 0, fhCandidate = "tt" }
            result <- handleFillHole hierCfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed unexpectedly: " <> T.unpack err)
              Right fr -> assertEqual "status" FillTypeError (frStatus fr)
        ]
      -- The transiently-patched source must be restored byte-for-byte.
      after <- BS.readFile useFile
      restored <- runTest "get_goal/fill_hole restore the source file exactly" $
        assert "file should be byte-for-byte unchanged after in-place tools"
               (before == after)
      pure (results <> [restored])


-- | fillVerdictTests: issue #69 regression.
--
-- A candidate that typechecks but leaves an unsolved implicit meta must be a
-- type_error, not ok — the old tag blacklist reported ok whenever the other
-- open hole's [UnsolvedInteractionMetas] appeared alongside an unlisted error
-- class.  The fixture's @implicitOnly : {n : Nat} → Nat@ leaves @_n@ unsolved
-- when used bare, which is exactly the FLRP "implicits under a defined
-- function" pattern from the field report (docs/feedback/, § 7.2.2).  The
-- companion cases pin the tolerance that must survive: a well-typed candidate
-- with another hole still open, and a candidate that introduces its own
-- sub-hole (a refinement).
fillVerdictTests :: AgdaConfig -> IO [Bool]
fillVerdictTests cfg = do
  let fixture = "test" </> "resources" </> "TwoHoles.agda"
  exists <- doesFileExist fixture
  if not exists
    then do
      hPutStrLn stderr $ "\n  [skip] fixture not found: " <> fixture
      pure []
    else do
      hPutStrLn stderr
        "\n── Integration tests (tier 2c: fill_hole verdict, #69) ──"
      before <- BS.readFile fixture
      results <- sequence
        [ runTest "fill_hole: candidate leaving an unsolved meta is a type error" $ do
            let params = FillHoleParams
                  { fhFilePath = fixture, fhHoleIndex = 0, fhCandidate = "implicitOnly" }
            result <- handleFillHole cfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed unexpectedly: " <> T.unpack err)
              Right fr -> do
                r1 <- assertEqual "status" FillTypeError (frStatus fr)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assert "message should name the unsolved metas"
                    (maybe False ("UnsolvedMetaVariables" `T.isInfixOf`) (frMessage fr))

        , runTest "fill_hole: well-typed candidate with another hole open stays ok" $ do
            let params = FillHoleParams
                  { fhFilePath = fixture, fhHoleIndex = 0, fhCandidate = "zero" }
            result <- handleFillHole cfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack err)
              Right fr -> assertEqual "status" FillOk (frStatus fr)

        , runTest "fill_hole: candidate introducing a new sub-hole stays ok" $ do
            let params = FillHoleParams
                  { fhFilePath = fixture, fhHoleIndex = 0, fhCandidate = "suc {!!}" }
            result <- handleFillHole cfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack err)
              Right fr -> assertEqual "status" FillOk (frStatus fr)

        -- Since issue #71, tracking matches tolerance: a `?` sub-hole the
        -- candidate introduces is both excused by the verdict and counted by
        -- remainingHoles — here hole h plus the new `?`.
        , runTest "fill_hole: a '?' sub-hole is tolerated AND counted (#71)" $ do
            let params = FillHoleParams
                  { fhFilePath = fixture, fhHoleIndex = 0, fhCandidate = "suc ?" }
            result <- handleFillHole cfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack err)
              Right fr -> do
                r1 <- assertEqual "status" FillOk (frStatus fr)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assertEqual "remainingHoles counts every hole syntax"
                              (Just 2) (frRemainingHoles fr)
        ]
      after <- BS.readFile fixture
      restored <- runTest "fill_hole verdict tests restore the fixture exactly" $
        assert "file should be byte-for-byte unchanged" (before == after)
      pure (results <> [restored])


-- | holeModelIntegrationTests: issues #71/#73 — the hole model against real
-- Agda.
--
-- The feedback loop, made a test: for every fixture in the matrix (plain
-- .agda with all four hole syntaxes plus decoys, and one literate fixture
-- per flavour), the scanner's enumeration must agree with the interaction
-- points batch Agda itself reports — same count, same (line, col) start
-- positions, in literate-file coordinates.  On top of parity: get_goal and
-- fill_hole must address non-{!!} holes (and behave identically on a
-- .lagda.md and its plain twin), a comment token preceding the first real
-- hole must not shift indices, prose tokens must not be addressable, and
-- in-place patching of non-{!!} holes must still restore files byte-exactly.
holeModelIntegrationTests :: AgdaConfig -> IO [Bool]
holeModelIntegrationTests cfg = do
  let resources = "test" </> "resources"
      variants  = resources </> "HoleVariants.agda"
      lagdaMd   = resources </> "LiterateMd.lagda.md"
      plainTwin = resources </> "HolePlain.agda"
      parityFixtures =
        [ variants
        , lagdaMd
        , resources </> "LiterateTex.lagda"
        , resources </> "LiterateRst.lagda.rst"
        , resources </> "LiterateOrg.lagda.org"
        , resources </> "LiterateTree.lagda.tree"
        ]
  exists <- mapM doesFileExist (parityFixtures <> [plainTwin])
  if not (and exists)
    then do
      hPutStrLn stderr "\n  [skip] hole-model fixtures not found"
      pure []
    else do
      hPutStrLn stderr
        "\n── Integration tests (tier 2d: hole model vs Agda, #71/#73) ──"
      parity <- mapM (agdaParityTest cfg) parityFixtures
      before <- mapM BS.readFile (parityFixtures <> [plainTwin])
      results <- sequence
        [ runTest "get_goal: the ? hole in HoleVariants (index 3) has goal Nat" $ do
            result <- handleGetGoal cfg GetGoalParams
              { ggFilePath = variants, ggHoleIndex = 3 }
            case result of
              Left err   -> pure (Fail $ "get_goal failed: " <> T.unpack err)
              Right info -> assertEqual "goal" "Nat" (giGoal info)

        , runTest "fill_hole: comment decoys do not shift hole indices (#71)" $ do
            -- Hole 0 (a = {!!}) is preceded by comment/string decoy tokens;
            -- remainingHoles == 3 proves the fill hit the real hole, not a
            -- decoy (writing into a comment would leave all 4 holes open).
            result <- handleFillHole cfg FillHoleParams
              { fhFilePath = variants, fhHoleIndex = 0, fhCandidate = "zero" }
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack err)
              Right fr -> do
                r1 <- assertEqual "status" FillOk (frStatus fr)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assertEqual "remainingHoles" (Just 3) (frRemainingHoles fr)

        , runTest "fill_hole: a standalone ? hole is addressable and fillable" $ do
            result <- handleFillHole cfg FillHoleParams
              { fhFilePath = variants, fhHoleIndex = 3, fhCandidate = "zero" }
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack err)
              Right fr -> do
                r1 <- assertEqual "status" FillOk (frStatus fr)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assertEqual "remainingHoles" (Just 3) (frRemainingHoles fr)

        , runTest "get_goal: {! zero !} in a .lagda.md ≡ the same code in a .agda" $ do
            mdGoal    <- handleGetGoal cfg GetGoalParams
              { ggFilePath = lagdaMd, ggHoleIndex = 0 }
            plainGoal <- handleGetGoal cfg GetGoalParams
              { ggFilePath = plainTwin, ggHoleIndex = 0 }
            case (mdGoal, plainGoal) of
              (Right md, Right plain) -> do
                r1 <- assertEqual "goals agree" (giGoal plain) (giGoal md)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assertEqual "goal" "Nat" (giGoal md)
              (Left err, _) -> pure (Fail $ "get_goal (.lagda.md) failed: " <> T.unpack err)
              (_, Left err) -> pure (Fail $ "get_goal (.agda) failed: " <> T.unpack err)

        , runTest "fill_hole: {! zero !} in a .lagda.md fills like in a .agda" $ do
            mdFill    <- handleFillHole cfg FillHoleParams
              { fhFilePath = lagdaMd, fhHoleIndex = 0, fhCandidate = "zero" }
            plainFill <- handleFillHole cfg FillHoleParams
              { fhFilePath = plainTwin, fhHoleIndex = 0, fhCandidate = "zero" }
            case (mdFill, plainFill) of
              (Right md, Right plain) -> do
                r1 <- assertEqual "status (.lagda.md)" FillOk (frStatus md)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass -> do
                    r2 <- assertEqual "status (.agda)" FillOk (frStatus plain)
                    case r2 of
                      Fail m -> pure (Fail m)
                      Pass   -> assertEqual "remainingHoles agree"
                                  (frRemainingHoles plain) (frRemainingHoles md)
              (Left err, _) -> pure (Fail $ "fill_hole (.lagda.md) failed: " <> T.unpack err)
              (_, Left err) -> pure (Fail $ "fill_hole (.agda) failed: " <> T.unpack err)

        -- get_goal on every remaining literate flavour: exercises the
        -- flavour-aware debug-import injection end-to-end — in particular
        -- the indentation-preserving insert that .lagda.rst requires.
        , runTest "get_goal: goal is Nat in .lagda, .lagda.rst, .lagda.org, .lagda.tree" $ do
            let files = [ resources </> "LiterateTex.lagda"
                        , resources </> "LiterateRst.lagda.rst"
                        , resources </> "LiterateOrg.lagda.org"
                        , resources </> "LiterateTree.lagda.tree"
                        ]
            results <- mapM (\f -> handleGetGoal cfg GetGoalParams
                              { ggFilePath = f, ggHoleIndex = 0 }) files
            let bad = [ (takeFileName f, r)
                      | (f, r) <- zip files results
                      , either (const True) ((/= "Nat") . giGoal) r
                      ]
            assert ("failures: " <> show (map fst bad)) (null bad)

        , runTest "fill_hole: prose {!!} decoys are not addressable (#73)" $ do
            -- LiterateMd has exactly one real hole; its prose decoys must
            -- not create an index 1.
            result <- handleFillHole cfg FillHoleParams
              { fhFilePath = lagdaMd, fhHoleIndex = 1, fhCandidate = "zero" }
            case result of
              Left err -> assert "error names the missing index"
                            ("Hole index 1" `T.isInfixOf` err)
              Right _  -> pure (Fail "expected Left for a prose decoy index")

        , runTest "get_diagnostics: .lagda.md hole position is in literate coordinates" $ do
            src <- TIO.readFile lagdaMd
            result <- handleGetDiagnostics cfg GetDiagnosticsParams
              { gdFilePath = lagdaMd }
            case (result, expectedHolePos src) of
              (Left err, _)  -> pure (Fail $ "get_diagnostics failed: " <> T.unpack err)
              (_, Nothing)   -> pure (Fail "fixture lacks the n = {! zero !} line")
              (Right dr, Just (ln, col)) ->
                case drHoles dr of
                  [h] -> assertEqual "(index, line, col)" (0, ln, col)
                           (hiIndex h, hiLine h, hiCol h)
                  hs  -> pure . Fail $ "expected 1 hole, got " <> show (length hs)
        ]
      -- (f) byte-exact restore after in-place patching of non-{!!} holes.
      after <- mapM BS.readFile (parityFixtures <> [plainTwin])
      restored <- runTest "hole-model tools restore fixtures byte-exactly" $
        assert "files unchanged after in-place patching" (before == after)
      pure (parity <> results <> [restored])

-- | agdaParityTest: run batch Agda on a fixture and demand that the
-- scanner's holes coincide with Agda's reported interaction points — same
-- count, same 1-based (line, col) starts, in the file's own coordinates.
agdaParityTest :: AgdaConfig -> FilePath -> IO Bool
agdaParityTest cfg path =
  runTest ("Agda parity: " <> takeFileName path) $ do
    src <- TIO.readFile path
    let ours = [ (hsLine h, hsCol h) | h <- findHoles (flavourOf path) src ]
        cfg' = cfg { agdaFlags = agdaFlags cfg <> ["-i", takeDirectory path] }
    result <- runAgda cfg' path
    let combined = arStdout result <> "\n" <> arStderr result
        agdas    = interactionPointStarts (takeFileName path) combined
    if null agdas
      then pure . Fail $
        "Agda reported no interaction-point locations; output:\n"
        <> T.unpack (T.take 1000 combined)
      else assertEqual "interaction points (line, col)" agdas ours

-- | interactionPointStarts: the (line, col) starts of the interaction-meta
-- locations batch Agda lists for the given file, in report order.  Agda
-- 2.8.0 prints an indented location list under the
-- [UnsolvedInteractionMetas] error, one @path:LINE.COL-…@ per line.
interactionPointStarts :: String -> Text -> [(Int, Int)]
interactionPointStarts file out =
  [ (ln, col)
  | raw <- T.lines out
  , " " `T.isPrefixOf` raw                       -- location lines are indented
  , T.pack file `T.isInfixOf` raw
  , Just (ln, col) <- [parseLoc (T.strip raw)]
  ]
  where
    parseLoc s =
      let loc      = snd (T.breakOnEnd ":" s)    -- "LINE.COL-…"
          start    = T.takeWhile (/= '-') loc    -- "LINE.COL"
          (l, c0)  = T.break (\ch -> ch == '.' || ch == ',') start
          c        = T.drop 1 c0
      in  if not (T.null l) && not (T.null c)
             && T.all isDigit l && T.all isDigit c
            then Just (read (T.unpack l), read (T.unpack c))
            else Nothing


-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  hPutStrLn stderr "agda-mcp test suite"

  -- Tier 0: pure unit tests — hole finding, marker parsing.
  pureResults <- pureTests
  -- Tier 1a: hole-model tests (no Agda, but needs fixture files).
  holeResults <- holeModelTests
  -- Tier 1b: corpus / search tests (no Agda, but needs fixture file).
  corpusResults <- corpusTests
  -- Tier 2: integration tests (only if agda + fixtures are available).
  mEnv <- probeAgdaEnv
  integrationResults <- case mEnv of
    Nothing           -> do
      hPutStrLn stderr "\n── Integration tests (tier 2): SKIPPED ──"
      pure []
    Just (cfg, fixture, repoRoot) -> integrationTests cfg fixture repoRoot

  let allResults = pureResults <> holeResults <> corpusResults <> integrationResults
      total  = length allResults
      passed = length (filter id allResults)
      failed = total - passed

  hPutStrLn stderr $ "\n" <> show passed <> "/" <> show total <> " tests passed."
  if failed > 0 then exitFailure else exitSuccess
