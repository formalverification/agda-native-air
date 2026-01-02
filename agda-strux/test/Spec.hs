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
import Control.Monad (forM_, unless, when)
import Data.Aeson (Value(..), eitherDecodeStrict')
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Text qualified as T
import Paths_agda_json (getDataFileName)
import System.Directory
  ( copyFile, createDirectory, doesFileExist, getTemporaryDirectory
  , listDirectory, removePathForcibly
  )
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
  ]

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
        agdai = dir </> "Example.agdai"

    putStrLn $ "[agda-json-test] out1: " <> out1
    putStrLn $ "[agda-json-test] out2: " <> out2

    copyFile srcInput input

    -- Make the test independent from ~/.config/agda.
    -- Agda respects AGDA_DIR for config (defaults/libraries).
    agdaDir <- setupAgdaDir dir

    withEnv "AGDA_DIR" agdaDir $ do
      -- Run #1
      _st1  <- Run.runJsonl input out1 []   -- includeDirs already include input dir
      rows1 <- parseJsonl out1
      assertBool "expected at least one row on first run" (not (null rows1))

      cacheExists <- doesFileExist agdai
      assertBool "expected Example.agdai to exist after first run (cache creation)" cacheExists

      -- Run #2 (cache should be used)
      _st2  <- Run.runJsonl input out2 []
      rows2 <- parseJsonl out2
      assertBool "expected at least one row on second run" (not (null rows2))

      -- Required rows in the *second* run (stronger signal: cache path works)
      assertBool "expected (module,name)=(Example,foo)"
        (any (\(m,n,_) -> m == "Example" && n == "foo") rows2)

      assertBool "expected (module,name)=(Example,foo-id)"
        (any (\(m,n,_) -> m == "Example" && n == "foo-id") rows2)

      -- Ensure nested module defs are excluded by main-module filtering.
      assertBool "expected no nested module def (Example.Nested,bar)"
        (not (any (\(m,n,_) -> m == "Example.Nested" && n == "bar") rows2))

      -- Helpful diagnostic if someone changes caching behavior later
      unless cacheExists $ do
        items <- sort <$> listDirectory dir
        putStrLn $
          unlines
            [ "[note] Example.agdai did NOT exist after first run."
            , "[note] temp dir contents: " <> show items
            ]

--------------------------------------------------------------------------------
-- JSONL parsing + schema invariants
--------------------------------------------------------------------------------

type Row = (String, String, String)  -- (module, name, qname)

parseJsonl :: FilePath -> IO [Row]
parseJsonl out = do
  outExists <- doesFileExist out
  unless outExists $
    assertFailure ("missing JSONL output file: " <> out)

  bs <- BS.readFile out
  when (BS.null bs) $
    assertFailure ("empty JSONL output: " <> out)

  let ls = filter (not . BS.null) (BS.split 10 bs) -- '\n'
  fmap concat $ mapM parseLine ls

parseLine :: BS.ByteString -> IO [Row]
parseLine line =
  case eitherDecodeStrict' line :: Either String Value of
    Left e ->
      assertFailure ("Invalid JSON line: " <> e <> "\n" <> show line)
    Right v ->
      case v of
        Object o -> do
          -- v0 required keys + v0.1 additions
          let required = [ "file","module","name","qname","type","kind","astSize", "defKind", "dependencies" ]
          forM_ required $ \k -> assertBool ("missing key: " <> show k) (KM.member k o)

          -- Schema regression guards:
          -- defKind must be a non-empty string
          case KM.lookup "defKind" o of
            Just (String dk)  -> assertBool "defKind must be non-empty" (not (T.null dk))
            _                 -> assertFailure "defKind must be a JSON string"

          -- dependencies must be a JSON array (even if empty)
          case KM.lookup "dependencies" o of
            Just (Array _arr)  -> pure ()
            _                  -> assertFailure "dependencies must be a JSON array"

          case (KM.lookup "module" o, KM.lookup "name" o, KM.lookup "qname" o) of
            (Just (String m), Just (String n), Just (String q)) ->
              pure [(T.unpack m, T.unpack n, T.unpack q)]
            _ -> assertFailure "module/name/qname missing or not strings"

        _ -> assertFailure ("Expected each JSONL line to be a JSON object, but got: " <> show v)

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
  pure dst
