{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- | Integration tests for the Agda JSONL backend (in-process).
--
-- File: agda-strux/test/Spec.hs
--
-- Description:
--
--   This is a test helper module providing `withAgda` to run TCM actions
--   with specified include paths and input file.
--
--   Design goals:
--     1.  Deterministic: tests must
--         + not depend on repo state (e.g. pre-existing .agdai).
--         + not depend on ~/.config/agda (we set AGDA_DIR).
--     2.  End-to-end: boots Agda, typechecks, extracts JSONL, twice (cache path).
--     3.  Self-diagnosing: on failure, print enough info to debug in one pass.
--     4.  Behavior-focused: asserts schema invariants and key rows; validate
--         both JSONL structure and caching behavior.
--
-- We deliberately avoid shelling out to the executable to eliminate
-- PATH / dist-newstyle / build-tool-depends brittleness. The executable
-- is thin wiring over the library anyway.

module Main (main) where

import Control.Exception (bracket, finally)
import Control.Monad (forM, forM_, unless, when)
import Data.Aeson (Value(..), eitherDecodeStrict')
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Char (isSpace, toLower)
import Data.Text qualified as T
import Data.Foldable (toList)
import Paths_agda_json (getDataFileName)
import System.Directory  ( copyFile, createDirectory, createDirectoryIfMissing
                         , doesFileExist , getTemporaryDirectory , removePathForcibly )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)
import Test.Tasty
import Test.Tasty.HUnit

import qualified AgdaJsonl.Run as Run
import qualified AgdaJsonl.Cli as Cli

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "agda-json"
  [ testCase "produces JSONL twice (cache path) and satisfies invariants"
      test_runs_twice_jsonl_invariants
  , testCase "Empty.agda succeeds and produces empty JSONL"
      test_empty_module_allows_empty_jsonl
  , testCase "extracts proof clauses for lemma-like function defs"
      test_extracts_proof_clauses
  , testCase "regression: NoetherLike normalizes anonymous-section names"
      test_regression_noetherlike_normalization
  , testCase "regression: golden Noether.jsonl schema + normalization invariants"
      test_regression_golden_noether_jsonl
  , testCase "extracts commutativity proof + local where lemma in AddCommExample"
      test_addcommexample_extracts_comm_and_where_lemma
  , testCase "typeAst: parses, tag == Type, and contains a Pi (Example.secId)"
      test_typeAst_contains_Pi_for_secId
  , testGroup "include-path policy" includePathTests
  ]


--------------------------------------------------------------------------------
-- Include-path policy
--------------------------------------------------------------------------------
--
-- Which roots go on Agda's include path decides whether a module is findable
-- under one name or two.  Extracting agda-algebras hit the two-names case:
-- `src/Setoid/Categories/Algebra.lagda.md` is `Setoid.Categories.Algebra` from
-- the library root and plain `Algebra` from its own directory, and the second
-- reading collides with the standard library's `Algebra` (issue #84).  These
-- tests pin the rule that resolves it without breaking the single-file usage
-- the CLI documents.

includePathTests :: [TestTree]
includePathTests =
  [ testCase "adds the input's own directory when no include covers it" $ do
      dirs <- Run.includePathsFor "/lib/src/Foo/Bar.agda" ["/other/resources"]
      assertEqual "input dir must be first, so the module is findable"
        ["/lib/src/Foo", "/other/resources"] dirs

  , testCase "adds the input's own directory when there are no includes at all" $ do
      dirs <- Run.includePathsFor "/lib/src/Foo/Bar.agda" []
      assertEqual "sole root is the input's directory" ["/lib/src/Foo"] dirs

  , testCase "omits the input's own directory when an include already covers it" $ do
      dirs <- Run.includePathsFor "/lib/src/Setoid/Categories/Algebra.lagda.md" ["/lib/src"]
      assertEqual "library root alone names the module once" ["/lib/src"] dirs

  , testCase "treats an include that IS the input's directory as covering it" $ do
      dirs <- Run.includePathsFor "/lib/src/Foo.agda" ["/lib/src"]
      assertEqual "no duplicate root" ["/lib/src"] dirs

  , testCase "dirContains compares path components, not string prefixes" $ do
      assertBool "/a/b contains /a/b/c.agda" (Run.dirContains "/a/b" "/a/b/c.agda")
      assertBool "/a/bc does not contain /a/b/c.agda"
        (not (Run.dirContains "/a/bc" "/a/b/c.agda"))
      assertBool "a directory contains itself" (Run.dirContains "/a/b" "/a/b")

  , testCase "dirContains reaches to any depth" $
      assertBool "/a contains /a/b/c/d.agda" (Run.dirContains "/a" "/a/b/c/d.agda")
  ]


--------------------------------------------------------------------------------
-- JSONL parsing + schema invariants
--------------------------------------------------------------------------------

type Row = (String, String, String, String)
        -- (module, name,   qname,  prettyQname)

parseJsonl :: Bool -> FilePath -> IO [Row]
parseJsonl allowEmpty out = do
  outExists <- doesFileExist out
  unless outExists $
    assertFailure ("missing JSONL output file: " <> out)

  bs <- BS.readFile out
  when (BS.null bs && not allowEmpty) $
    assertFailure ("empty JSONL output (unexpected): " <> out)

  -- If empty is allowed, treat it as "0 rows".
  if BS.null bs
    then pure []
    else do
      let ls = filter (not . BS.null) (BS.split 10 bs) -- '\n'
      fmap concat $ mapM parseLine ls

-- NOTE:
-- We keep parsing strict-bytestring lines because the backend writes one JSON object per line.
-- If the backend ever emits trailing newlines, the BS.null filter above prevents spurious failures.

parseLine :: BS.ByteString -> IO [Row]
parseLine line =
  case eitherDecodeStrict' line :: Either String Value of
    Left e ->
      assertFailure ("Invalid JSON line: " <> e <> "\n" <> show line)
    Right v ->
      case v of
        Object o -> do
          -- v0 required keys + v0.1 additions
          let required =
                [ "file","module","name","qname"
                , "prettyModule","prettyName","prettyQname"
                , "type","kind","astSize","defKind","dependencies"
                ]
          forM_ required $ \k ->
            assertBool ("missing key: " <> show k) (KM.member k o)

          -- Schema regression guards:
          case ( KM.lookup "module" o
               , KM.lookup "name" o
               , KM.lookup "qname" o
               , KM.lookup "prettyQname" o
               ) of
            (Just (String m), Just (String n), Just (String q), Just (String pq)) ->
              pure [(T.unpack m, T.unpack n, T.unpack q, T.unpack pq)]
            _ -> assertFailure "module/name/qname/prettyQname missing or not strings"

        _ -> assertFailure ("Expected JSON object but got: " <> show v)


-- | Parse JSONL file into list of JSON objects.
-- Fails the test on invalid JSON or non-object lines.
parseJsonlObjects :: FilePath -> IO [KM.KeyMap Value]
parseJsonlObjects out = do
  bs <- BS.readFile out
  let ls = filter (not . BS.null) (BS.split 10 bs)
  fmap concat $ forM ls $ \line ->
    case eitherDecodeStrict' line :: Either String Value of
      Left e -> assertFailure ("Invalid JSON line: " <> e) >> pure []
      Right (Object o) -> pure [o]
      Right _ -> assertFailure "Expected JSON object" >> pure []


test_runs_twice_jsonl_invariants :: Assertion
test_runs_twice_jsonl_invariants = do
  srcInput <- getDataFileName "../data/agda/Example.agda"
  exists <- doesFileExist srcInput
  unless exists $
    assertFailure ("Missing test input file: " <> srcInput)

  withTempDir "agda-json-test" $ \dir -> do
    putStrLn ("[agda-json-test] temp dir: " <> dir)
    let input = dir </> "Example.agda"
        out1  = dir </> "out1.jsonl"
        out2  = dir </> "out2.jsonl"
        -- agdai = dir </> "Example.agdai"

    putStrLn $ "[agda-json-test] out1: " <> out1
    putStrLn $ "[agda-json-test] out2: " <> out2

    copyFile srcInput input

    -- Make the test independent from ~/.config/agda.
    -- Agda respects AGDA_DIR for config (defaults/libraries).
    agdaDir <- setupAgdaDir dir

    withEnv "AGDA_DIR" agdaDir $ do
      let fmt = Cli.Full

      -- Run #1
      _st1  <- Run.runJsonl input out1 [] fmt  -- includeDirs already include input dir
      rows1 <- parseJsonl False out1
      assertBool "expected at least one row on first run" (not (null rows1))

      -- Run #2 (cache should be used)
      _st2  <- Run.runJsonl input out2 [] fmt
      rows2 <- parseJsonl False out2
      assertBool "expected at least one row on second run" (not (null rows2))

      -- Existing rows
      assertBool "expected Example.foo"
        (any (\(_,_,_,pq) -> pq == "Example.foo") rows2)

      assertBool "expected Example.foo-id"
        (any (\(_,_,_,pq) -> pq == "Example.foo-id") rows2)

      -- section traversal must find Example.secId
      assertBool "expected Example.secId (from anonymous module section)"
        (any (\(_,_,_,pq) -> pq == "Example.secId") rows2)

      -- prefix filtering includes nested module defs too
      assertBool "expected Example.Nested.bar"
        (any (\(_,_,_,pq) -> pq == "Example.Nested.bar") rows2)


test_empty_module_allows_empty_jsonl :: Assertion
test_empty_module_allows_empty_jsonl = do
  srcInput <- getDataFileName "../data/agda/Empty.agda"
  exists <- doesFileExist srcInput
  unless exists $
    assertFailure ("Missing test input file: " <> srcInput)

  withTempDir "agda-json-empty-test" $ \dir -> do
    putStrLn ("[agda-json-empty-test] temp dir: " <> dir)
    let input = dir </> "Empty.agda"
        out   = dir </> "empty.jsonl"

    copyFile srcInput input

    agdaDir <- setupAgdaDir dir
    withEnv "AGDA_DIR" agdaDir $ do
      let fmt = Cli.Full
      _st <- Run.runJsonl input out [] fmt
      rows <- parseJsonl True out
      assertBool "expected 0 rows for Empty.agda" (null rows)


test_extracts_proof_clauses :: Assertion
test_extracts_proof_clauses = do
  srcInput <- getDataFileName "../data/agda/Proofs.agda"
  exists <- doesFileExist srcInput
  unless exists $
    assertFailure ("Missing test input file: " <> srcInput)

  withTempDir "agda-json-proofs-test" $ \dir -> do
    let input = dir </> "Proofs.agda"
        out   = dir </> "proofs.jsonl"

    copyFile srcInput input
    agdaDir <- setupAgdaDir dir

    withEnv "AGDA_DIR" agdaDir $ do
      let fmt = Cli.Full
      _st <- Run.runJsonl input out [] fmt
      objs <- parseJsonlObjects out

      let findByPrettyQ pq =
            [ o | o <- objs
                , KM.lookup "prettyQname" o == Just (String (T.pack pq))
            ]

      let rowsRefl = findByPrettyQ "Proofs.⊑-refl"
      assertBool "expected row Proofs.⊑-refl" (not (null rowsRefl))

      oRefl <- case rowsRefl of
        o : _ -> pure o
        []    -> assertFailure "expected row Proofs.⊑-refl" >> error "no rows found for Proofs.⊑-refl"

      case (KM.lookup "hasBody" oRefl, KM.lookup "body" oRefl) of
        (Just (Bool True), Just (String t)) ->
          assertBool "expected non-empty body for ⊑-refl" (not (T.null t))
        other ->
          assertFailure ("expected hasBody=true and body=String, got: " <> show other)

      let rowsTrans = findByPrettyQ "Proofs.⊑-trans"
      assertBool "expected row Proofs.⊑-trans" (not (null rowsTrans))

      oTrans <- case rowsTrans of
        o : _ -> pure o
        []    -> assertFailure "expected row Proofs.⊑-trans" >> error "no rows found for Proofs.⊑-trans"

      case (KM.lookup "hasBody" oTrans, KM.lookup "body" oTrans) of
        (Just (Bool True), Just (String t)) ->
          assertBool "expected non-empty body for ⊑-trans" (not (T.null t))
        other ->
          assertFailure ("expected hasBody=true and body=String, got: " <> show other)

test_addcommexample_extracts_comm_and_where_lemma :: Assertion
test_addcommexample_extracts_comm_and_where_lemma = do
  srcInput <- getDataFileName "../data/agda/AddCommExample.agda"
  exists <- doesFileExist srcInput
  unless exists $
    assertFailure ("Missing test input file: " <> srcInput)

  -- AddCommExample imports Proofs, so we must copy it too for hermetic tests.
  srcProofs <- getDataFileName "../data/agda/Proofs.agda"
  proofsExists <- doesFileExist srcProofs
  unless proofsExists $
    assertFailure ("Missing test dependency file: " <> srcProofs)

  withTempDir "agda-json-addcomm-test" $ \dir -> do
    let input     = dir </> "AddCommExample.agda"
        proofsDep = dir </> "Proofs.agda"
        out       = dir </> "addcomm.jsonl"

    copyFile srcInput input
    copyFile srcProofs proofsDep

    agdaDir <- setupAgdaDir dir

    withEnv "AGDA_DIR" agdaDir $ do
      _st  <- Run.runJsonl input out [] Cli.Full
      objs <- parseJsonlObjects out

      assertBool "expected non-empty JSONL for AddCommExample.agda" (not (null objs))

      let findByPrettyQname pq =
            [ o | o <- objs
                , KM.lookup "prettyQname" o == Just (String (T.pack pq))
            ]

      let findByQname qn =
            [ o | o <- objs
                , KM.lookup "qname" o == Just (String (T.pack qn))
            ]

      -- 0) Regression: operators that start with '_' must NOT be treated as anonymous-module segments.
      --    After the normalizeQNameText fix, _+_ should remain in prettyName / prettyQname.
      let plusRows = findByQname "AddCommExample._+_"
      assertBool "expected row qname AddCommExample._+_" (not (null plusRows))

      oPlus <- case plusRows of
        o : _ -> pure o
        []    -> assertFailure "expected row AddCommExample._+_" >> error "no rows found for AddCommExample._+_"

      case ( KM.lookup "prettyModule" oPlus
           , KM.lookup "prettyName"   oPlus
           , KM.lookup "prettyQname"  oPlus
           ) of
        (Just (String pm), Just (String pn), Just (String pq)) -> do
          assertBool "expected prettyModule == AddCommExample" (pm == "AddCommExample")
          assertBool "expected prettyName == _+_" (pn == "_+_")
          assertBool "expected prettyQname == AddCommExample._+_" (pq == "AddCommExample._+_")
        other ->
          assertFailure ("expected prettyModule/prettyName/prettyQname to be strings, got: " <> show other)

      -- 1) Main theorem exists + has non-empty body
      let commRows = findByPrettyQname "AddCommExample.properties.+-comm"
      assertBool "expected row AddCommExample.properties.+-comm" (not (null commRows))

      oComm <- case commRows of
        o : _ -> pure o
        []    -> assertFailure "expected row AddCommExample.properties.+-comm" >> error "no rows found for AddCommExample.properties.+-comm"

      case (KM.lookup "hasBody" oComm, KM.lookup "body" oComm) of
        (Just (Bool True), Just (String t)) -> do
          assertBool "expected non-empty body for +-comm" (not (T.null t))
          assertBool "expected body to mention '+-comm'" ("+-comm" `T.isInfixOf` t)
          assertBool "expected body to mention 'cong' or 'trans'"
            (("cong" `T.isInfixOf` t) || ("trans" `T.isInfixOf` t))
        other ->
          assertFailure ("expected hasBody=true and body=String, got: " <> show other)

      -- 2) Tight regression for the where-lemma name normalization:
      --    qname contains section marker "._." but prettyQname does not.
      let sucRows = findByPrettyQname "AddCommExample.properties.+-suc"
      assertBool "expected row AddCommExample.properties.+-suc" (not (null sucRows))

      oSuc <- case sucRows of
        o : _ -> pure o
        []    -> assertFailure "expected row AddCommExample.properties.+-suc" >> error "no rows found for AddCommExample.properties.+-suc"

      case (KM.lookup "qname" oSuc, KM.lookup "prettyQname" oSuc) of
        (Just (String q), Just (String pq)) -> do
          assertBool "expected raw qname to contain 'properties._.'" ("properties._." `T.isInfixOf` q)
          assertBool "expected prettyQname to be normalized (no '._.')" (not ("._." `T.isInfixOf` pq))
        other ->
          assertFailure ("expected qname/prettyQname to be strings, got: " <> show other)

      -- Optional extra invariant: prettyModule should be normalized too
      case (KM.lookup "module" oSuc, KM.lookup "prettyModule" oSuc) of
        (Just (String m), Just (String pm)) -> do
          assertBool "expected module to contain 'properties._'" ("AddCommExample.properties._" `T.isInfixOf` m)
          assertBool "expected prettyModule to be normalized"
            (pm == "AddCommExample.properties")
        other ->
          assertFailure ("expected module/prettyModule to be strings, got: " <> show other)

