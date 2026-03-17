-- | File: agda-native-air/agda-mcp/test/Main.hs
--
-- Integration tests for agda-mcp.
--
-- Tests are organized in three tiers:
--   1. Pure unit tests (no IO, no Agda) — hole finding, marker parsing.
--   2. Subprocess tests (needs agda on PATH) — full tool round-trips.
--   3. MCP protocol tests (needs agda on PATH) — send JSON-RPC, verify response.
--
-- Tier 2 and 3 tests are skipped gracefully if Agda is not available,
-- making the test suite safe to run in CI without a Nix shell.

{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)
import Control.Exception (catch, SomeException)

import AgdaMCP.Agda
  ( findHoles , findNthHole , injectReportExpr , substituteHole
  , parseGoalContext , defaultConfig
  )
import AgdaMCP.Types (CtxEntry (..))


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
                    -- TODO: don't use `head` on possible empty list
                    assertEqual "ctx[0].name" "x" (ctxName (head ctx))

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
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  hPutStrLn stderr "agda-mcp test suite"

  pureResults <- pureTests

  -- TODO (M1-2, tier 2): add subprocess round-trip tests when agda is on PATH.
  -- These will call handleGetGoal / handleFillHole on real fixture files.

  let total  = length pureResults
      passed = length (filter id pureResults)
      failed = total - passed

  hPutStrLn stderr $ "\n" <> show passed <> "/" <> show total <> " tests passed."
  if failed > 0 then exitFailure else exitSuccess
