{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for the Agda JSONL backend (in-process).
--
-- File: agda-backend-jsonl/test/Spec.hs
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
import Data.Foldable (toList)
import Data.Text qualified as T
import Paths_agda_json (getDataFileName)
import System.Directory  ( copyFile, createDirectory, doesFileExist
                         , getTemporaryDirectory , removePathForcibly )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)
import Test.Tasty
import Test.Tasty.HUnit

import qualified AgdaJsonl.Run as Run

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

          -- -- defKind must be a non-empty string
          -- case KM.lookup "defKind" o of
          --   Just (String dk)  -> assertBool "defKind must be non-empty" (not (T.null dk))
          --   _                 -> assertFailure "defKind must be a JSON string"

          -- -- dependencies must be a JSON array (even if empty)
          -- case KM.lookup "dependencies" o of
          --   Just (Array _arr)  -> pure ()
          --   _                  -> assertFailure "dependencies must be a JSON array"

          -- case (KM.lookup "module" o, KM.lookup "name" o, KM.lookup "qname" o) of
          --   (Just (String m), Just (String n), Just (String q)) ->
          --     pure [(T.unpack m, T.unpack n, T.unpack q)]
          --   _ -> assertFailure "module/name/qname missing or not strings"

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
  srcInput <- getDataFileName "test/resources/Example.agda"
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
      -- Run #1
      _st1  <- Run.runJsonl input out1 []   -- includeDirs already include input dir
      rows1 <- parseJsonl False out1
      assertBool "expected at least one row on first run" (not (null rows1))

      -- Run #2 (cache should be used)
      _st2  <- Run.runJsonl input out2 []
      rows2 <- parseJsonl False out2
      assertBool "expected at least one row on second run" (not (null rows2))

      -- Existing rows
      assertBool "expected Example.foo"
        (any (\(_,_,_,pq) -> pq == "Example.foo") rows2)

      assertBool "expected Example.foo-id"
        (any (\(_,_,_,pq) -> pq == "Example.foo-id") rows2)

      -- NEW: section traversal must find Example.secId
      assertBool "expected Example.secId (from anonymous module section)"
        (any (\(_,_,_,pq) -> pq == "Example.secId") rows2)

      -- NEW: prefix filtering includes nested module defs too
      assertBool "expected Example.Nested.bar"
        (any (\(_,_,_,pq) -> pq == "Example.Nested.bar") rows2)


test_empty_module_allows_empty_jsonl :: Assertion
test_empty_module_allows_empty_jsonl = do
  srcInput <- getDataFileName "test/resources/Empty.agda"
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
      _st <- Run.runJsonl input out []
      rows <- parseJsonl True out
      assertBool "expected 0 rows for Empty.agda" (null rows)


test_extracts_proof_clauses :: Assertion
test_extracts_proof_clauses = do
  srcInput <- getDataFileName "test/resources/Proofs.agda"
  exists <- doesFileExist srcInput
  unless exists $
    assertFailure ("Missing test input file: " <> srcInput)

  withTempDir "agda-json-proofs-test" $ \dir -> do
    let input = dir </> "Proofs.agda"
        out   = dir </> "proofs.jsonl"

    copyFile srcInput input
    agdaDir <- setupAgdaDir dir

    withEnv "AGDA_DIR" agdaDir $ do
      _st <- Run.runJsonl input out []
      objs <- parseJsonlObjects out

      let findByPrettyQ pq =
            [ o | o <- objs
                , KM.lookup "prettyQname" o == Just (String (T.pack pq))
            ]

      let rowsRefl = findByPrettyQ "Proofs.⊑-refl"
      assertBool "expected row Proofs.⊑-refl" (not (null rowsRefl))

      let oRefl = head rowsRefl

      -- case KM.lookup "clauses" oRefl of
      --   Just (Array arr) ->
      --     assertBool "expected non-empty clauses for ⊑-refl" (not (null (toList arr)))
      --   other ->
      --     assertFailure ("expected clauses: Array, got: " <> show other)

      case (KM.lookup "hasBody" oRefl, KM.lookup "body" oRefl) of
        (Just (Bool True), Just (String t)) ->
          assertBool "expected non-empty body for ⊑-refl" (not (T.null t))
        other ->
          assertFailure ("expected hasBody=true and body=String, got: " <> show other)



      let rowsTrans = findByPrettyQ "Proofs.⊑-trans"
      assertBool "expected row Proofs.⊑-trans" (not (null rowsTrans))

      let oTrans = head rowsTrans
      -- case KM.lookup "clauses" oTrans of
      --   Just (Array arr) ->
      --     assertBool "expected non-empty clauses for ⊑-trans" (not (null (toList arr)))
      --   other ->
      --     assertFailure ("expected clauses: Array, got: " <> show other)

      case (KM.lookup "hasBody" oTrans, KM.lookup "body" oTrans) of
        (Just (Bool True), Just (String t)) ->
          assertBool "expected non-empty body for ⊑-trans" (not (T.null t))
        other ->
          assertFailure ("expected hasBody=true and body=String, got: " <> show other)


--------------------------------------------------------------------------------
-- Deterministic environment + temp dir
--------------------------------------------------------------------------------

withEnv :: String -> String -> IO a -> IO a
withEnv k v action =
  bracket (lookupEnv k) (\old -> maybe (unsetEnv k) (setEnv k) old) $ \_ -> do
    setEnv k v
    action

withTempDir :: String -> (FilePath -> IO a) -> IO a
withTempDir prefix action = do
  tmp <- getTemporaryDirectory
  (fp, h) <- openTempFile tmp prefix
  hClose h
  removePathForcibly fp
  createDirectory fp
  keep <- lookupEnv "KEEP_TEST_DIR"
  let cleanup =
        case keep of
          Just _  -> pure ()          -- keep for debugging
          Nothing -> removePathForcibly fp
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