--------------------------------------------------------------------------------
-- typeAst structural schema checks (v0)
--------------------------------------------------------------------------------

test_typeAst_contains_Pi_for_secId :: Assertion
test_typeAst_contains_Pi_for_secId = do
  srcInput <- getDataFileName "../data/agda/Example.agda"
  exists <- doesFileExist srcInput
  unless exists $
    assertFailure ("Missing test input file: " <> srcInput)

  withTempDir "agda-json-typeast-test" $ \dir -> do
    let input = dir </> "Example.agda"
        out   = dir </> "example-typeast.jsonl"

    copyFile srcInput input
    agdaDir <- setupAgdaDir dir

    withEnv "AGDA_DIR" agdaDir $ do
      _st  <- Run.runJsonl input out [] Cli.Full
      objs <- parseJsonlObjects out
      assertBool "expected non-empty JSONL" (not (null objs))

      let findByPrettyQ pq =
            [ o | o <- objs
                , KM.lookup "prettyQname" o == Just (String (T.pack pq))
            ]

      let rows = findByPrettyQ "Example.secId"
      assertBool "expected row Example.secId" (not (null rows))

      o <- case rows of
        x : _ -> pure x
        []    -> assertFailure "unreachable" >> error "no rows found for Example.secId"

      -- 1) JSON parses + required key exists
      typeAstVal <- case KM.lookup "typeAst" o of
        Nothing -> assertFailure "missing key: typeAst" >> error "missing key: typeAst"
        Just v  -> pure v

      -- 2) typeAst.tag == "Type"
      case typeAstVal of
        Object taObj ->
          case KM.lookup "tag" taObj of
            Just (String "Type") -> pure ()
            other -> assertFailure ("typeAst.tag expected \"Type\", got: " <> show other)
        other ->
          assertFailure ("typeAst expected JSON object, got: " <> show other)

      -- Optional: version guard (if you added it)
      case KM.lookup "typeAstVersion" o of
        Just (String "0.3-v0") -> pure ()
        Just (String v)        -> assertFailure ("unexpected typeAstVersion: " <> T.unpack v)
        Just other             -> assertFailure ("typeAstVersion must be a string, got: " <> show other)
        Nothing                -> pure () -- allow missing if you kept it optional

      -- 3) Somewhere inside typeAst, we should see a node with tag == "Pi"
      assertBool "expected typeAst to contain at least one Pi"
        (containsTag "Pi" typeAstVal)


