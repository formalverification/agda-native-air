-- | Main.hs
--
-- File: agda-native-air/agda-mcp/test/Main.hs
--
-- Description:
--   Integration tests for agda-mcp.
--
--   Tests are organized in three tiers:
--   0. Pure unit tests (no IO, no Agda) — hole finding, marker parsing.
--   1. Corpus/search tests (IO for file read, no Agda) — corpus loading,
--      search_by_name, search_by_type, get_dependencies.
--   2. Subprocess tests (needs agda on PATH) — full tool round-trips.
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
import Data.Either (isLeft)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString as BS
import System.Directory (findExecutable, doesFileExist, getCurrentDirectory)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>), takeDirectory)
import System.IO (hPutStrLn, stderr)

import AgdaMCP.Agda
  ( findHoles , findNthHole , injectReportExpr , substituteHole
  , parseGoalContext , defaultConfig
  , AgdaConfig (..)
  )
import AgdaMCP.Corpus (loadCorpus, searchByName, searchByType, getDeps)
import AgdaMCP.Tools.ProofState
  ( handleGetGoal, handleFillHole, handleCheckFile, handleGetDiagnostics
  , ensureDebugImport )
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
        let holes = findHoles fixture01
        assertEqual "hole count" 2 (length holes)

    , runTest "findHoles: fixtureLambda has 1 hole" $ do
        let holes = findHoles fixtureLambda
        assertEqual "hole count" 1 (length holes)

    , runTest "findNthHole: index 0 exists" $
        assert "should be Just" (isJust $ findNthHole 0 fixture01)

    , runTest "findNthHole: index 99 is Nothing" $
        assert "should be Nothing" (isNothing $ findNthHole 99 fixture01)

    , runTest "injectReportExpr: replaces hole with macro" $ do
        let cfg = defaultConfig
        case injectReportExpr cfg 0 fixture01 of
          Nothing -> pure (Fail "injectReportExpr returned Nothing")
          Just patched -> assert "should contain reportGoalCtx"
            ("reportGoalCtx ?" `T.isInfixOf` patched)

    , runTest "substituteHole: replaces hole with candidate" $ do
        case substituteHole 0 "x" fixture01 of
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
        assertEqual "unchanged" s (ensureDebugImport s)

    , runTest "ensureDebugImport: recognizes a private-qualified import (no duplicate)" $ do
        let s = T.unlines
              [ "module M where", "private open import AgdaDojang.Debug", "foo = {!!}" ]
        assertEqual "unchanged" s (ensureDebugImport s)

    , runTest "ensureDebugImport: a longer name (.Debug.Extra) is not the module" $ do
        let s = T.unlines
              [ "module M where", "open import AgdaDojang.Debug.Extra", "foo = {!!}" ]
        assert "injects the real import"
          ("open import AgdaDojang.Debug" `elem` T.lines (ensureDebugImport s))

    , runTest "ensureDebugImport: a comment mention does not count as an import" $ do
        let s = T.unlines
              [ "module M where"
              , "open import Data.Nat  -- also see AgdaDojang.Debug"
              , "foo = {!!}" ]
        assert "injects the real import"
          ("open import AgdaDojang.Debug" `elem` T.lines (ensureDebugImport s))

    , runTest "ensureDebugImport: 'where' in a header comment does not misplace the import" $ do
        let inp = [ "module M"
                  , "  {a : Level}  -- a level where needed"
                  , "  (X : Set a)"
                  , "  where"
                  , "foo = {!!}" ]
            out = T.lines (ensureDebugImport (T.unlines inp))
        r1 <- assert "header block is intact" (take 4 out == take 4 inp)
        case r1 of
          Fail m -> pure (Fail m)
          Pass   -> assert "import sits just after the real where"
                      (length out > 4 && out !! 4 == "open import AgdaDojang.Debug")
    ]



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
    [ runTest "get_goal: Fixture01 hole 0 returns a non-empty goal" $ do
        let params = GetGoalParams { ggFilePath = fixturePath, ggHoleIndex = 0 }
        result <- handleGetGoal cfg params
        case result of
          Left err -> pure (Fail $ "get_goal failed: " <> T.unpack err)
          Right info ->
            assert "goal should be non-empty" (not . T.null $ giGoal info)

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
  pure (base <> hier)


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


-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  hPutStrLn stderr "agda-mcp test suite"

  -- Tier 0: pure unit tests — hole finding, marker parsing.
  pureResults <- pureTests
  -- Tier 1: corpus / search tests (no Agda, but needs fixture file).
  corpusResults <- corpusTests
  -- Tier 2: integration tests (only if agda + fixtures are available).
  mEnv <- probeAgdaEnv
  integrationResults <- case mEnv of
    Nothing           -> do
      hPutStrLn stderr "\n── Integration tests (tier 2): SKIPPED ──"
      pure []
    Just (cfg, fixture, repoRoot) -> integrationTests cfg fixture repoRoot

  let allResults = pureResults <> corpusResults <> integrationResults
      total  = length allResults
      passed = length (filter id allResults)
      failed = total - passed

  hPutStrLn stderr $ "\n" <> show passed <> "/" <> show total <> " tests passed."
  if failed > 0 then exitFailure else exitSuccess
