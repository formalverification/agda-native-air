-- | Main.hs
--
-- File: agda-native-air/agda-mcp/test/Main.hs
--
-- Description:
--   Integration tests for agda-mcp.
--
--   Tests are organized in three tiers:
--   1. Pure unit tests (no IO, no Agda) — hole finding, marker parsing.
--   2. Subprocess tests (needs agda on PATH) — full tool round-trips.
--   3. MCP protocol tests (needs agda on PATH) — send JSON-RPC, verify response.
--
--   Tier 2 and 3 tests are skipped gracefully if Agda is not available,
--   making the test suite safe to run in CI without a Nix shell.

{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (catch, SomeException)
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (findExecutable, doesFileExist, getCurrentDirectory)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>), takeDirectory)
import System.IO (hPutStrLn, stderr)

import AgdaMCP.Agda
  ( findHoles , findNthHole , injectReportExpr , substituteHole
  , parseGoalContext , defaultConfig
  , AgdaConfig (..)
  )
import AgdaMCP.Types
import AgdaMCP.Tools.ProofState
  ( handleGetGoal, handleFillHole, handleCheckFile, handleGetDiagnostics )



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
-- Tier 1: Pure tests (no Agda required)
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
-- Returns Just AgdaConfig if everything is available, Nothing otherwise.
probeAgdaEnv :: IO (Maybe (AgdaConfig, FilePath))
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
          libFile     = repoRoot </> "agda-dojang" </> "agda" </> "libraries"
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
            pure (Just (cfg, fixturePath))


-- | integrationTests: Tier 2 tests that call tool handlers on real fixture files
-- with a real Agda binary.
integrationTests :: AgdaConfig -> FilePath -> IO [Bool]
integrationTests cfg fixturePath = do
  hPutStrLn stderr "\n── Integration tests (tier 2: Agda subprocess) ──"
  sequence
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



-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  hPutStrLn stderr "agda-mcp test suite"

  pureResults <- pureTests

  -- Tier 2: integration tests (only if agda + fixtures are available).
  mEnv <- probeAgdaEnv
  integrationResults <- case mEnv of
    Nothing           -> do
      hPutStrLn stderr "\n── Integration tests (tier 2): SKIPPED ──"
      pure []
    Just (cfg, fixture) -> integrationTests cfg fixture

  let allResults = pureResults <> integrationResults
      total  = length allResults
      passed = length (filter id allResults)
      failed = total - passed

  hPutStrLn stderr $ "\n" <> show passed <> "/" <> show total <> " tests passed."
  if failed > 0 then exitFailure else exitSuccess