-- | Does a JSON Value contain an object with field { "tag": <wanted> } anywhere?
containsTag :: T.Text -> Value -> Bool
containsTag wanted = go
  where
    go :: Value -> Bool
    go = \case
      Object o ->
        hasWantedTag o || any go (KM.elems o)
      Array arr ->
        any go (toList arr)
      _ ->
        False

    hasWantedTag o =
      case KM.lookup "tag" o of
        Just (String t) -> t == wanted
        _               -> False

test_regression_noetherlike_normalization :: Assertion
test_regression_noetherlike_normalization = do
  srcInput <- getDataFileName "../data/agda/agda-algebras-regressions/NoetherLike.agda"
  exists <- doesFileExist srcInput
  unless exists $
    assertFailure ("Missing test input file: " <> srcInput)

  withTempDir "agda-json-noetherlike-test" $ \dir -> do
    let input = dir </> "NoetherLike.agda"
        out   = dir </> "noetherlike.jsonl"

    copyFile srcInput input
    agdaDir <- setupAgdaDir dir

    withEnv "AGDA_DIR" agdaDir $ do
      _st <- Run.runJsonl input out [] Cli.Full
      objs <- parseJsonlObjects out

      -- Basic sanity: non-empty
      assertBool "expected non-empty JSONL for NoetherLike.agda" (not (null objs))

      -- Core regression: we should see at least one row whose *raw* qname contains "._."
      -- but whose prettyQname does NOT contain "._."
      let hasAnonInQname o =
            case (KM.lookup "qname" o, KM.lookup "prettyQname" o) of
              (Just (String q), Just (String pq)) ->
                   ("._." `T.isInfixOf` q)
                && not ("._." `T.isInfixOf` pq)
              _ -> False

      assertBool
        "expected at least one def with qname containing '._.' but prettyQname normalized"
        (any hasAnonInQname objs)

      -- Also assert the specific symbol we expect is present in prettyQname space.
      let hasPretty pq =
            any (\o -> KM.lookup "prettyQname" o == Just (String (T.pack pq))) objs

      assertBool "expected NoetherLike.secId in prettyQname" (hasPretty "NoetherLike.secId")
      assertBool "expected NoetherLike.FirstHomTheorem|Set in prettyQname" (hasPretty "NoetherLike.FirstHomTheorem|Set")
      assertBool "expected NoetherLike.Nested.bar in prettyQname" (hasPretty "NoetherLike.Nested.bar")


