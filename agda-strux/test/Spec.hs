-- | Spec.hs
--
-- File: agda-backend-jsonl/test/Spec.hs
--
-- Description:
--   Integration tests for the agda-json executable.
--
--   This is a test helper module providing `withAgda` to run TCM actions
--   with specified include paths and input file.
--
--   Design goals:
--     1) Deterministic: tests must not depend on repo state (e.g. pre-existing .agdai).
--     2) Self-diagnosing: on failure, print enough info to debug in one pass.
--     3) Behavior-focused: validate both JSONL structure and caching behavior.

{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (finally)
import Control.Monad (forM_, forM, unless, when)
import Data.Aeson (Value(..), eitherDecodeStrict')
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.List (sort, isInfixOf)
import Data.Text qualified as T
import Paths_agda_json (getDataFileName)
import System.Directory
  ( copyFile, createDirectory, doesFileExist, findExecutable, getTemporaryDirectory
  , createDirectoryIfMissing, listDirectory, removeFile, removePathForcibly
  )
import System.Exit (ExitCode(..))
import System.FilePath ((</>), takeDirectory)
import System.IO (hClose, openTempFile)
import System.Environment (lookupEnv)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "agda-json"
  [ testCase "produces JSONL even when .agdai cache exists (isolated temp dir)"
      test_runs_twice_jsonl
  , testCase "fails with usage when required args are missing"
      test_missing_args
  , testCase "fails when input file does not exist"
      test_input_missing
  , testCase "fails when include path is invalid"
      test_bad_include
  , testCase "fails on malformed Agda code"
      test_malformed_agda
  ]

test_runs_twice_jsonl :: Assertion
test_runs_twice_jsonl = do
  -- exe <- cabalListBin "agda-json:exe:agda-json"
  -- With `build-tool-depends: agda-json:agda-json`, Cabal puts the tool on PATH.
  mExe <- findExecutable "agda-json"
  exe <- case mExe of
    Just p  -> pure p
    Nothing -> do
      mp <- lookupEnv "PATH"
      assertFailure $
        unlines
          [ "Could not find build tool `agda-json` on PATH."
          , "PATH=" <> maybe "<unset>" id mp
          , "Hint: ensure the test-suite stanza includes:"
          , "  build-tool-depends: agda-json:agda-json"
          ]

  -- Source test input in repo
  srcInput <- getDataFileName "test/resources/Example.agda"
  exists <- doesFileExist srcInput
  unless exists $
    assertFailure ("Missing test input file: " <> srcInput)

  withTempDir "agda-json-test" $ \dir -> do
    let input = dir </> "Example.agda"
        inc   = dir
        out1  = dir </> "out1.jsonl"
        out2  = dir </> "out2.jsonl"
        agdai = dir </> "Example.agdai"

    -- Copy module into the temp directory.
    copyFile srcInput input

    -- Run #1: should produce JSONL and (typically) create the .agdai cache
    rows1 <- runOnceOrExplain exe input inc out1
    assertBool "expected at least one row on first run" (not (null rows1))

    -- After first run, cache may exist (Agda usually writes Example.agdai).
    cacheExists <- doesFileExist agdai
    assertBool "expected Example.agdai to exist after first run (cache creation)" cacheExists

    -- Run #2: should *still* produce JSONL
    rows2 <- runOnceOrExplain exe input inc out2
    assertBool "expected at least one row on second run" (not (null rows2))

    -- Assert we saw expected names in at least one of the runs.
    -- (We accept qualified or unqualified output here.)
    let hasFoo   = any (\(m,n,_) -> m == "Example" && n == "foo") rows2
        hasFooId = any (\(m,n,_) -> m == "Example" && n == "foo-id") rows2
    assertBool "expected (module,name)=(Example,foo)" hasFoo
    assertBool "expected (module,name)=(Example,foo-id)" hasFooId

    -- Diagnostic note: not all Agda invocations necessarily write .agdai depending on options,
    -- but when debugging the original bug it's useful to report whether it appeared.
    unless cacheExists $ do
      items <- sort <$> listDirectory dir
      -- Not a failure, but extremely informative when chasing caching behavior.
      putStrLn $
        unlines
          [ "[note] Example.agdai did NOT exist after first run."
          , "[note] temp dir contents: " <> show items
          ]



--------------------------------------------------------------------------------
-- Negative tests (fast, stable)
--------------------------------------------------------------------------------

getExe :: IO FilePath
getExe = do
  mExe <- findExecutable "agda-json"
  case mExe of
    Just p  -> pure p
    Nothing -> do
      mp <- lookupEnv "PATH"
      assertFailure $
        unlines
          [ "Could not find build tool `agda-json` on PATH."
          , "PATH=" <> maybe "<unset>" id mp
          , "Hint: ensure the test-suite stanza includes:"
          , "  build-tool-depends: agda-json:agda-json"
          ]

assertExitFailureWith :: String -> (ExitCode, String, String) -> Assertion
assertExitFailureWith needle (code, stdout, stderr) =
  case code of
    ExitSuccess ->
      assertFailure $
        unlines
          [ "Expected ExitFailure but got ExitSuccess"
          , "stdout:\n" <> stdout
          , "stderr:\n" <> stderr
          ]
    ExitFailure _ -> do
      let hay = stdout <> "\n" <> stderr
      assertBool ("Expected output to contain: " <> show needle) (needle `isInfixOf` hay)

test_missing_args :: Assertion
test_missing_args = do
  exe <- getExe
  r <- readProcessWithExitCode exe [] ""
  assertExitFailureWith "Missing --input" r
  assertExitFailureWith "Usage:" r

test_input_missing :: Assertion
test_input_missing = do
  exe <- getExe
  withTempDir "agda-json-missing-input" $ \dir -> do
    let out = dir </> "out.jsonl"
    r <- readProcessWithExitCode exe
          [ "--input", dir </> "Nope.agda"
          , "--output", out
          , "--include", dir
          ] ""
    assertExitFailureWith "Input file does not exist" r

test_bad_include :: Assertion
test_bad_include = do
  exe <- getExe
  withTempDir "agda-json-bad-include" $ \dir -> do
    -- We need a module that depends on a separate include dir, because
    -- agda-json always includes the input file's directory automatically.
    let mainDir = dir </> "main"
        libDir  = dir </> "lib"
        badInc  = dir </> "nope-include-dir"

        depFile  = libDir  </> "Dep.agda"
        mainFile = mainDir </> "Main.agda"

        outOk  = dir </> "ok.jsonl"
        outBad = dir </> "bad.jsonl"

    createDirectoryIfMissing True mainDir
    createDirectoryIfMissing True libDir

    -- Dep lives ONLY in libDir.
    BS.writeFile depFile $
      "module Dep where\n\
      \open import Agda.Builtin.Nat using (Nat; zero)\n\
      \bar : Nat\n\
      \bar = zero\n"

    -- Main is in mainDir and imports Dep, which must be found via --include libDir.
    BS.writeFile mainFile $
      "module Main where\n\
      \open import Dep\n\
      \open import Agda.Builtin.Nat using (Nat)\n\
      \use : Nat\n\
      \use = bar\n"

    -- Sanity: with correct include, it should succeed.
    (codeOk, _so, _se) <- readProcessWithExitCode exe
      [ "--input", mainFile
      , "--output", outOk
      , "--include", libDir
      ] ""
    case codeOk of
      ExitFailure _ ->
        assertFailure "Expected success when --include points to libDir, but agda-json failed."
      ExitSuccess -> pure ()

    -- Now: with a bad include, it should fail (Dep is not findable).
    r <- readProcessWithExitCode exe
      [ "--input", mainFile
      , "--output", outBad
      , "--include", badInc
      ] ""
    case r of
      (ExitSuccess, _stdout, _stderr) ->
        assertFailure "Expected failure when Dep cannot be found (bad --include), but command succeeded."
      (ExitFailure _, stdout, stderr) -> do
        let hay = stdout <> "\n" <> stderr
        assertBool "Expected failure output to mention Dep" ("Dep" `isInfixOf` hay)

test_malformed_agda :: Assertion
test_malformed_agda = do
  exe <- getExe
  withTempDir "agda-json-malformed" $ \dir -> do
    let input = dir </> "Bad.agda"
        out   = dir </> "out.jsonl"
    BS.writeFile input "this is not Agda\n"
    r <- readProcessWithExitCode exe
          [ "--input", input
          , "--output", out
          , "--include", dir
          ] ""
    case r of
      (ExitSuccess, _stdout, _stderr) ->
        assertFailure "Expected failure for malformed Agda input, but command succeeded."
      _ -> pure ()




--------------------------------------------------------------------------------
-- Running the executable with strong diagnostics
--------------------------------------------------------------------------------

type Row = (String, String, String)  -- (module, name, qname)

-- | Run the executable once and parse its JSONL output.
-- On failure (including empty output), print rich diagnostics: stdout/stderr,
-- output path/size, and directory contents.
runOnceOrExplain :: FilePath -> FilePath -> FilePath -> FilePath -> IO [Row]
runOnceOrExplain exe input inc out = do
  (code, stdout, stderr) <-
    readProcessWithExitCode exe
      [ "--input", input
      , "--output", out
      , "--include", inc
      ] ""

  case code of
    ExitFailure n -> do
      explainFailure "agda-json exited non-zero" exe input inc out stdout stderr
      assertFailure ("agda-json failed with exit code " <> show n)
    ExitSuccess -> pure ()

  outExists <- doesFileExist out
  unless outExists $ do
    explainFailure "agda-json exited successfully, but output file was not created" exe input inc out stdout stderr
    assertFailure "missing JSONL output file"

  bs <- BS.readFile out
  when (BS.null bs) $ do
    explainFailure "agda-json exited successfully, but output file is empty" exe input inc out stdout stderr
    assertFailure "empty JSONL output"

  let ls = filter (not . BS.null) (BS.split 10 bs)  -- '\n'

  -- Parse each line as JSON and check keys exist.
  fmap concat $ forM ls $ \line ->
    case eitherDecodeStrict' line :: Either String Value of
      Left e  -> assertFailure ("Invalid JSON line: " <> e <> "\n" <> show line)
      Right v ->
        case v of
          Object o -> do
            -- 1) Check all required keys exist (once per JSON object)
            forM_ ["file","module","name","qname","type","kind","astSize"] $ \k -> do
              assertBool ("missing key: " <> show k) (KM.member k o)

            -- 2) Extract the values we care about (once per JSON object)
            case (KM.lookup "module" o, KM.lookup "name" o, KM.lookup "qname" o) of
              (Just (String m), Just (String n), Just (String q)) -> pure [(T.unpack m, T.unpack n, T.unpack q)]
              _ -> assertFailure "module/name/qname missing or not strings"
          _ ->
            assertFailure ("Expected each JSONL line to be a JSON object, but got: " <> show v)