test_regression_golden_noether_jsonl :: Assertion
test_regression_golden_noether_jsonl = do
  fp <- getDataFileName "../data/agda/agda-algebras-regressions/Noether.jsonl"
  exists <- doesFileExist fp
  unless exists $
    assertFailure ("Missing golden JSONL file: " <> fp)

  objs <- parseJsonlObjects fp

  assertBool "expected Noether.jsonl to contain at least one object" (not (null objs))

  -- Guard the exact weirdness seen in the snapshot:
  -- module can be "Base.Homomorphisms.Noether._" while prettyModule is normalized.
  let hasNormalizedPrettyModule o =
        case (KM.lookup "module" o, KM.lookup "prettyModule" o) of
          (Just (String m), Just (String pm)) ->
               ("._" `T.isInfixOf` m)
            && not ("._" `T.isInfixOf` pm)
          _ -> False

  assertBool
    "expected at least one row where module contains '._' but prettyModule is normalized"
    (any hasNormalizedPrettyModule objs)

  -- Similar check for qname vs prettyQname
  let hasNormalizedPrettyQname o =
        case (KM.lookup "qname" o, KM.lookup "prettyQname" o) of
          (Just (String q), Just (String pq)) ->
               ("._." `T.isInfixOf` q)
            && not ("._." `T.isInfixOf` pq)
          _ -> False

  assertBool
    "expected at least one row where qname contains '._.' but prettyQname is normalized"
    (any hasNormalizedPrettyQname objs)


--------------------------------------------------------------------------------
-- Deterministic environment + temp dir
--------------------------------------------------------------------------------

withEnv :: String -> String -> IO a -> IO a
withEnv k v action =
  bracket (lookupEnv k) (\old -> maybe (unsetEnv k) (setEnv k) old) $ \_ -> do
    setEnv k v
    action

-- Treat any non-empty value as true except explicit "0"/"false"/"no"/"off"
envTruthy :: Maybe String -> Bool
envTruthy = \case
  Nothing -> False
  Just s0 ->
    let s = map toLower (trim s0)
    in not (null s) && s `notElem` ["0","false","no","off"]
  where
    trim :: String -> String
    trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

withTempDir :: String -> (FilePath -> IO a) -> IO a
withTempDir prefix action = do
  -- New knobs (preferred):
  --   AGDA_JSON_TEST_KEEP=1
  --   AGDA_JSON_TEST_OUT_ROOT=data/test-output/agda-strux
  --
  -- Back-compat (legacy):
  --   KEEP_TEST_DIR=1
  keepNew    <- lookupEnv "AGDA_JSON_TEST_KEEP"
  keepLegacy <- lookupEnv "KEEP_TEST_DIR"
  outRoot    <- lookupEnv "AGDA_JSON_TEST_OUT_ROOT"

  let keep = envTruthy keepNew || envTruthy keepLegacy

  fp <-
    if keep
      then do
        base <- case outRoot of
          Just r | not (null r) -> pure r
          _                     -> getTemporaryDirectory

        -- Ensure base exists, e.g. data/test-output/agda-strux/
        createDirectoryIfMissing True base

        -- Unique run dir under base (openTempFile gives uniqueness)
        (p, h) <- openTempFile base prefix
        hClose h
        removePathForcibly p
        createDirectory p
        pure p
      else do
        tmp <- getTemporaryDirectory
        (p, h) <- openTempFile tmp prefix
        hClose h
        removePathForcibly p
        createDirectory p
        pure p

  let cleanup =
        if keep
          then pure ()            -- keep for debugging / sharing
          else removePathForcibly fp

  action fp `finally` cleanup


setupAgdaDir :: FilePath -> IO FilePath
setupAgdaDir dir = do
  let dst = dir </> "agda-config"
  createDirectory dst
  mSrc <- lookupEnv "AGDA_DIR"
  case mSrc of
    Nothing  -> pure ()  -- no pinned config available; remains minimal
    Just src -> do
      -- copy pinned Agda library config produced by nix develop
      let files = ["libraries","defaults"]
      forM_ files $ \f -> do
        let s = src </> f
            d = dst </> f
        ok <- doesFileExist s
        when ok (copyFile s d)
  -- Ensure we do not accidentally fall back to user-level config:
  -- create empty files if they don't exist.
  let ensureEmpty f = do
        let p = dst </> f
        ok <- doesFileExist p
        unless ok (BS.writeFile p BS.empty)
  ensureEmpty "libraries"
  ensureEmpty "defaults"
  pure dst