explainFailure :: String -> FilePath -> FilePath -> FilePath -> FilePath -> String -> String -> IO ()
explainFailure headline exe input inc out stdout stderr = do
  let dir = takeDirectory input
  files <- safeList dir
  outExists <- doesFileExist out
  outSize <- if outExists then BS.length <$> BS.readFile out else pure 0
  let msg = unlines
        [ ""
        , "=== " <> headline <> " ==="
        , "exe   : " <> exe
        , "input : " <> input
        , "inc   : " <> inc
        , "out   : " <> out
        , "out?  : " <> show outExists <> " (bytes=" <> show outSize <> ")"
        , ""
        , "Directory listing of: " <> dir
        , unlines (map ("  " <>) files)
        , ""
        , "stdout:"
        , indent stdout
        , ""
        , "stderr:"
        , indent stderr
        , "=============================="
        ]
  putStrLn msg
  where
    indent s = unlines (map ("  " <>) (lines s))

safeList :: FilePath -> IO [String]
safeList d = do
  xs <- listDirectory d
  pure xs

--------------
-- Temp dir
--------------

withTempDir :: String -> (FilePath -> IO a) -> IO a
withTempDir prefix action = do
  tmp <- getTemporaryDirectory
  (fp, h) <- openTempFile tmp prefix
  hClose h
  removeFile fp
  createDirectory fp
  action fp `finally` removePathForcibly fp

