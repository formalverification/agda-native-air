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
--      get_dependencies; 1c: `--timeout` enforcement (subprocess, but no
--      *Agda*), driven by the `fake-slow-agda.sh` stand-in binary so it
--      runs anywhere; 1d: the response echo and root resolution (#72/#76);
--      1e: hole addressing by position or index, and the parse of both
--      (#79) — all resolved before Agda is started, misses included;
--      1f: the whole-project gate (#78), driven by `fake-project-gate.sh`
--      over fixture projects — never over this repository's own gate;
--      1g: the requested path (#101) — a relative path resolved against the
--      server's own working directory, and every way a path can fail to name
--      a readable file, each refused by name rather than crashing the call.
--   2. Subprocess tests (needs agda on PATH) — full tool round-trips,
--      including 2d: hole-enumeration parity against batch Agda, and 2f:
--      re-anchoring by position across a fill (#79).
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

import Control.Concurrent (threadDelay)
import Control.Exception (bracket_, catch, try, SomeException)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import Data.Char (isDigit)
import Data.Either (isLeft)
import Data.List (find, isInfixOf, nub, sort, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, isNothing, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import System.Directory
  ( Permissions, createDirectoryIfMissing, doesFileExist, emptyPermissions
  , findExecutable, getCurrentDirectory, getPermissions, getTemporaryDirectory
  , makeAbsolute, removeDirectoryRecursive, removeFile, setOwnerExecutable
  , setPermissions
  )
import System.Environment (setEnv)
import System.Exit (exitFailure, exitSuccess)
import System.IO.Error
  ( doesNotExistErrorType, mkIOError, permissionErrorType )
import System.Posix.Files (createNamedPipe, ownerReadMode, ownerWriteMode, unionFileModes)
import System.FilePath ((</>), takeDirectory, takeFileName)
import System.IO (hPutStrLn, stderr)

import AgdaMCP.Agda
  ( parseGoalContext , defaultConfig
  , AgdaConfig (..)
  , runAgda , AgdaResult (..)
  , checkedFromSourceOf , defaultTimeoutSeconds
  )
import AgdaMCP.Holes
  ( LiterateFlavour (..) , flavourOf , maskNonCode
  , HoleSpan (..) , findHoles , findNthHole
  , HoleRef (..) , offsetOfPosition , resolveHoleRef
  , injectReportExpr , substituteHole
  )
import AgdaMCP.Corpus (loadCorpus, searchByName, searchByType, getDeps)
import AgdaMCP.Path (ioProblem)
import AgdaMCP.Diagnostics
  ( capDiagnostics, defaultMaxDiagnostics, diagnosticRank, maxMessageChars
  , maxMessageLines, parseDiagnostics )
import AgdaMCP.Gate
  ( GateConfig (..), GatePlan (..), defaultGateConfig, findMakefileGate
  , makefileTargets, resolveGate )
import AgdaMCP.Project
  ( findNearestAgdaLib, includePathsOf, librariesFileFlagOf, libraryIncludeDirs
  , libraryIncludesOf, libraryNameOf, parseLibrariesFile, resolveProjectDir
  , selectedLibrariesOf
  )
import AgdaMCP.Server (ServerConfig (..), forceResponse, toolDefinitions)
import AgdaMCP.Tools.CheckProject
  ( handleCheckProject, failingModuleOf, gateFailureLines, maxTailLines
  , outputTailOf, parseCheckingLine, progressModules )
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

-- | allOf: run assertions in sequence, stopping at the first failure.  A test
-- that checks several things about one result (a diagnostic's code, then its
-- range, then its payload) reads as a list rather than as a staircase of
-- case-on-TestResult.
allOf :: [IO TestResult] -> IO TestResult
allOf []       = pure Pass
allOf (a : as) = do
  r <- a
  case r of
    Fail m -> pure (Fail m)
    Pass   -> allOf as

-- | failureText: flatten a structured 'ToolFailure' to its message, for test
-- diagnostics that only want the prose.
failureText :: ToolFailure -> Text
failureText (FailMessage m)  = m
failureText (FailTimeout tf) = tfMessage tf
failureText (FailProject pm) = mismatchMessage pm
failureText (FailPath pf)    = pathFailureMessage pf

-- | fakeResult: a synthetic 'AgdaResult' for the pure 'checkedFromSourceOf'
-- tests — exit code, timed-out flag, and stdout, with the fields the signal
-- never reads left inert.
fakeResult :: Int -> Bool -> Text -> AgdaResult
fakeResult ec timedOut out = AgdaResult
  { arExitCode  = ec
  , arStdout    = out
  , arStderr    = ""
  , arTimedOut  = timedOut
  , arElapsedMs = 0
  , arCommand   = CommandEcho { ceBinary = "agda", ceArgs = [], ceCwd = "." }
  }


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

    -- checkedFromSourceOf: the coarse cache signal (issue #77).  A @Checking@
    -- line is positive evidence of a source re-check; a run that completed
    -- successfully in silence is the interface-reuse signature (a warm Agda
    -- 2.8.0 prints nothing at default verbosity); and a run that died without
    -- producing evidence either way is unknown — a Copilot review catch on
    -- PR #89: defaulting that case to False would misread a killed cold call
    -- as a warm one.
    , runTest "checkedFromSourceOf: a 'Checking' line means a source re-check" $
        assertEqual "signal" (Just True)
          (checkedFromSourceOf (fakeResult 0 False (T.unlines
            [ "Checking Algebras.Basic (/lib/Algebras/Basic.agda)."
            , "Finished Algebras.Basic."
            ])))

    , runTest "checkedFromSourceOf: a failed run that reached 'Checking' still counts" $
        assertEqual "signal" (Just True)
          (checkedFromSourceOf (fakeResult 42 False
            "Checking Broken (/x/Broken.agda).\nerror: [MissingTypeSignature]"))

    , runTest "checkedFromSourceOf: silent success is the interface-reuse signature" $
        assertEqual "signal" (Just False)
          (checkedFromSourceOf (fakeResult 0 False ""))

    , runTest "checkedFromSourceOf: 'Loading' lines (verbose runs) also read as reuse" $
        assertEqual "signal" (Just False)
          (checkedFromSourceOf (fakeResult 42 False (T.unlines
            [ "Loading Algebras.Basic (/lib/_build/Algebras/Basic.agdai)."
            , "Loading Homomorphisms.Basic (/lib/_build/Homomorphisms/Basic.agdai)."
            ])))

    , runTest "checkedFromSourceOf: indented 'Checking' still counts" $
        assertEqual "signal" (Just True)
          (checkedFromSourceOf (fakeResult 0 False
            "  Checking Proofs.Use (/lib/src/Proofs/Use.agda)."))

    , runTest "checkedFromSourceOf: a failure with no evidence is unknown, not a guess" $
        assertEqual "signal" Nothing
          (checkedFromSourceOf (fakeResult 42 False
            "error: [LibraryError]\nLibrary 'agda-dojang' not found."))

    , runTest "checkedFromSourceOf: a timeout before any output is unknown, not warm" $
        assertEqual "signal" Nothing
          (checkedFromSourceOf (fakeResult (-15) True ""))

    -- The default bound is enforced now (issue #77), so its value is a real
    -- decision: a cold agda-algebras call builds .agdai interfaces and takes
    -- minutes, which the previous 30 s default would have aborted.
    , runTest "defaultConfig: the enforced default timeout is the documented 300s" $
        assertEqual "timeout" (Just 300) (agdaTimeout defaultConfig)

    , runTest "defaultTimeoutSeconds: matches defaultConfig" $
        assertEqual "timeout" (Just defaultTimeoutSeconds) (agdaTimeout defaultConfig)

    -- Issue #76: the project echo is only as trustworthy as the parsing behind
    -- it.  These pin the two file formats the resolution reads (the libraries
    -- registry and a *.agda-lib) and the flag spellings it has to recognize in
    -- whatever the server was started with.
    , runTest "parseLibrariesFile: skips blanks and comments, resolves relative paths" $
        assertEqual "entries"
          [ "/abs/one/one.agda-lib", "/base/two/two.agda-lib" ]
          (parseLibrariesFile "/base"
             "-- a comment\n/abs/one/one.agda-lib\n\n  two/two.agda-lib  \n")

    , runTest "parseLibrariesFile: a double hyphen inside a path is not a comment" $
        -- A naive breakOn "--" would truncate this to "/base/my", silently
        -- pointing the registry at a directory that does not exist — in a
        -- module whose whole purpose is getting path comparison right.
        assertEqual "entries" ["/base/my--lib/my.agda-lib"]
          (parseLibrariesFile "/base" "/base/my--lib/my.agda-lib -- trailing note\n")

    , runTest "libraryNameOf: the name: field, comments ignored" $
        assertEqual "name" (Just "agda-algebras")
          (libraryNameOf "-- header\nname: agda-algebras  -- the library\ninclude: src\n")

    , runTest "libraryNameOf: no name: field → Nothing" $
        assertEqual "name" Nothing (libraryNameOf "include: src\n")

    , runTest "libraryIncludesOf: several dirs, continuation lines, comments" $
        assertEqual "includes" ["src", "test", "extra"]
          (libraryIncludesOf "name: x\ninclude: src test\n  extra\n-- done\ndepend: y\n")

    , runTest "libraryIncludeDirs: no include: field means the library root" $
        assertEqual "dirs" ["/r"]
          (libraryIncludeDirs LibraryEntry
             { leName = "x", leRoot = "/r", leLibFile = "/r/x.agda-lib", leIncludes = [] })

    , runTest "libraryIncludeDirs: include: dirs are resolved against the root" $
        assertEqual "dirs" ["/r/src", "/r/test"]
          (libraryIncludeDirs LibraryEntry
             { leName = "x", leRoot = "/r", leLibFile = "/r/x.agda-lib"
             , leIncludes = ["src", "test"] })

    , runTest "librariesFileFlagOf: both spellings, and the last one wins" $
        -- The last-wins rule is not academic: the Nix agda wrapper supplies a
        -- --library-file of its own ahead of the caller's flags, so reading the
        -- first would report the store's registry instead of the project's.
        assertEqual "library file" (Just "/second/libraries")
          (librariesFileFlagOf
             [ "--library-file=/first/libraries", "-l", "std"
             , "--library-file", "/second/libraries" ])

    , runTest "librariesFileFlagOf: absent → Nothing" $
        assertEqual "library file" Nothing (librariesFileFlagOf ["-i", "x", "-l", "y"])

    , runTest "includePathsOf: -i DIR, -iDIR, and both --include-path spellings" $
        assertEqual "includes" ["a", "b", "c", "d"]
          (includePathsOf
             ["-i", "a", "-ib", "--include-path=c", "--include-path", "d", "-l", "e"])

    , runTest "selectedLibrariesOf: -l NAME, -lNAME, and both --library spellings" $
        assertEqual "libraries" ["a", "b", "c", "d"]
          (selectedLibrariesOf
             ["-l", "a", "-lb", "--library=c", "--library", "d", "-i", "e"])
    ]



-- ---------------------------------------------------------------------------
-- Tier 0b: Structured-diagnostic tests (issue #74; pure)
--
-- These run the parser over Agda output captured verbatim from the pinned
-- Agda 2.8.0 against the fixtures in test/resources/diagnostics/ (the tier-2e
-- tests below re-derive the same facts from a live Agda, so drift between the
-- two is a test failure rather than a silent divergence).  They also cover the
-- old `LINE,COL` position spelling, which the pinned Agda cannot produce and
-- which the pre-#74 extractor was written for.
-- ---------------------------------------------------------------------------

-- | Captured output: the § 5 pair — a [ModuleDoesntExport] warning on the
-- import, and the [NotInScope] error it causes below.  Note the warning's
-- `-W[no]Code` spelling of the code, and the interleaved `Checking` lines.
outModuleDoesntExport :: Text
outModuleDoesntExport = T.unlines
  [ "Checking ModuleDoesntExport (/r/ModuleDoesntExport.agda)."
  , " Checking DiagBarrel (/r/DiagBarrel.agda)."
  , "/r/ModuleDoesntExport.agda:20.24-50: warning: -W[no]ModuleDoesntExport"
  , "The module DiagBarrel doesn't export the following:"
  , "  absentName"
  , "when scope checking the declaration"
  , "  open import DiagBarrel using (usable; absentName)"
  , ""
  , "/r/ModuleDoesntExport.agda:23.5-15: error: [NotInScope]"
  , "Not in scope:"
  , "  absentName"
  , "  at /r/ModuleDoesntExport.agda:23.5-15"
  , "when scope checking absentName"
  ]

-- | Captured output: [NotInScope] with a "did you mean" list.
outNotInScope :: Text
outNotInScope = T.unlines
  [ "Checking NotInScope (/r/NotInScope.agda)."
  , "/r/NotInScope.agda:16.9-14: error: [NotInScope]"
  , "Not in scope:"
  , "  zeroo"
  , "  at /r/NotInScope.agda:16.9-14"
  , "    (did you mean"
  , "       'Agda.Builtin.Nat.Nat.zero' or"
  , "       'Agda.Builtin.Nat.zero' or"
  , "       'Nat.zero' or"
  , "       'zero'?)"
  , "when scope checking zeroo"
  ]

-- | Captured output: [AmbiguousName], whose candidate list interleaves names
-- with the locations they are bound at.
outAmbiguousName :: Text
outAmbiguousName = T.unlines
  [ "Checking AmbiguousName (/r/AmbiguousName.agda)."
  , "/r/AmbiguousName.agda:19.5-11: error: [AmbiguousName]"
  , "Ambiguous name shared. It could refer to any one of"
  , "  DiagAmbigA.shared bound at"
  , "    /r/DiagAmbigA.agda:13.1-7"
  , "  DiagAmbigB.shared bound at"
  , "    /r/DiagAmbigB.agda:12.1-7"
  , "shared is in scope as"
  , "  * a defined name DiagAmbigA.shared brought into scope by"
  , "    - the opening of DiagAmbigA at /r/AmbiguousName.agda:15.13-23"
  , "when scope checking shared"
  ]

-- | Captured output: [ClashingDefinition], whose sentence wraps across lines.
outClashingDefinition :: Text
outClashingDefinition = T.unlines
  [ "Checking ClashingDefinition (/r/ClashingDefinition.agda)."
  , "/r/ClashingDefinition.agda:22.1-6: error: [ClashingDefinition]"
  , "Multiple definitions of least. Previous definition at"
  , "/r/ClashingDefinition.agda:18.9-14"
  , "when scope checking the declaration"
  , "  least : Nat"
  ]

-- | Captured output: [UnequalTerms], with Agda's subtyping inequality.
outUnequalTerms :: Text
outUnequalTerms = T.unlines
  [ "Checking UnequalTerms (/r/UnequalTerms.agda)."
  , "/r/UnequalTerms.agda:17.5-9: error: [UnequalTerms]"
  , "Bool !=< Nat"
  , "when checking that the expression true has type Nat"
  ]

-- | Captured output: [UnsolvedConstraints] — which carries no position at all,
-- so its header begins the line — followed by [UnsolvedMetaVariables].
outUnsolvedMetas :: Text
outUnsolvedMetas = T.unlines
  [ "Checking UnsolvedMetas (/r/UnsolvedMetas.agda)."
  , "error: [UnsolvedConstraints]"
  , "Failed to solve the following constraints:"
  , "  _n_4 + _m_5 = 3 : Nat (blocked on _n_4)"
  , ""
  , "/r/UnsolvedMetas.agda:26.9-16: error: [UnsolvedMetaVariables]"
  , "Unsolved metas at the following locations:"
  , "  /r/UnsolvedMetas.agda:26.9-16"
  ]

-- | byCode: the first diagnostic carrying a given code.
byCode :: Text -> [Diagnostic] -> Maybe Diagnostic
byCode c = find ((== Just c) . diagCode)

-- | involvedOf: a diagnostic's payload, or the empty one when it is absent.
involvedIn :: Maybe Diagnostic -> Involved
involvedIn = maybe noInvolved diagInvolved

-- | codesOf: the codes of a diagnostic list, in order — the shape the ordering
-- tests assert on.
codesOf :: [Diagnostic] -> [Maybe Text]
codesOf = map diagCode

-- | synthetic: a diagnostic with a code and severity and nothing else, for the
-- ordering and capping tests.
synthetic :: DiagSeverity -> Text -> Diagnostic
synthetic sev code = (plainDiagnostic sev code) { diagCode = Just code }

diagnosticTests :: IO [Bool]
diagnosticTests = do
  hPutStrLn stderr "\n── Structured-diagnostic tests (tier 0b: pure, #74) ──"
  sequence
    [ -- The bug this issue opens with: under Agda 2.8.0 the old extractor found
      -- no positions at all, because it split on the comma of a spelling Agda
      -- had already replaced.  Both spellings must parse.
      runTest "position: Agda 2.8 'LINE.COL-COL' parses (the #74 bug)" $
        case parseDiagnostics outNotInScope of
          [d] -> allOf
            [ assertEqual "code" (Just "NotInScope") (diagCode d)
            , assertEqual "file" (Just "/r/NotInScope.agda") (diagFile d)
            , assertEqual "range" (Just (DiagRange 16 9 16 14)) (diagRange d)
            ]
          ds  -> pure . Fail $ "expected 1 diagnostic, got " <> show (length ds)

    , runTest "position: legacy 'LINE,COL-COL' still parses" $
        case parseDiagnostics "/r/M.agda:10,5-15: error: [NotInScope]\nNot in scope:\n  x\n" of
          [d] -> allOf
            [ assertEqual "range" (Just (DiagRange 10 5 10 15)) (diagRange d)
            , assertEqual "file" (Just "/r/M.agda") (diagFile d)
            ]
          ds  -> pure . Fail $ "expected 1 diagnostic, got " <> show (length ds)

    , runTest "position: multi-line ranges, both spellings" $ do
        let rangeOf out = diagRange =<< listToMaybe (parseDiagnostics out)
        allOf
          [ assertEqual "2.8 'L.C-L.C'" (Just (DiagRange 9 12 11 5))
              (rangeOf "/r/M.agda:9.12-11.5: error: [UnequalTerms]\nBool !=< Nat\n")
          , assertEqual "legacy 'L,C-L,C'" (Just (DiagRange 10 5 11 3))
              (rangeOf "/r/M.agda:10,5-11,3: error: [UnequalTerms]\nBool !=< Nat\n")
          , assertEqual "a bare position" (Just (DiagRange 7 3 7 3))
              (rangeOf "/r/M.agda:7.3: error: [NotInScope]\nNot in scope:\n  x\n")
          ]

    , runTest "header: an error with no position at all is still a diagnostic" $
        -- error: [UnsolvedConstraints] starts the line, so a parser keyed on
        -- ": error:" dropped it entirely before #74.
        case byCode "UnsolvedConstraints" (parseDiagnostics outUnsolvedMetas) of
          Nothing -> pure (Fail "UnsolvedConstraints was not parsed")
          Just d  -> allOf
            [ assertEqual "file" Nothing (diagFile d)
            , assertEqual "range" Nothing (diagRange d)
            , assertEqual "severity" DiagError (diagSeverity d)
            ]

    , runTest "header: a warning's code is its -W[no]Name" $
        case byCode "ModuleDoesntExport" (parseDiagnostics outModuleDoesntExport) of
          Nothing -> pure (Fail "ModuleDoesntExport was not parsed")
          Just d  -> allOf
            [ assertEqual "severity" DiagWarning (diagSeverity d)
            , assertEqual "range" (Just (DiagRange 20 24 20 50)) (diagRange d)
            ]

    , runTest "message: the full body is kept, not just the header line" $
        case byCode "UnequalTerms" (parseDiagnostics outUnequalTerms) of
          Nothing -> pure (Fail "UnequalTerms was not parsed")
          Just d  -> assertEqual "message"
            "Bool !=< Nat\nwhen checking that the expression true has type Nat"
            (diagMessage d)

    , runTest "message: progress lines and the end banner stay out of it" $ do
        let out = T.unlines
              [ "Checking M (/r/M.agda)."
              , "/r/M.agda:6.1-8: warning: -W[no]UnreachableClauses"
              , "Unreachable clause"
              , "when checking the definition of f"
              , ""
              , "———— All done; warnings encountered ————————————————————————"
              , ""
              , "/r/M.agda:6.1-8: warning: -W[no]UnreachableClauses"
              , "Unreachable clause"
              , "when checking the definition of f"
              ]
        case parseDiagnostics out of
          -- One diagnostic, not two: Agda prints every warning a second time
          -- under the banner, and counting both would double every count.
          [d] -> assertEqual "message"
                   "Unreachable clause\nwhen checking the definition of f"
                   (diagMessage d)
          ds  -> pure . Fail $ "expected 1 diagnostic after dedup, got " <> show (length ds)

    , runTest "message: a long body is bounded, and says so" $ do
        let body = [ "  meta " <> T.pack (show i) | i <- [1 :: Int .. 60] ]
            out  = T.unlines $
              [ "error: [UnsolvedConstraints]"
              , "Failed to solve the following constraints:"
              ] <> body
        case parseDiagnostics out of
          [d] -> allOf
            -- The bound is on what is emitted, elision marker included: a
            -- client that budgets maxMessageLines gets no more than that.
            [ assertEqual "message lines" maxMessageLines
                (length (T.lines (diagMessage d)))
            , assert "the elision is stated" ("more lines" `T.isInfixOf` diagMessage d)
              -- Bounding the prose must not cost the structured payload: all 60
              -- constraints are still there under `involved`.
            , assertEqual "metaTypes are not bounded" 60
                (length (invMetaTypes (diagInvolved d)))
            ]
          ds  -> pure . Fail $ "expected 1 diagnostic, got " <> show (length ds)

    , runTest "message: the character bound counts the elision marker too" $ do
        let out = T.unlines
              [ "/r/M.agda:5.1-5: error: [UnequalTerms]"
              , T.replicate 4000 "x"
              ]
        case parseDiagnostics out of
          [d] -> allOf
            [ assertEqual "message length" maxMessageChars (T.length (diagMessage d))
            , assert "the elision is stated" ("…" `T.isSuffixOf` diagMessage d)
            ]
          ds  -> pure . Fail $ "expected 1 diagnostic, got " <> show (length ds)

      -- Dedup keys off what Agda printed, not off what survived the message
      -- bound: two diagnostics that agree for the first maxMessageLines lines
      -- and differ only past it are different diagnostics, and collapsing them
      -- would understate diagnosticsTotal and the error counts.
    , runTest "dedup: two diagnostics differing only past the bound both survive" $ do
        let shared = [ "  constraint " <> T.pack (show i) | i <- [1 :: Int .. 40] ]
            block tl = [ "error: [UnsolvedConstraints]"
                       , "Failed to solve the following constraints:"
                       ] <> shared <> [ "  " <> tl ]
            out = T.unlines (block "blocked on _a" <> block "blocked on _b")
        assertEqual "diagnostics" 2 (length (parseDiagnostics out))

      -- The § 5 payloads, one test per error class.
    , runTest "involved: ModuleDoesntExport names the missing exports" $
        assertEqual "candidates" ["absentName"]
          (invCandidates (involvedIn
            (byCode "ModuleDoesntExport" (parseDiagnostics outModuleDoesntExport))))

    , runTest "involved: NotInScope carries the qualified 'did you mean' names" $
        assertEqual "candidates"
          [ "Agda.Builtin.Nat.Nat.zero", "Agda.Builtin.Nat.zero", "Nat.zero", "zero" ]
          (invCandidates (involvedIn (byCode "NotInScope" (parseDiagnostics outNotInScope))))

    , runTest "involved: AmbiguousName carries the candidates, not their locations" $
        assertEqual "candidates" ["DiagAmbigA.shared", "DiagAmbigB.shared"]
          (invCandidates (involvedIn
            (byCode "AmbiguousName" (parseDiagnostics outAmbiguousName))))

    , runTest "involved: ClashingDefinition carries the previous definition's origin" $
        assertEqual "candidates" ["/r/ClashingDefinition.agda:18.9-14"]
          (invCandidates (involvedIn
            (byCode "ClashingDefinition" (parseDiagnostics outClashingDefinition))))

    , runTest "involved: UnequalTerms carries actual and expected, in that order" $ do
        let inv = involvedIn (byCode "UnequalTerms" (parseDiagnostics outUnequalTerms))
        allOf
          [ assertEqual "actual"   (Just "Bool") (invActual inv)
          , assertEqual "expected" (Just "Nat")  (invExpected inv)
          ]

    , runTest "involved: UnequalTerms handles the 'A != B of type T' shape" $ do
        let out = T.unlines
              [ "/r/M.agda:5.5-9: error: [UnequalTerms]"
              , "1 != 2 of type Nat"
              , "when checking that the expression refl has type 1 ≡ 2"
              ]
            inv = involvedIn (byCode "UnequalTerms" (parseDiagnostics out))
        allOf
          [ assertEqual "actual"   (Just "1") (invActual inv)
          , assertEqual "expected" (Just "2") (invExpected inv)
          ]

      -- Agda fills its sentences to the terminal width, so the phrase that
      -- introduces a list can wrap onto the next line (a long module or name
      -- does it).  The lists are found by their indentation, not by that
      -- phrase, so wrapping must not lose the payload.
    , runTest "involved: a wrapped introducing sentence still yields the list" $ do
        let wrappedExport = T.unlines
              [ "/r/M.agda:3.20-43: warning: -W[no]ModuleDoesntExport"
              , "The module A.Very.Long.Qualified.Barrel.Module doesn't export the"
              , "following:"
              , "  absentName"
              , "when scope checking the declaration"
              ]
            wrappedAmbig = T.unlines
              [ "/r/M.agda:19.5-11: error: [AmbiguousName]"
              , "Ambiguous name aLongEnoughNameToWrap. It could refer to any one"
              , "of"
              , "  A.aLongEnoughNameToWrap bound at"
              , "    /r/A.agda:3.1-4"
              , "  B.aLongEnoughNameToWrap bound at"
              , "    /r/B.agda:3.1-4"
              , "when scope checking aLongEnoughNameToWrap"
              ]
        allOf
          [ assertEqual "missing exports" ["absentName"]
              (invCandidates (involvedIn
                (byCode "ModuleDoesntExport" (parseDiagnostics wrappedExport))))
          , assertEqual "ambiguity candidates"
              ["A.aLongEnoughNameToWrap", "B.aLongEnoughNameToWrap"]
              (invCandidates (involvedIn
                (byCode "AmbiguousName" (parseDiagnostics wrappedAmbig))))
          ]

    , runTest "involved: every 'did you mean' block contributes, not just the first" $ do
        let out = T.unlines
              [ "/r/M.agda:4.9-14: error: [NotInScope]"
              , "Not in scope:"
              , "  aa"
              , "  at /r/M.agda:4.9-14"
              , "    (did you mean 'ab'?)"
              , "  ba"
              , "  at /r/M.agda:5.9-14"
              , "    (did you mean 'bb'?)"
              , "when scope checking aa"
              ]
        assertEqual "candidates" ["ab", "bb"]
          (invCandidates (involvedIn (byCode "NotInScope" (parseDiagnostics out))))

    , runTest "involved: the unsolved classes carry one entry per meta" $ do
        let ds = parseDiagnostics outUnsolvedMetas
        allOf
          [ assertEqual "constraints"
              ["_n_4 + _m_5 = 3 : Nat (blocked on _n_4)"]
              (invMetaTypes (involvedIn (byCode "UnsolvedConstraints" ds)))
          , assertEqual "meta locations"
              ["/r/UnsolvedMetas.agda:26.9-16"]
              (invMetaTypes (involvedIn (byCode "UnsolvedMetaVariables" ds)))
          ]

      -- Root-cause ordering.
    , runTest "order: the precursor warning comes before the error it causes" $
        -- Agda prints ModuleDoesntExport first here anyway; what this pins is
        -- that the ordering does not *undo* that by sinking warnings.
        assertEqual "codes" [Just "ModuleDoesntExport", Just "NotInScope"]
          (codesOf (parseDiagnostics outModuleDoesntExport))

    , runTest "order: scope errors precede type errors, unsolved metas trail" $ do
        let out = T.unlines
              [ "/r/M.agda:30.1-5: error: [UnsolvedMetaVariables]"
              , "Unsolved metas at the following locations:"
              , "  /r/M.agda:30.1-5"
              , "/r/M.agda:20.1-5: error: [UnequalTerms]"
              , "Bool !=< Nat"
              , "/r/M.agda:10.1-5: error: [NotInScope]"
              , "Not in scope:"
              , "  x"
              , "/r/M.agda:5.1-5: warning: -W[no]ModuleDoesntExport"
              , "The module B doesn't export the following:"
              , "  x"
              , "/r/M.agda:1.1-5: error: [LibraryError]"
              , "Library 'nope' not found."
              ]
        assertEqual "codes"
          [ Just "LibraryError", Just "ModuleDoesntExport", Just "NotInScope"
          , Just "UnequalTerms", Just "UnsolvedMetaVariables" ]
          (codesOf (parseDiagnostics out))

    , runTest "order: within one rank Agda's own order survives (stable sort)" $ do
        let ds = [ synthetic DiagError "NotInScope"
                 , synthetic DiagError "AmbiguousName"
                 , synthetic DiagError "ClashingDefinition"
                 ]
        assertEqual "codes" (codesOf ds) (codesOf (sortOn diagnosticRank ds))

      -- The cap.
    , runTest "cap: the default keeps ten and reports the total" $ do
        let ds = [ synthetic DiagError ("E" <> T.pack (show i)) | i <- [1 :: Int .. 25] ]
            (kept, total) = capDiagnostics Nothing ds
        allOf
          [ assertEqual "kept"  defaultMaxDiagnostics (length kept)
          , assertEqual "total" 25 total
          , assertEqual "kept the first ten, in order"
              (codesOf (take defaultMaxDiagnostics ds)) (codesOf kept)
          ]

    , runTest "cap: an explicit bound is honoured; 0 means no bound" $ do
        let ds = [ synthetic DiagError ("E" <> T.pack (show i)) | i <- [1 :: Int .. 25] ]
        allOf
          [ assertEqual "explicit 3"  3  (length (fst (capDiagnostics (Just 3) ds)))
          , assertEqual "0 = no cap"  25 (length (fst (capDiagnostics (Just 0) ds)))
          , assertEqual "total is pre-cap" 25 (snd (capDiagnostics (Just 3) ds))
          ]

    , runTest "cap: a list under the bound is untouched" $ do
        let ds = [ synthetic DiagError "NotInScope" ]
            (kept, total) = capDiagnostics Nothing ds
        allOf [ assertEqual "kept" 1 (length kept), assertEqual "total" 1 total ]

      -- Noise must not become diagnostics.
    , runTest "parse: a clean run yields nothing" $
        assertEqual "diagnostics" 0 . length . parseDiagnostics $ T.unlines
          [ "Checking M (/r/M.agda)."
          , "Finished M."
          ]
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
-- Tier 1e: Hole addressing (issue #79; IO for fixture reads, no Agda)
--
-- Placed here, next to the tier-1a hole model it extends and whose fixtures it
-- reuses; run last among the tier-1 groups, so the console reads in order.
--
-- Addressing is resolved before Agda is ever started, so every one of these
-- runs everywhere the pure tests do — including the misses, which is where the
-- issue's contract actually bites: a position that names no hole must produce
-- an error listing the file's holes, never a silent guess at the nearest one.
--
-- The parse tests belong here for the same reason.  "Which hole did you mean?"
-- is answered at the wire boundary, and a request that carries both spellings,
-- half a position, or none at all is a client that does not know — so it is
-- rejected there rather than resolved by a rule nobody wrote down.
-- ---------------------------------------------------------------------------

-- | A three-hole source with a multi-character hole in the middle, so a
-- position can be tested at a hole's start, strictly inside its span, and one
-- past its end.
addressingSrc :: Text
addressingSrc = T.unlines
  [ "module Addressing where"     -- 1
  , ""                            -- 2
  , "a : Nat"                     -- 3
  , "a = {!!}"                    -- 4: hole 0 at (4, 5), span 4.5-4.9
  , ""                            -- 5
  , "b : Nat"                     -- 6
  , "b = {! zero !}"              -- 7: hole 1 at (7, 5), span 7.5-7.15
  , ""                            -- 8
  , "c : Nat"                     -- 9
  , "c = ?"                       -- 10: hole 2 at (10, 5), span 10.5-10.6
  ]

-- | resolveIn: resolve a reference against 'addressingSrc'.
resolveIn :: HoleRef -> Either Text Int
resolveIn = resolveHoleRef "Addressing.agda" PlainAgda addressingSrc

-- | decodeGoalParams: what the wire parser makes of a @get_goal@ argument
-- object — the hole reference, or the message it refuses with.
decodeGoalParams :: LBS.ByteString -> Either String HoleRef
decodeGoalParams = fmap ggHole . Aeson.eitherDecode

-- | The address shapes the wire parser accepts: the keys each one needs
-- (besides @filePath@), with a minimal request that uses exactly those keys.
--
-- One list, read three times — every shape must parse, every key in it must be
-- a declared schema property, and the shapes must be exactly the alternatives
-- the schema's @oneOf@ advertises.  Both directions matter and both were wrong
-- in earlier rounds of this PR (Copilot review catches): @col@ was accepted but
-- undeclared, so a validating client could not send it; and the schema required
-- only @filePath@, so it advertised an addressless call the parser rejects.
addressShapes :: [([Text], LBS.ByteString)]
addressShapes =
  [ (["holeIndex"],      "{\"filePath\":\"F.agda\",\"holeIndex\":0}")
  , (["line", "column"], "{\"filePath\":\"F.agda\",\"line\":7,\"column\":5}")
  , (["line", "col"],    "{\"filePath\":\"F.agda\",\"line\":7,\"col\":5}")
  ]

-- | The tools that take a hole address.
addressTools :: [Text]
addressTools = ["get_goal", "fill_hole"]

-- | inputSchemaOf: one tool's advertised input schema, read out of the very
-- value @tools/list@ serializes.
inputSchemaOf :: Text -> Aeson.Value -> Aeson.Object
inputSchemaOf name v =
  case Aeson.fromJSON v :: Aeson.Result [Aeson.Object] of
    Aeson.Error _    -> KM.empty
    Aeson.Success ts -> case
      [ schema
      | t <- ts
      , KM.lookup "name" t == Just (Aeson.String name)
      , Just (Aeson.Object schema) <- [KM.lookup "inputSchema" t]
      ] of
        (s : _) -> s
        []      -> KM.empty

-- | schemaProperties: the property names that schema declares.
schemaProperties :: Text -> Aeson.Value -> [Text]
schemaProperties name v =
  case KM.lookup "properties" (inputSchemaOf name v) of
    Just (Aeson.Object props) -> map Key.toText (KM.keys props)
    _                         -> []

-- | schemaAlternatives: the @required@ list of each @oneOf@ branch — the shapes
-- the schema says a legal request has.
schemaAlternatives :: Text -> Aeson.Value -> [[Text]]
schemaAlternatives name v =
  case KM.lookup "oneOf" (inputSchemaOf name v) of
    Just alts -> case Aeson.fromJSON alts :: Aeson.Result [Aeson.Object] of
      Aeson.Success bs ->
        [ ks
        | b <- bs
        , Just req <- [KM.lookup "required" b]
        , Aeson.Success ks <- [Aeson.fromJSON req :: Aeson.Result [Text]]
        ]
      Aeson.Error _ -> []
    _ -> []

-- | advertisedTools: the tool definitions a client receives, with no corpus
-- loaded (so the four proof-state tools and the project gate, and no search
-- tools).
advertisedTools :: Aeson.Value
advertisedTools = toolDefinitions ServerConfig
  { scAgdaConfig  = defaultConfig
  , scGateConfig  = defaultGateConfig
  , scServerName  = "agda-mcp-test"
  , scVersion     = "0"
  , scCorpusIndex = Nothing
  }

holeAddressingTests :: IO [Bool]
holeAddressingTests = do
  hPutStrLn stderr "\n── Hole-addressing tests (tier 1e: no Agda, #79) ──"
  mdSrc <- TIO.readFile ("test" </> "resources" </> "LiterateMd.lagda.md")
  sequence
    [ runTest "offsetOfPosition: round-trips every hole's own (line, col)" $
        assertEqual "offsets"
          (map (Just . hsStart) (findHoles PlainAgda addressingSrc))
          [ offsetOfPosition (hsLine h) (hsCol h) addressingSrc
          | h <- findHoles PlainAgda addressingSrc ]

    , runTest "offsetOfPosition: end-of-line column yes, beyond it no" $ do
        -- Line 4 is "a = {!!}" (8 characters), so column 9 is its end and
        -- column 10 is off the line — which must not silently roll onto line 5.
        r1 <- assert "column 9 (one past the last character) resolves"
                (isJust (offsetOfPosition 4 9 addressingSrc))
        case r1 of
          Fail m -> pure (Fail m)
          Pass   -> allOf
            [ assertEqual "column 10 is off the line" Nothing
                (offsetOfPosition 4 10 addressingSrc)
            , assertEqual "line 99 does not exist" Nothing
                (offsetOfPosition 99 1 addressingSrc)
            , assertEqual "0-based coordinates are not accepted" Nothing
                (offsetOfPosition 0 0 addressingSrc)
            ]

    , runTest "resolveHoleRef: a position at a hole's first character hits it" $
        assertEqual "indices" [Right 0, Right 1, Right 2]
          [ resolveIn (ByPosition (hsLine h) (hsCol h))
          | h <- findHoles PlainAgda addressingSrc ]

    , runTest "resolveHoleRef: a position inside a hole's span hits it" $
        -- Anywhere in {! zero !} — its opening brace, its body, its final
        -- brace — is that hole; one past its last character is not.
        assertEqual "indices" [Right 1, Right 1, Right 1, Left ()]
          [ either (const (Left ())) Right (resolveIn (ByPosition 7 c))
          | c <- [5, 10, 14, 15] ]

    , runTest "resolveHoleRef: a position in no hole names the nearest ones" $
        case resolveIn (ByPosition 8 1) of
          Right i  -> pure (Fail $ "expected a miss, got hole " <> show i)
          Left msg -> allOf
            [ assert "names the position asked for"
                ("line 8, column 1" `T.isInfixOf` msg)
            , assert "names the hole above"  ("line 7, column 5"  `T.isInfixOf` msg)
            , assert "names the hole below"  ("line 10, column 5" `T.isInfixOf` msg)
            , assert "says how many holes there are" ("3 in the file" `T.isInfixOf` msg)
            , assert "points at where the coordinates come from"
                ("get_diagnostics.holes" `T.isInfixOf` msg)
            ]

    , runTest "resolveHoleRef: an out-of-range index says so and lists the holes" $
        case resolveIn (ByIndex 7) of
          Right i  -> pure (Fail $ "expected a miss, got hole " <> show i)
          Left msg -> allOf
            [ assert "keeps the pre-#79 wording" ("Hole index 7" `T.isInfixOf` msg)
            , assert "warns that indices shift" ("shifts down by one" `T.isInfixOf` msg)
            , assert "lists a real hole" ("index 0 at line 4, column 5" `T.isInfixOf` msg)
            ]

    , runTest "resolveHoleRef: a file with no holes says exactly that" $
        case resolveHoleRef "Empty.agda" PlainAgda "x = 1\n" (ByPosition 1 1) of
          Right i  -> pure (Fail $ "expected a miss, got hole " <> show i)
          Left msg -> assert "says the file has no holes"
                        ("Empty.agda has no holes" `T.isInfixOf` msg)

    -- Literate coordinates, the #73 contract seen from the addressing side: a
    -- position is read in the file as written, so the code hole resolves and
    -- the prose decoys above it — which occupy no index either — do not.
    , runTest "resolveHoleRef: literate positions are literate-file coordinates" $
        case (findHoles LiterateMd mdSrc, expectedHolePos mdSrc) of
          ([h], Just (ln, col)) -> allOf
            [ assertEqual "the fixture's own hole position" (ln, col) (hsLine h, hsCol h)
            , assertEqual "resolves by that position" (Right 0)
                (resolveHoleRef "LiterateMd.lagda.md" LiterateMd mdSrc (ByPosition ln col))
            , assert "a prose decoy position is a miss"
                (isLeft (resolveHoleRef "LiterateMd.lagda.md" LiterateMd mdSrc
                          (ByPosition (proseDecoyLine mdSrc) (proseDecoyCol mdSrc))))
            ]
          (hs, _) -> pure . Fail $ "expected 1 hole, got " <> show (length hs)

    , runTest "params: holeIndex alone parses as an index reference" $
        assertEqual "ref" (Right (ByIndex 2))
          (decodeGoalParams "{\"filePath\":\"F.agda\",\"holeIndex\":2}")

    , runTest "params: line + column parses as a position reference" $
        assertEqual "ref" (Right (ByPosition 7 5))
          (decodeGoalParams "{\"filePath\":\"F.agda\",\"line\":7,\"column\":5}")

    -- The response spells the column `col`, so accepting that spelling is what
    -- lets a hole entry be handed straight back with no key renaming — and
    -- giving both spellings is refused like every other ambiguous request,
    -- which is also what makes the schema's oneOf an exact description.
    , runTest "params: col stands in for column, but not alongside it" $ allOf
        [ assertEqual "col alone" (Right (ByPosition 7 5))
            (decodeGoalParams "{\"filePath\":\"F.agda\",\"line\":7,\"col\":5}")
        , case decodeGoalParams "{\"filePath\":\"F.agda\",\"line\":7,\"column\":5,\"col\":5}" of
            Right r  -> pure (Fail $ "both spellings should not parse: " <> show r)
            Left msg -> assert ("message: " <> msg) ("give one of them" `isInfixOf` msg)
        ]

    , runTest "params: both spellings at once is refused, not resolved" $
        case decodeGoalParams "{\"filePath\":\"F.agda\",\"line\":7,\"column\":5,\"holeIndex\":0}" of
          Right r  -> pure (Fail $ "expected a parse failure, got " <> show r)
          Left msg -> assert ("message: " <> msg) ("not both" `isInfixOf` msg)

    , runTest "params: half a position is refused" $ allOf
        [ case decodeGoalParams "{\"filePath\":\"F.agda\",\"line\":7}" of
            Right r  -> pure (Fail $ "expected a parse failure, got " <> show r)
            Left msg -> assert ("message: " <> msg) ("without column" `isInfixOf` msg)
        , case decodeGoalParams "{\"filePath\":\"F.agda\",\"column\":5}" of
            Right r  -> pure (Fail $ "expected a parse failure, got " <> show r)
            Left msg -> assert ("message: " <> msg) ("without line" `isInfixOf` msg)
        ]

    , runTest "params: no address at all is refused, naming both spellings" $
        case decodeGoalParams "{\"filePath\":\"F.agda\"}" of
          Right r  -> pure (Fail $ "expected a parse failure, got " <> show r)
          Left msg -> allOf
            [ assert ("message: " <> msg) ("line, column" `isInfixOf` msg)
            , assert ("message: " <> msg) ("holeIndex"    `isInfixOf` msg)
            ]

    , runTest "params: fill_hole reads the same two spellings" $
        assertEqual "refs" (Right (ByPosition 7 5), Right (ByIndex 1))
          ( fmap fhHole (Aeson.eitherDecode
              "{\"filePath\":\"F.agda\",\"line\":7,\"column\":5,\"candidate\":\"zero\"}")
          , fmap fhHole (Aeson.eitherDecode
              "{\"filePath\":\"F.agda\",\"holeIndex\":1,\"candidate\":\"zero\"}")
          )

    , runTest "params: every advertised address shape parses" $
        assertEqual "shapes that failed to parse" []
          [ ks | (ks, args) <- addressShapes, isLeft (decodeGoalParams args) ]

    -- The other half of the same contract: a client picks what to send by
    -- reading the schema, so an accepted key the schema omits may as well not
    -- exist.  Reads the value tools/list serializes, not the Haskell.
    , runTest "schema: every address key is a declared property (#79)" $
        assertEqual "keys missing from the advertised input schema" []
          [ (tool, k)
          | tool <- addressTools
          , let declared = schemaProperties tool advertisedTools
          , k <- nub (concatMap fst addressShapes)
          , k `notElem` declared
          ]

    -- `required` cannot say "address it somehow", so without the oneOf the
    -- schema advertised a bare {filePath} as a complete call while the parser
    -- refused it.  These are the same three shapes, from the same list.
    , runTest "schema: oneOf advertises exactly the shapes that parse (#79)" $ allOf
        [ assertEqual ("oneOf for " <> T.unpack tool)
            (sort (map (sort . fst) addressShapes))
            (sort (map sort (schemaAlternatives tool advertisedTools)))
        | tool <- addressTools
        ]
    ]

-- | proseDecoyLine / proseDecoyCol: the position of the first @{!!}@ token in
-- the .lagda.md fixture's prose — a token that looks like a hole, sits above
-- the code fence, and must be addressable by nothing.
proseDecoyLine :: Text -> Int
proseDecoyLine src = maybe 1 fst (posOfNth 0 src "{!!}")

proseDecoyCol :: Text -> Int
proseDecoyCol src = maybe 1 snd (posOfNth 0 src "{!!}")


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
-- Tier 1c: Timeout enforcement (subprocess, but no Agda) — issue #77
--
-- These drive a fake `agda` (test/resources/fake-slow-agda.sh) that sleeps for a
-- configurable time, so they can prove `--timeout` is enforced without a real
-- Agda, a real library, or a genuinely hung typechecker.  They run everywhere the
-- pure tests do.
-- ---------------------------------------------------------------------------

-- | The stand-in binary and the fixture the in-place tools patch.
fakeAgdaPath, timeoutFixturePath :: FilePath
fakeAgdaPath       = "test" </> "resources" </> "fake-slow-agda.sh"
timeoutFixturePath = "test" </> "resources" </> "TimeoutFixture.agda"

-- | How long the fake agda "typechecks" for in the tests that expect a timeout.
-- Must comfortably exceed 'fakeTimeoutSecs' so the bound is what ends the run,
-- and must be short enough that a test can outwait it to check for an orphan.
fakeSleepSecs :: Int
fakeSleepSecs = 4

-- | The bound the tests configure.  One second keeps the suite fast while still
-- being long enough that a slow CI box cannot mistake startup for the timeout.
fakeTimeoutSecs :: Int
fakeTimeoutSecs = 1

-- | timeoutTests: the issue #77 acceptance criteria, minus the parts that need a
-- real Agda.
timeoutTests :: IO [Bool]
timeoutTests = do
  hPutStrLn stderr "\n── Timeout tests (tier 1c: fake agda binary, #77) ──"
  fakeExists    <- doesFileExist fakeAgdaPath
  fixtureExists <- doesFileExist timeoutFixturePath
  if not (fakeExists && fixtureExists)
    then do
      hPutStrLn stderr $ "  [skip] fixtures not found: "
        <> fakeAgdaPath <> " / " <> timeoutFixturePath
      pure []
    else do
      fakeAgda <- makeAbsolute fakeAgdaPath
      -- A checkout that lost the executable bit would otherwise fail with a
      -- confusing "permission denied" reported as a crash, so restore it.
      ensureExecutable fakeAgda
      tmpDir <- getTemporaryDirectory
      let marker = tmpDir </> "agda-mcp-timeout-orphan-marker"
          slowCfg = defaultConfig
            { agdaBin     = fakeAgda
            , agdaTimeout = Just fakeTimeoutSecs
            }
      removeIfExists marker
      setEnv "AGDA_MCP_FAKE_MARKER" marker
      setEnv "AGDA_MCP_FAKE_SLEEP" (show fakeSleepSecs)

      -- One slow run, shared by the assertions below, so the suite pays the
      -- timeout wait once.
      slow <- runAgda slowCfg timeoutFixturePath

      results1 <- sequence
        [ runTest "runAgda: a hung agda is reported as timed out, not as a failure" $
            assert ("arTimedOut should be True; got " <> show slow) (arTimedOut slow)

        , runTest "runAgda: the timeout lands at the bound, not at the sleep" $
            -- The fake would have run for 'fakeSleepSecs'; a bound that was not
            -- enforced would show up here as an elapsed time near that instead.
            assert ("elapsedMs = " <> show (arElapsedMs slow))
              (arElapsedMs slow >= 500 && arElapsedMs slow < fakeSleepSecs * 1000)

        , runTest "runAgda: output written before the kill is still captured" $
            -- Proves partial output survives, and that the cache signal is
            -- derived from what the process actually printed: the fake echoes
            -- its "Checking" line before sleeping, so even this killed run
            -- carries positive evidence of a source re-check.
            assert ("stdout was " <> show (arStdout slow))
              (checkedFromSourceOf slow == Just True)
        ]

      -- Outwait the fake's own sleep.  If the subprocess had merely been
      -- abandoned (the failure mode of timing out the waiting Haskell thread
      -- instead of the process), it would finish on its own by now and drop the
      -- marker file.
      threadDelay ((fakeSleepSecs + 2) * 1000 * 1000)
      orphaned <- doesFileExist marker
      results2 <- sequence
        [ runTest "runAgda: the timed-out subprocess is killed, not orphaned" $
            assert "the fake agda completed after the timeout — it was left running"
                   (not orphaned)
        ]

      -- fill_hole must restore the file byte-for-byte on the timeout path too:
      -- runAgda reports the timeout as a value rather than throwing, so the
      -- bracket_ restore in runInPlace runs exactly as on the success path.
      before <- BS.readFile timeoutFixturePath
      fillRes <- handleFillHole slowCfg FillHoleParams
        { fhFilePath  = timeoutFixturePath
        , fhHole      = ByIndex 0
        , fhCandidate = "zero"
        }
      after <- BS.readFile timeoutFixturePath
      results3 <- sequence
        [ runTest "fill_hole: a timeout is status 'timeout', not a type error" $
            case fillRes of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
              Right fr -> assertEqual "status" FillTimeout (frStatus fr)

        , runTest "fill_hole: the timeout message names the bound that was hit" $
            case fillRes of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
              Right fr -> assert ("message was " <> show (frMessage fr))
                (maybe False (\m -> "timed out after 1s" `T.isInfixOf` m) (frMessage fr))

        , runTest "fill_hole: a timed-out response still carries elapsedMs" $
            case fillRes of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
              Right fr -> assert ("elapsedMs = " <> show (frElapsedMs fr))
                            (frElapsedMs fr > 0)

        , runTest "fill_hole: a timed-out in-place call restores the file exactly" $
            assert "fixture should be byte-for-byte unchanged after a timeout"
                   (before == after)
        ]

      -- get_goal is the one tool whose timeout cannot ride inside a
      -- success-shaped response, so its failure must be the structured kind
      -- that still carries the call's measurements (a Copilot review catch on
      -- PR #89: a plain error string dropped elapsedMs on the floor).
      gg <- handleGetGoal slowCfg GetGoalParams
        { ggFilePath = timeoutFixturePath
        , ggHole     = ByIndex 0
        }
      resultsGoal <- sequence
        [ runTest "get_goal: a timeout is a structured failure carrying elapsedMs" $
            case gg of
              Right gi -> pure (Fail $ "expected a timeout failure, got a goal: " <> show gi)
              Left (FailMessage m) ->
                pure (Fail $ "expected FailTimeout, got FailMessage: " <> T.unpack m)
              Left (FailProject pm) ->
                pure (Fail $ "expected FailTimeout, got FailProject: "
                             <> T.unpack (mismatchMessage pm))
              Left (FailPath pf) ->
                pure (Fail $ "expected FailTimeout, got FailPath: "
                             <> T.unpack (pathFailureMessage pf))
              Left (FailTimeout tf) -> do
                r1 <- assert ("elapsedMs = " <> show (tfElapsedMs tf)) (tfElapsedMs tf > 0)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assert ("message was " <> show (tfMessage tf))
                              ("timed out after 1s" `T.isInfixOf` tfMessage tf)
        ]

      -- check_file / get_diagnostics report the timeout as a failed check with an
      -- explanatory diagnostic, rather than as a silent "0 errors" summary of
      -- output Agda never produced.
      chk  <- handleCheckFile slowCfg
                (CheckFileParams timeoutFixturePath Nothing)
      diag <- handleGetDiagnostics slowCfg
                (GetDiagnosticsParams timeoutFixturePath Nothing)
      results4 <- sequence
        [ runTest "check_file: a timeout is success:false with a timeout diagnostic" $
            case chk of
              Left err  -> pure (Fail $ "check_file failed: " <> T.unpack (failureText err))
              Right fcr -> do
                r1 <- assert "success should be False" (not (fcrSuccess fcr))
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> do
                    r2 <- assert "timedOut should be True" (fcrTimedOut fcr)
                    case r2 of
                      Fail m -> pure (Fail m)
                      Pass   -> assert
                        ("diagnostics were " <> show (map diagMessage (fcrDiagnostics fcr)))
                        (any (("agda timed out after" `T.isInfixOf`) . diagMessage)
                             (fcrDiagnostics fcr))

        , runTest "get_diagnostics: a timeout is success:false and counts as an error" $
            case diag of
              Left err -> pure (Fail $ "get_diagnostics failed: " <> T.unpack (failureText err))
              Right dr -> do
                r1 <- assert "success should be False" (not (drSuccess dr))
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> do
                    r2 <- assert "timedOut should be True" (drTimedOut dr)
                    case r2 of
                      Fail m -> pure (Fail m)
                      Pass   -> assert ("errors = " <> show (drErrors dr))
                                  (drErrors dr >= 1)
        ]

      -- Second orphan sweep.  The slow runs after the first sweep (fill_hole,
      -- get_goal, check_file, get_diagnostics) each spawned their own fake with
      -- its own marker subshell; outwait the longest of their sleeps so a
      -- leader-only kill on any of those paths — the exact failure mode of
      -- signalling agda but not its descendants — has had time to surface as a
      -- marker drop.
      threadDelay ((fakeSleepSecs + 2) * 1000 * 1000)
      lateOrphan <- doesFileExist marker
      resultsLate <- sequence
        [ runTest "runAgda: no timed-out tool call leaves a descendant behind" $
            assert "a fake agda descendant outlived its tool call and wrote the marker"
                   (not lateOrphan)
        ]

      -- The fast path: a run that finishes inside its bound must not be reported
      -- as a timeout, and must still be timed.
      setEnv "AGDA_MCP_FAKE_SLEEP" "1"
      removeIfExists marker
      let fastCfg = defaultConfig { agdaBin = fakeAgda, agdaTimeout = Just 60 }
      fast <- runAgda fastCfg timeoutFixturePath
      results5 <- sequence
        [ runTest "runAgda: a run inside the bound is not reported as timed out" $
            assert ("arTimedOut should be False; got " <> show (arTimedOut fast))
                   (not (arTimedOut fast))

        , runTest "runAgda: a completed run reports its real exit code" $
            assertEqual "exit code" 0 (arExitCode fast)

        , runTest "runAgda: elapsedMs measures the real subprocess duration" $
            -- The fake slept a second, so a plausible clock has to show it; this
            -- is what a hard-coded 0 or an uninitialised field would fail.
            assert ("elapsedMs = " <> show (arElapsedMs fast))
              (arElapsedMs fast >= 500 && arElapsedMs fast < 60000)
        ]

      removeIfExists marker
      pure (results1 <> results2 <> results3 <> resultsGoal <> results4
              <> resultsLate <> results5)

-- | ensureExecutable: restore the executable bit on the fake agda script.
-- Git tracks the mode, so this is belt-and-braces for checkouts (or archive
-- extractions) that drop it — without it the failure surfaces as an opaque
-- "permission denied" crash rather than as a fixture problem.
ensureExecutable :: FilePath -> IO ()
ensureExecutable path = do
  perms <- getPermissions path
  setPermissions path (setOwnerExecutable True (perms :: Permissions))

-- | removeIfExists: delete a scratch file, tolerating its absence.
removeIfExists :: FilePath -> IO ()
removeIfExists path = do
  present <- doesFileExist path
  if present then removeFile path else pure ()


-- ---------------------------------------------------------------------------
-- Tier 1d: the response echo and project-root resolution (issues #72, #76)
--
-- No Agda is needed here, and that is the point twice over.
--
-- For the verdict (#72), the claim under test is that @success@ is a function
-- of the exit code and of nothing else.  A real Agda cannot demonstrate that,
-- because its exit code and its message text always agree; the stand-in binary
-- can, by exiting non-zero while printing nothing an error parser could latch
-- onto.  A verdict derived from the diagnostics would report that run green.
--
-- For root resolution (#76), the scene is two checkouts of one library — the
-- one-worktree-per-branch workflow the field report was written in — with a
-- registry that names only the first.  The assertions are that a file in the
-- registered checkout resolves to it, that a file in the other is refused by
-- name, and that the refusal lands before @agda@ is spawned and before any
-- in-place patching.
-- ---------------------------------------------------------------------------

-- | The stand-in agda used below: 'fakeAgdaPath', configured to return at once
-- with a chosen exit status and to leave no marker behind.
--
-- @AGDA_MCP_FAKE_EXIT@ is deliberately left set to whatever a test last chose,
-- so these tests must run after 'timeoutTests', whose fast-path case asserts
-- the default exit status of 0.
withFakeExit :: Int -> IO a -> IO a
withFakeExit code act = do
  setEnv "AGDA_MCP_FAKE_SLEEP" "0"
  setEnv "AGDA_MCP_FAKE_MARKER" ""
  setEnv "AGDA_MCP_FAKE_EXIT" (show code)
  act

-- | The library scene the root-resolution tests run against.
--
-- Four roots, covering the three ways a file's library can relate to the
-- server's registry, plus the conflict that must be refused.
data LibraryScene = LibraryScene
  { lsRootA     :: FilePath  -- ^ library @agda-algebras@; registered AND @-l@-selected.
  , lsRootB     :: FilePath  -- ^ library @agda-algebras@ again — a second checkout, unregistered.
  , lsRootC     :: FilePath  -- ^ library @c-lib@; unknown to the registry entirely.
  , lsRootD     :: FilePath  -- ^ library @d-lib@; registered, but not @-l@-selected.
  , lsLibraries :: FilePath  -- ^ the registry: A and D only.
  }

-- | withLibraryScene: build the scene under the temp directory, run an action on
-- it, and remove it.
--
--   <tmp>/agda-mcp-roots/A/agda-algebras.agda-lib   (name: agda-algebras)  registered, selected
--   <tmp>/agda-mcp-roots/A/src/Target.agda
--   <tmp>/agda-mcp-roots/B/agda-algebras.agda-lib   (name: agda-algebras)  NOT registered
--   <tmp>/agda-mcp-roots/B/src/Target.agda
--   <tmp>/agda-mcp-roots/C/c-lib.agda-lib           (name: c-lib)          NOT registered
--   <tmp>/agda-mcp-roots/C/src/Deep/Target.agda     (nested, so the library's
--                                                    include dir and the file's
--                                                    own directory differ)
--   <tmp>/agda-mcp-roots/D/d-lib.agda-lib           (name: d-lib)          registered, unselected
--   <tmp>/agda-mcp-roots/D/src/Target.agda
--   <tmp>/agda-mcp-roots/libraries                  (registers A and D)
withLibraryScene :: (LibraryScene -> IO a) -> IO a
withLibraryScene act = do
  tmp <- getTemporaryDirectory
  let scene = tmp </> "agda-mcp-roots"
      ls = LibraryScene
        { lsRootA     = scene </> "A"
        , lsRootB     = scene </> "B"
        , lsRootC     = scene </> "C"
        , lsRootD     = scene </> "D"
        , lsLibraries = scene </> "libraries"
        }
  bracket_ (build ls) (removeTree scene) (act ls)
  where
    target = "module Target where\n\nopen import Agda.Builtin.Nat\n\nm : Nat\nm = {!!}\n"

    build ls = do
      removeTree (takeDirectory (lsLibraries ls))
      mapM_ (createDirectoryIfMissing True)
        [ lsRootA ls </> "src", lsRootB ls </> "src"
        , lsRootC ls </> "src" </> "Deep", lsRootD ls </> "src" ]
      mapM_ (\(r, n) -> TIO.writeFile (r </> (n <> ".agda-lib"))
                          ("name: " <> T.pack n <> "\ninclude: src\n"))
        [ (lsRootA ls, "agda-algebras"), (lsRootB ls, "agda-algebras")
        , (lsRootC ls, "c-lib"),         (lsRootD ls, "d-lib") ]
      mapM_ (\f -> TIO.writeFile f target)
        [ lsRootA ls </> "src" </> "Target.agda"
        , lsRootB ls </> "src" </> "Target.agda"
        , lsRootC ls </> "src" </> "Deep" </> "Target.agda"
        , lsRootD ls </> "src" </> "Target.agda" ]
      TIO.writeFile (lsLibraries ls) . T.unlines . map T.pack $
        [ lsRootA ls </> "agda-algebras.agda-lib"
        , lsRootD ls </> "d-lib.agda-lib" ]

    removeTree d = removeDirectoryRecursive d `catch` \(_ :: SomeException) -> pure ()

-- | echoTests: tier 1d.
echoTests :: IO [Bool]
echoTests = do
  hPutStrLn stderr "\n── Response echo and root resolution (tier 1d: #72/#76) ──"
  fakeExists    <- doesFileExist fakeAgdaPath
  fixtureExists <- doesFileExist timeoutFixturePath
  if not (fakeExists && fixtureExists)
    then do
      hPutStrLn stderr $ "  [skip] fixtures not found: "
        <> fakeAgdaPath <> " / " <> timeoutFixturePath
      pure []
    else do
      fakeAgda <- makeAbsolute fakeAgdaPath
      ensureExecutable fakeAgda
      absFixture <- makeAbsolute timeoutFixturePath
      cwd        <- getCurrentDirectory
      let echoCfg = defaultConfig
            { agdaBin     = fakeAgda
            , agdaFlags   = ["-i", "test/resources", "-l", "agda-dojang"]
            , agdaTimeout = Just 60
            }
      -- One red run and one green run, from the same file: only the stand-in's
      -- exit status differs, so anything that changes between them is a
      -- function of the exit code.
      red      <- withFakeExit 42 $ handleCheckFile echoCfg (CheckFileParams timeoutFixturePath Nothing)
      redDiags <- withFakeExit 42 $ handleGetDiagnostics echoCfg (GetDiagnosticsParams timeoutFixturePath Nothing)
      green    <- withFakeExit 0  $ handleCheckFile echoCfg (CheckFileParams timeoutFixturePath Nothing)

      shape <- sequence
        [ runTest "check_file: success is read from the exit code, not from Agda's prose" $
            -- The stand-in exits 42 having printed no "error:" line at all, so
            -- the diagnostics list is empty.  A verdict derived from parsing
            -- messages would call this run green; the exit code says otherwise,
            -- and the exit code is what decides.
            withRight red $ \r -> assert
              ("success=" <> show (fcrSuccess r)
               <> " with " <> show (length (fcrDiagnostics r)) <> " diagnostics")
              (not (fcrSuccess r) && null (fcrDiagnostics r))

        , runTest "check_file: the verdict carries agda's own exit code" $
            withRight red $ \r ->
              assertEqual "exitCode" 42 (vExitCode (fcrVerdict r))

        , runTest "check_file: a silent exit 0 is success" $
            withRight green $ \r -> do
              r1 <- assert "success should be True" (fcrSuccess r)
              case r1 of
                Fail m -> pure (Fail m)
                Pass   -> assertEqual "exitCode" 0 (vExitCode (fcrVerdict r))

        , runTest "get_diagnostics: same success and exit code as check_file (#72)" $
            withRight red $ \c -> withRight redDiags $ \d -> do
              r1 <- assertEqual "success" (fcrSuccess c) (drSuccess d)
              case r1 of
                Fail m -> pure (Fail m)
                Pass   -> assertEqual "exitCode"
                            (vExitCode (fcrVerdict c)) (vExitCode (drVerdict d))

        , runTest "check_file: the command echo is the invocation that ran" $
            withRight red $ \r -> do
              let c = fcrCommand r
              r1 <- assertEqual "binary" "fake-slow-agda.sh" (takeFileName (ceBinary c))
              case r1 of
                Fail m -> pure (Fail m)
                Pass   -> do
                  r2 <- assert ("args were " <> show (ceArgs c))
                          (not (null (ceArgs c)) && last (ceArgs c) == absFixture
                           && "-l" `elem` ceArgs c)
                  case r2 of
                    Fail m -> pure (Fail m)
                    Pass   -> assertEqual "cwd" cwd (ceCwd c)

        , runTest "check_file: the verdict names the equivalent agda command" $
            withRight red $ \r ->
              assert ("equivalentTo was " <> show (vEquivalentTo (fcrVerdict r)))
                (T.pack absFixture `T.isInfixOf` vEquivalentTo (fcrVerdict r)
                 && "fake-slow-agda.sh" `T.isInfixOf` vEquivalentTo (fcrVerdict r))

        , runTest "check_file: the response wire shape carries verdict, command, project" $
            -- Asserted on the encoded JSON, because these key names are the
            -- client-visible contract the tool descriptions advertise; a
            -- refactor that renamed a field would otherwise pass silently.
            withRight red $ \r -> do
              let wire = encodeText r
                  want = [ "\"verdict\":", "\"equivalent-to: ", "\"meaning\":"
                         , "\"exitCode\":42", "\"command\":", "\"binary\":"
                         , "\"args\":", "\"cwd\":", "\"project\":"
                         , "\"rootSource\":", "\"root\":", "\"success\":false" ]
                  missing = [k | k <- want, not (k `T.isInfixOf` wire)]
              assert ("missing from the response: " <> show missing) (null missing)
        ]

      -- Root resolution: two checkouts of one library, a registry naming only
      -- the first, and a binary that does not exist — so any call that reaches
      -- Agda is visible as a crash rather than as a refusal.
      roots <- withLibraryScene $ \ls -> do
        let rootA = lsRootA ls
            rootB = lsRootB ls
            rootC = lsRootC ls
            rootD = lsRootD ls
            libs  = lsLibraries ls
            rootCfg = defaultConfig
              { agdaBin   = "/nonexistent/agda-must-not-run"
              , agdaFlags = ["--library-file=" <> libs, "-l", "agda-algebras"]
              }
            targetA = rootA </> "src" </> "Target.agda"
            targetB = rootB </> "src" </> "Target.agda"
            targetC = rootC </> "src" </> "Deep" </> "Target.agda"
            targetD = rootD </> "src" </> "Target.agda"
        okA     <- handleCheckFile rootCfg (CheckFileParams targetA Nothing)
        okC     <- handleCheckFile rootCfg (CheckFileParams targetC Nothing)
        okD     <- handleCheckFile rootCfg (CheckFileParams targetD Nothing)
        badB    <- handleCheckFile rootCfg (CheckFileParams targetB Nothing)
        badDiag <- handleGetDiagnostics rootCfg (GetDiagnosticsParams targetB Nothing)
        beforeB <- BS.readFile targetB
        badFill <- handleFillHole rootCfg FillHoleParams
          { fhFilePath = targetB, fhHole = ByIndex 0, fhCandidate = "zero" }
        afterB  <- BS.readFile targetB
        sequence
          [ runTest "root resolution: a file in the registered checkout resolves to it" $
              -- agdaBin does not exist, so check_file reports a crash (exit -1)
              -- rather than a refusal: the point is that resolution let it
              -- through, and named the tree it would have checked.
              withRight okA $ \r -> do
                let pc = fcrProject r
                r1 <- assertEqual "rootSource" RootFromAgdaLib (pcRootSource pc)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> do
                    r2 <- assertEqual "root" rootA (pcRoot pc)
                    case r2 of
                      Fail m -> pure (Fail m)
                      Pass   -> assertEqual "library"
                                  (Just "agda-algebras") (leName <$> pcLibrary pc)

          , runTest "root resolution: a file in another checkout of the same library is refused (#76)" $
              case badB of
                Right r -> pure (Fail $ "expected a refusal, got success=" <> show (fcrSuccess r))
                Left (FailProject pm) -> do
                  r1 <- assertEqual "fileRoot" rootB (pmFileRoot pm)
                  case r1 of
                    Fail m -> pure (Fail m)
                    Pass   -> do
                      r2 <- assertEqual "registeredRoot" rootA (pmRegisteredRoot pm)
                      case r2 of
                        Fail m -> pure (Fail m)
                        Pass   -> assertEqual "libraryName" "agda-algebras" (pmLibraryName pm)
                Left other ->
                  pure (Fail $ "expected FailProject, got: " <> T.unpack (failureText other))

          , runTest "root resolution: the refusal names both trees and the registry" $
              case badB of
                Left (FailProject pm) ->
                  let msg = mismatchMessage pm
                      want = [T.pack rootA, T.pack rootB, T.pack libs, "agda-algebras"]
                      missing = [w | w <- want, not (w `T.isInfixOf` msg)]
                  in  assert ("missing from the message: " <> show missing) (null missing)
                _ -> pure (Fail "expected FailProject")

          , runTest "root resolution: the refusal happens before agda is spawned" $
              -- agdaBin is a path that cannot be executed.  Had the call run it,
              -- the result would be a Right carrying exit code -1; a Left proves
              -- resolution short-circuited first.
              assert "expected a refusal rather than a failed agda run" (isLeft badB)

          , runTest "root resolution: get_diagnostics refuses the same way" $
              case badDiag of
                Left (FailProject _) -> pure Pass
                Left other -> pure (Fail $ "expected FailProject, got: "
                                           <> T.unpack (failureText other))
                Right _    -> pure (Fail "expected a refusal")

          , runTest "root resolution: fill_hole refuses without touching the file" $
              case badFill of
                Left (FailProject _) ->
                  assert "the source file was modified by a refused call" (beforeB == afterB)
                Left other -> pure (Fail $ "expected FailProject, got: "
                                           <> T.unpack (failureText other))
                Right _    -> pure (Fail "expected a refusal")

            -- The echo must describe the flags Agda was actually given, not the
            -- ones the server started with.  Resolution extends them two ways —
            -- an unregistered library contributes its include dirs, a registered
            -- but unselected one contributes a --library — and the requested
            -- file's own directory is added on every call.  A project block
            -- built before those additions would quietly describe a context Agda
            -- never saw (Copilot's review of PR 95).
          , runTest "project echo: includePaths cover the file's own directory" $
              withRight okA $ \r ->
                let pc = fcrProject r
                    dir = rootA </> "src"
                in  assert ("includePaths were " <> show (pcIncludePaths pc))
                      (dir `elem` pcIncludePaths pc)

          , runTest "project echo: an unregistered library's include dirs are reported" $
              withRight okC $ \r ->
                let pc   = fcrProject r
                    want = [rootC </> "src", rootC </> "src" </> "Deep"]
                    miss = [d | d <- want, d `notElem` pcIncludePaths pc]
                in  assert ("missing from includePaths " <> show (pcIncludePaths pc)
                            <> ": " <> show miss) (null miss)

          , runTest "project echo: a registered-but-unselected library is reported as selected" $
              withRight okD $ \r ->
                let pc = fcrProject r
                in  assert ("selectedLibraries were " <> show (pcSelected pc))
                      ("d-lib" `elem` pcSelected pc)

          , runTest "project echo: a configured-but-missing registry is echoed, not omitted" $ do
              -- A --library-file naming a path that is not there used to vanish
              -- from the echo entirely, so the response read as "no registry
              -- configured" while command.args still carried the flag — and the
              -- caller lost the one clue explaining the failure (Copilot's
              -- second review of PR 95).  It is also the case where the
              -- wrong-tree check is silently inert, since there is nothing to
              -- compare against, so the response has to say so.
              let ghost   = takeDirectory libs </> "no-such-libraries"
                  ghostCfg = defaultConfig
                    { agdaBin   = "/nonexistent/agda-must-not-run"
                    , agdaFlags = ["--library-file=" <> ghost, "-l", "agda-algebras"]
                    }
              res <- handleCheckFile ghostCfg (CheckFileParams targetA Nothing)
              withRight res $ \r -> do
                let pc = fcrProject r
                r1 <- assertEqual "librariesFile" (Just ghost) (pcLibrariesFile pc)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> do
                    r2 <- assert "librariesFileMissing should be True"
                            (pcLibrariesFileMissing pc)
                    case r2 of
                      Fail m -> pure (Fail m)
                      Pass   -> assert
                        ("registeredLibraries should be empty, got "
                         <> show (map leName (pcRegistered pc)))
                        (null (pcRegistered pc))

          , runTest "project echo: an empty --library-file is not resolved to the cwd" $ do
              -- "--library-file=" (an unset variable in a template) used to be
              -- absolutised into the current directory, so the echo named a
              -- directory nobody configured as the registry.  Agda does not fall
              -- back on an empty value either — it fails with
              -- "[LibraryError] Libraries file not found:" — so the faithful
              -- echo is the value as configured, flagged absent (Copilot's third
              -- review of PR 95).
              cwd <- getCurrentDirectory
              let emptyCfg = defaultConfig
                    { agdaBin   = "/nonexistent/agda-must-not-run"
                    , agdaFlags = ["--library-file=", "-l", "agda-algebras"]
                    }
              res <- handleCheckFile emptyCfg (CheckFileParams targetA Nothing)
              withRight res $ \r -> do
                let pc = fcrProject r
                r1 <- assert ("librariesFile should not be the cwd, got "
                              <> show (pcLibrariesFile pc))
                        (pcLibrariesFile pc /= Just cwd)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> do
                    r2 <- assertEqual "librariesFile" (Just "") (pcLibrariesFile pc)
                    case r2 of
                      Fail m -> pure (Fail m)
                      Pass   -> assert "librariesFileMissing should be True"
                                  (pcLibrariesFileMissing pc)

          , runTest "project echo: a readable registry is not flagged as missing" $
              withRight okA $ \r ->
                assert "librariesFileMissing should be False for a real registry"
                  (not (pcLibrariesFileMissing (fcrProject r)))

          , runTest "project echo: the echo agrees with the command that ran" $
              -- The two views a client can take of the same call must not differ.
              withRight okD $ \r ->
                let pc   = fcrProject r
                    args = ceArgs (fcrCommand r)
                    ok   = all (`elem` map T.pack args) (pcSelected pc)
                             && all (`elem` args) (pcIncludePaths pc)
                in  assert ("project " <> show (pcSelected pc, pcIncludePaths pc)
                            <> " not all present in args " <> show args) ok
          ]

      -- The upward walk itself, against this repository: a fixture inside
      -- agda-dojang belongs to agda-dojang, and a file under agda-mcp belongs
      -- to no library at all — the walk must stop at the repo root rather than
      -- climbing into whatever sits above the checkout.
      dojangRoot <- makeAbsolute (".." </> "agda-dojang")
      nearDojang <- findNearestAgdaLib (".." </> "agda-dojang" </> "data" </> "fixtures")
      nearHere   <- findNearestAgdaLib ("test" </> "resources")
      walk <- sequence
        [ runTest "findNearestAgdaLib: a fixture under agda-dojang resolves to that library" $
            assertEqual "library" (Just ("agda-dojang", dojangRoot))
              ((\e -> (leName e, leRoot e)) <$> nearDojang)

        , runTest "findNearestAgdaLib: the walk stops at the repository boundary" $
            assertEqual "library" Nothing (leName <$> nearHere)
        ]

      pure (shape <> roots <> walk)

-- | withRight: run an assertion on a handler's success value, failing the test
-- with the handler's own message when it returned a failure instead.
withRight :: Either ToolFailure a -> (a -> IO TestResult) -> IO TestResult
withRight (Left err) _ = pure (Fail $ "handler failed: " <> T.unpack (failureText err))
withRight (Right a)  k = k a

-- | encodeText: a value's JSON serialization, as Text, for wire-shape assertions.
encodeText :: Aeson.ToJSON a => a -> Text
encodeText = TE.decodeUtf8 . LBS.toStrict . Aeson.encode . Aeson.toJSON


-- ---------------------------------------------------------------------------
-- Tier 1f: the whole-project gate — check_project (issue #78)
--
-- The tool runs a project's real acceptance gate, so the one thing these tests
-- must not do is run this repository's.  Every gate here is
-- test/resources/fake-project-gate.sh, which prints Agda-shaped output and then
-- exits the way its mode says; the fixture projects are built under the temp
-- directory and removed afterwards.
--
-- The mode that earns its keep is `masked`: a wrapper whose last command is an
-- echo, so the shell exits 0 for a build that failed.  That is the trap § 3.5
-- of the feedback document describes — the reason the field session had to grep
-- its build logs for "error:" — and the test below is what pins that
-- check_project reports it as a masked failure rather than as a pass.
-- ---------------------------------------------------------------------------

-- | The stand-in gate, and how long its slow mode sleeps.
fakeGatePath :: FilePath
fakeGatePath = "test" </> "resources" </> "fake-project-gate.sh"

-- | GateScene: three fixture projects, one per way discovery can go.
data GateScene = GateScene
  { gsProject  :: FilePath -- ^ a Makefile declaring @check@ (and a @sub/@ to anchor from)
  , gsSub      :: FilePath -- ^ a subdirectory of it, so the upward walk is exercised
  , gsEntry    :: FilePath -- ^ no Makefile, but an @Everything.agda@
  , gsBare     :: FilePath -- ^ neither: the "no gate found" case
  , gsShadowed :: FilePath -- ^ a @GNUmakefile@ without @check@ shadowing a @Makefile@ with it
  }

-- | withGateScene: build the scene, run an action on it, remove it.
--
--   \<tmp\>/agda-mcp-gate/project/.git          (a file, so the walk stops here)
--   \<tmp\>/agda-mcp-gate/project/Makefile      (check: runs the fixture gate)
--   \<tmp\>/agda-mcp-gate/project/sub/
--   \<tmp\>/agda-mcp-gate/entry/.git
--   \<tmp\>/agda-mcp-gate/entry/Everything.agda
--   \<tmp\>/agda-mcp-gate/bare/.git
--   \<tmp\>/agda-mcp-gate/shadowed/.git
--   \<tmp\>/agda-mcp-gate/shadowed/GNUmakefile  (no check target)
--   \<tmp\>/agda-mcp-gate/shadowed/Makefile     (has one, but make never reads it)
--
-- The @.git@ markers are what make these projects rather than directories: the
-- upward search stops at a repository boundary, so without them a fixture would
-- climb into the temp directory's parents and could find a real Makefile.
withGateScene :: FilePath -> (GateScene -> IO a) -> IO a
withGateScene gate act = do
  tmp <- getTemporaryDirectory
  let scene = tmp </> "agda-mcp-gate"
      gs = GateScene
        { gsProject  = scene </> "project"
        , gsSub      = scene </> "project" </> "sub"
        , gsEntry    = scene </> "entry"
        , gsBare     = scene </> "bare"
        , gsShadowed = scene </> "shadowed"
        }
  bracket_ (build gs scene) (removeTree scene) (act gs)
  where
    build gs scene = do
      removeTree scene
      mapM_ (createDirectoryIfMissing True)
        [gsSub gs, gsEntry gs, gsBare gs, gsShadowed gs]
      mapM_ (\d -> TIO.writeFile (d </> ".git") "gitdir: fixture\n")
        [gsProject gs, gsEntry gs, gsBare gs, gsShadowed gs]
      TIO.writeFile (gsProject gs </> "Makefile") (makefileFor gate)
      TIO.writeFile (gsEntry gs </> "Everything.agda")
        "module Everything where\n\nopen import Agda.Builtin.Nat\n"
      -- GNU make reads GNUmakefile and never looks at Makefile, so a `check`
      -- declared only in the latter is not this project's gate.
      TIO.writeFile (gsShadowed gs </> "GNUmakefile") "other:\n\t@true\n"
      TIO.writeFile (gsShadowed gs </> "Makefile")    "check:\n\t@true\n"

    makefileFor g = T.unlines
      [ "# Fixture Makefile for the tier-1f gate tests (issue #78)."
      , "GATE := " <> T.pack g
      , ""
      , "check:"
      , "\t@$(GATE) fail"
      , ""
      , "other:"
      , "\t@true"
      ]

    removeTree d = removeDirectoryRecursive d `catch` \(_ :: SomeException) -> pure ()

-- | A Makefile exercising every shape the target scan has to tell apart.
makefileSample :: Text
makefileSample = T.unlines
  [ "# a comment: with a colon in it"
  , "SIMPLE = a:b"
  , "IMMEDIATE := /some/path"
  , "POSIX ::= x"
  , "FANCY :::= y"
  , ".PHONY: check test"
  , "check test: deps"
  , "\t@echo not-a-target: this is a recipe"
  , "double:: dep"
  , "%.o: %.c"
  ]

-- | gateTests: tier 1f.
gateTests :: IO [Bool]
gateTests = do
  hPutStrLn stderr "\n── Whole-project gate (tier 1f: check_project, #78) ──"
  gateExists <- doesFileExist fakeGatePath
  if not gateExists
    then do
      hPutStrLn stderr $ "  [skip] fixture not found: " <> fakeGatePath
      pure []
    else do
      gate <- makeAbsolute fakeGatePath
      ensureExecutable gate

      pureRes <- sequence
        [ runTest "makefileTargets: rule lines declare targets, assignments do not" $
            assertEqual "targets"
              [".PHONY", "check", "test", "double", "%.o"]
              (makefileTargets makefileSample)

        , runTest "parseCheckingLine: an indented progress line parses; prose does not" $
            allOf
              [ assertEqual "indented"
                  (Just ("Gate.Broken", "/fixture/Gate/Broken.agda"))
                  (parseCheckingLine "  Checking Gate.Broken (/fixture/Gate/Broken.agda).")
              , assertEqual "prose" Nothing
                  (parseCheckingLine "Checking that the expression has type Nat")
              , assertEqual "no path" Nothing
                  (parseCheckingLine "Checking Gate.Broken.")
              ]

        , runTest "progressModules: every announced module, in order" $
            assertEqual "modules" ["A", "B", "A"]
              (map fst (progressModules
                 (T.unlines [ "Checking A (/x/A.agda)."
                            , "make: nothing to be done"
                            , "  Checking B (/x/B.agda)."
                            , "Checking A (/x/A.agda)." ])))

        , runTest "failingModuleOf: a located error names its own module" $
            let progress = [("A", "/x/A.agda"), ("B", "/x/B.agda")]
                err = (plainDiagnostic DiagError "boom") { diagFile = Just "/x/B.agda" }
            in  assertEqual "module and file"
                  (Just "B", Just "/x/B.agda") (failingModuleOf progress (Just err))

        , runTest "failingModuleOf: with no located error, the last module started" $
            let progress = [("A", "/x/A.agda"), ("B", "/x/B.agda")]
            in  assertEqual "module and file"
                  (Just "B", Just "/x/B.agda") (failingModuleOf progress Nothing)

        , runTest "outputTailOf: keeps the end, and pays for the marker out of the bound" $
            -- The marker occupies one of the maxTailLines, rather than being
            -- added on top of them: the bound is on the text as emitted, which
            -- is 'AgdaMCP.Diagnostics.boundMessage''s rule and was this
            -- function's stated contract before it was its behaviour (Copilot's
            -- third review of PR 98).
            let txt  = T.unlines [T.pack ("line " <> show i) | i <- [1 :: Int .. 100]]
                tail' = maybe "" id (outputTailOf txt)
                ls    = T.lines tail'
            in  allOf
                  [ assertEqual "lines emitted" maxTailLines (length ls)
                  , assert ("first line was " <> show (listToMaybe ls))
                      (maybe False ("61 earlier lines elided" `T.isInfixOf`) (listToMaybe ls))
                  , assert "the last line of the output must survive"
                      ("line 100" `T.isInfixOf` tail')
                  ]

        , runTest "outputTailOf: output that fits the bound is returned whole" $
            let txt = T.unlines [T.pack ("line " <> show i) | i <- [1 :: Int .. maxTailLines]]
            in  allOf
                  [ assertEqual "lines emitted" maxTailLines
                      (length (T.lines (maybe "" id (outputTailOf txt))))
                  , assert "no elision marker on output that fits"
                      (maybe False (not . ("elided" `T.isInfixOf`)) (outputTailOf txt))
                  ]

        , runTest "outputTailOf: empty output has no tail" $
            assertEqual "tail" Nothing (outputTailOf "   \n\n  ")

        , runTest "gateFailureLines: make's own failure lines, and nothing else" $
            -- The evidence that catches a mask hiding a failure Agda never saw.
            -- A line that merely mentions make is not evidence.
            allOf
              [ assertEqual "matches"
                  [ "make: *** [Makefile:12: check] Error 127"
                  , "make[1]: *** No rule to make target 'check'.  Stop."
                  , "gmake: *** [check] Error 1"
                  ]
                  (gateFailureLines (T.unlines
                     [ "Checking A (/x/A.agda)."
                     , "make: *** [Makefile:12: check] Error 127"
                     , "  make[1]: *** No rule to make target 'check'.  Stop."
                     , "gmake: *** [check] Error 1"
                     ]))
              , assertEqual "no false positives" []
                  (gateFailureLines (T.unlines
                     [ "make: Nothing to be done for 'check'."
                     , "make: Entering directory '/x'"
                     , "echo \"make: *** pretend\" > log"
                     , "/x/M.agda:3.1-5: error: [NotInScope]"
                     ]))
              ]
        ]

      sceneRes <- withGateScene gate $ \gs -> do
        -- agdaBin points nowhere: a configured gate must never reach for agda,
        -- so any test that does would fail as a crash rather than pass quietly.
        let agdaCfg = defaultConfig { agdaBin = "/nonexistent/agda-must-not-run" }
            gateCfg mode secs = GateConfig
              { gcCommand = Just (gate : mode)
              , gcTimeout = Just secs
              }
            paramsAt dir = CheckProjectParams
              { cppTarget         = Nothing
              , cppProjectPath    = Just dir
              , cppMaxDiagnostics = Nothing
              }

        failRes   <- handleCheckProject agdaCfg (gateCfg ["fail"] 60)
                       (paramsAt (gsProject gs))
        passRes   <- handleCheckProject agdaCfg (gateCfg ["pass", "1"] 60)
                       (paramsAt (gsProject gs))
        maskedRes <- handleCheckProject agdaCfg (gateCfg ["masked"] 60)
                       (paramsAt (gsProject gs))
        maskedMake <- handleCheckProject agdaCfg (gateCfg ["masked-make"] 60)
                        (paramsAt (gsProject gs))

        failing <- sequence
          [ runTest "check_project: a gate that fails mid-run is a non-success verdict" $
              withRight failRes $ \r -> allOf
                [ assert ("success was " <> show (cprSuccess r)) (not (cprSuccess r))
                , assertEqual "exitCode" 1 (vExitCode (cprVerdict r))
                , assert "a gate that exits non-zero is not a masked failure"
                    (not (cprMaskedFailure r))
                , assert "timedOut should be False" (not (cprTimedOut r))
                ]

          , runTest "check_project: the failing gate's first error is structured (#74)" $
              withRight failRes $ \r -> case cprFirstError r of
                Nothing -> pure (Fail "no firstError in the response")
                Just d  -> allOf
                  [ assertEqual "code" (Just "NotInScope") (diagCode d)
                  , assertEqual "file" (Just "/fixture/Gate/Broken.agda") (diagFile d)
                  , assertEqual "range start" (Just (16, 9))
                      ((\g -> (rngStartLine g, rngStartCol g)) <$> diagRange d)
                  , assert ("candidates were " <> show (invCandidates (diagInvolved d)))
                      ("zero" `elem` invCandidates (diagInvolved d))
                  ]

          , runTest "check_project: the failing gate names the module it stopped in" $
              withRight failRes $ \r -> allOf
                [ assertEqual "failingModule" (Just "Gate.Broken") (cprFailingModule r)
                , assertEqual "failingFile"
                    (Just "/fixture/Gate/Broken.agda") (cprFailingFile r)
                ]

          , runTest "check_project: a failing gate returns the tail of its output" $
              -- The replacement for grepping the build log: a gate can fail for
              -- reasons Agda never printed, so the tail is there whenever the
              -- check did not pass.
              withRight failRes $ \r ->
                assert ("outputTail was " <> show (cprOutputTail r))
                  (maybe False ("NotInScope" `T.isInfixOf`) (cprOutputTail r))

          , runTest "check_project: modulesChecked counts the modules the gate rebuilt" $
              withRight failRes $ \r -> assertEqual "modulesChecked" 2 (cprModulesChecked r)
          ]

        passing <- sequence
          [ runTest "check_project: a passing gate names the command it ran and its elapsed time" $
              withRight passRes $ \r -> allOf
                [ assert ("success was " <> show (cprSuccess r)) (cprSuccess r)
                , assertEqual "exitCode" 0 (vExitCode (cprVerdict r))
                , assert ("elapsedMs = " <> show (cprElapsedMs r))
                    (cprElapsedMs r >= 500 && cprElapsedMs r < 60000)
                , assert ("equivalentTo was " <> show (vEquivalentTo (cprVerdict r)))
                    ("fake-project-gate.sh" `T.isInfixOf` vEquivalentTo (cprVerdict r)
                     && T.pack (gsProject gs) `T.isInfixOf` vEquivalentTo (cprVerdict r))
                , assertEqual "args" ["pass", "1"] (ceArgs (cprCommand r))
                , assertEqual "cwd" (gsProject gs) (ceCwd (cprCommand r))
                  -- The tail comes back even on a pass: a mask this server
                  -- cannot recognize is reported as a pass, so withholding the
                  -- output exactly there is what would hide it.
                , assert ("outputTail was " <> show (cprOutputTail r))
                    (maybe False ("Gate.Ok" `T.isInfixOf`) (cprOutputTail r))
                , assertEqual "timeoutSeconds" (Just 60) (cprTimeoutSeconds r)
                ]

          , runTest "check_project: a passing gate echoes the gate it chose" $
              withRight passRes $ \r ->
                let g = cprGate r
                in  allOf
                      [ assertEqual "source" GateFromServerConfig (gateSource g)
                      , assertEqual "searchedFrom" (gsProject gs) (gateSearchedFrom g)
                      , assertEqual "target" Nothing (gateTarget g)
                      ]

          , runTest "check_project: a passing gate has no failing module" $
              -- The progress fallback is for a check that did not pass.  Asking
              -- for it unconditionally made a green run name the last module it
              -- checked as the one it stopped in — a failure report about a
              -- success (Copilot's third review of PR 98).
              withRight passRes $ \r -> allOf
                [ assertEqual "failingModule" Nothing (cprFailingModule r)
                , assertEqual "failingFile" Nothing (cprFailingFile r)
                , assert "neither key belongs in a passing response"
                    (not ("\"failingModule\":" `T.isInfixOf` encodeText r)
                     && not ("\"failingFile\":" `T.isInfixOf` encodeText r))
                ]
          ]

        masked <- sequence
          [ runTest "check_project: a wrapper ending in echo is a masked failure, not a pass" $
              -- The field-session trap, verbatim: the gate's own exit status is
              -- 0 and is echoed as 0, and the check is still not a success.
              withRight maskedRes $ \r -> allOf
                [ assertEqual "exitCode" 0 (vExitCode (cprVerdict r))
                , assert "maskedFailure should be True" (cprMaskedFailure r)
                , assert ("success was " <> show (cprSuccess r)) (not (cprSuccess r))
                , assertEqual "firstError code" (Just "NotInScope")
                    (cprFirstError r >>= diagCode)
                , assertEqual "failingModule" (Just "Gate.Broken") (cprFailingModule r)
                ]

          , runTest "check_project: the masked failure is visible in the wire shape" $
              -- These key names are the client-visible contract the tool
              -- description advertises, so they are asserted on the JSON.
              withRight maskedRes $ \r ->
                let wire = encodeText r
                    want = [ "\"success\":false", "\"maskedFailure\":true"
                           , "\"exitCode\":0", "\"firstError\":"
                           , "\"failingModule\":", "\"outputTail\":"
                           , "\"gate\":", "\"modulesChecked\":" ]
                    missing = [k | k <- want, not (k `T.isInfixOf` wire)]
                in  assert ("missing from the response: " <> show missing) (null missing)

          , runTest "check_project: a mask with no Agda diagnostic is still caught" $
              -- Copilot's review of PR 98: judging the mask from Agda's
              -- diagnostics alone let a wrapper hiding a *non-Agda* failure —
              -- a missing tool, make giving up — come back success:true with
              -- nothing in the response to show it.  The gate's own failure
              -- line is evidence too, and it becomes the diagnostic that
              -- explains the verdict.
              withRight maskedMake $ \r -> allOf
                [ assertEqual "exitCode" 0 (vExitCode (cprVerdict r))
                , assert "maskedFailure should be True" (cprMaskedFailure r)
                , assert ("success was " <> show (cprSuccess r)) (not (cprSuccess r))
                , assert ("firstError was " <> show (cprFirstError r))
                    (maybe False (("make: *** [Makefile:12: check] Error 127" `T.isInfixOf`)
                                   . diagMessage)
                           (cprFirstError r))
                , assert ("outputTail was " <> show (cprOutputTail r))
                    (maybe False ("command not found" `T.isInfixOf`) (cprOutputTail r))
                ]

          , runTest "check_project: a passing gate does not claim a masked failure" $
              -- The key, not the word: verdict.meaning explains maskedFailure in
              -- prose on every response, so the search has to be for the JSON
              -- key ("maskedFailure":) rather than for the name.
              withRight passRes $ \r ->
                assert "maskedFailure must be absent from a clean pass"
                  (not (cprMaskedFailure r)
                   && not ("\"maskedFailure\":" `T.isInfixOf` encodeText r))
          ]

        -- The timeout path.  One slow run at a one-second bound, then an
        -- orphan sweep: the fixture's marker is written by a backgrounded
        -- subshell, so it appears only if something outlived the kill.
        tmpDir <- getTemporaryDirectory
        let marker = tmpDir </> "agda-mcp-gate-orphan-marker"
        removeIfExists marker
        slowRes <- handleCheckProject agdaCfg
                     (gateCfg ["slow", show fakeSleepSecs, marker] 1)
                     (paramsAt (gsProject gs))
        timeoutFast <- sequence
          [ runTest "check_project: a gate that outruns --check-timeout is a timeout" $
              withRight slowRes $ \r -> allOf
                [ assert "timedOut should be True" (cprTimedOut r)
                , assert ("success was " <> show (cprSuccess r)) (not (cprSuccess r))
                , assertEqual "timeoutSeconds" (Just 1) (cprTimeoutSeconds r)
                , assert ("elapsedMs = " <> show (cprElapsedMs r))
                    (cprElapsedMs r >= 500 && cprElapsedMs r < fakeSleepSecs * 1000)
                , assert "a timeout is not a masked failure"
                    (not (cprMaskedFailure r))
                ]

          , runTest "check_project: a run with no status of its own reports exitCode -1" $
              -- Both no-status cases report -1, and timedOut is what tells them
              -- apart; a killed process's real status is the signal that took it
              -- down, which is why #77 reports the fact as a flag rather than as
              -- a magic exit code.  The start-failure half is asserted below.
              withRight slowRes $ \r -> allOf
                [ assertEqual "exitCode" (-1) (vExitCode (cprVerdict r))
                , assert "timedOut is what distinguishes it from a gate that never started"
                    (cprTimedOut r)
                ]

          , runTest "check_project: a timed-out gate still reports how far it got" $
              -- The progress a blocking call can otherwise not give: the module
              -- it was in, and how many it had rebuilt.
              withRight slowRes $ \r -> allOf
                [ assertEqual "modulesChecked" 1 (cprModulesChecked r)
                , assertEqual "failingModule" (Just "Gate.Slow") (cprFailingModule r)
                , assert ("diagnostics were " <> show (map diagMessage (cprDiagnostics r)))
                    (any (("the project gate timed out after 1s" `T.isInfixOf`) . diagMessage)
                         (cprDiagnostics r))
                , assert ("outputTail was " <> show (cprOutputTail r))
                    (maybe False ("Gate.Slow" `T.isInfixOf`) (cprOutputTail r))
                ]
          ]

        -- Outwait the fixture's own sleep: a kill that took the leader but left
        -- its backgrounded child running would drop the marker by now.
        threadDelay ((fakeSleepSecs + 2) * 1000 * 1000)
        orphaned <- doesFileExist marker
        removeIfExists marker
        timeoutOrphan <- sequence
          [ runTest "check_project: the timed-out gate's whole process group is killed" $
              assert "a descendant of the gate outlived the tool call and wrote the marker"
                     (not orphaned)
          ]

        -- Discovery: what runs when nothing is configured.
        found     <- findMakefileGate "check" (gsSub gs)
        missed    <- findMakefileGate "nope"  (gsSub gs)
        shadowed  <- findMakefileGate "check" (gsShadowed gs)
        projectPc <- contextFor agdaCfg (gsProject gs)
        entryPc   <- contextFor agdaCfg (gsEntry gs)
        barePc    <- contextFor agdaCfg (gsBare gs)
        makeGate  <- resolveGate defaultGateConfig agdaCfg projectPc (gsSub gs) Nothing
        entryGate <- resolveGate defaultGateConfig agdaCfg entryPc (gsEntry gs) Nothing
        bareGate  <- resolveGate defaultGateConfig agdaCfg barePc (gsBare gs) Nothing
        cfgGate   <- resolveGate (gateCfg ["pass"] 60) agdaCfg projectPc (gsProject gs) Nothing
        cfgTarget <- resolveGate (gateCfg ["pass"] 60) agdaCfg projectPc (gsProject gs) (Just "other")

        discovery <- sequence
          [ runTest "gate discovery: the nearest Makefile declaring the target wins" $
              assertEqual "makefile and dir"
                (Right (gsProject gs </> "Makefile", gsProject gs)) found

          , runTest "gate discovery: an undeclared target misses, listing every directory searched" $
              assertEqual "searched" (Left [gsSub gs, gsProject gs]) missed

          , runTest "gate discovery: only the makefile make itself would read is consulted" $
              -- A GNUmakefile shadows a Makefile for GNU make, so a `check`
              -- declared only in the shadowed file is not a gate: naming it
              -- would echo a makefile the run never read, and `make check`
              -- would then fail for a target we had just said existed.
              assertEqual "searched" (Left [gsShadowed gs]) shadowed

          , runTest "gate discovery: with no target given, the Makefile's check target is the gate" $
              case makeGate of
                Left why   -> pure (Fail ("expected a gate: " <> T.unpack why))
                Right plan -> allOf
                  [ assertEqual "source" GateFromMakefile (gateSource (gpGate plan))
                  , assertEqual "target" (Just "check") (gateTarget (gpGate plan))
                  , assertEqual "binary" "make" (gpBinary plan)
                  , assertEqual "args" ["check"] (gpArgs plan)
                  , assertEqual "cwd" (Just (gsProject gs)) (gpCwd plan)
                  ]

          , runTest "gate discovery: with no Makefile, the Everything module is the gate" $
              case entryGate of
                Left why   -> pure (Fail ("expected a gate: " <> T.unpack why))
                Right plan -> allOf
                  [ assertEqual "source" GateFromEverything (gateSource (gpGate plan))
                  , assertEqual "entry" (Just (gsEntry gs </> "Everything.agda"))
                      (gateEntry (gpGate plan))
                  , assertEqual "binary" (agdaBin agdaCfg) (gpBinary plan)
                  , assert ("args were " <> show (gpArgs plan))
                      (not (null (gpArgs plan))
                       && last (gpArgs plan) == gsEntry gs </> "Everything.agda")
                    -- The Everything gate keeps the server's working directory,
                    -- because the server's agda flags are relative to it.
                  , assertEqual "cwd" Nothing (gpCwd plan)
                  ]

          , runTest "gate discovery: a project with no gate is refused, showing its search" $
              case bareGate of
                Right plan -> pure (Fail ("expected no gate, got " <> show (gpGate plan)))
                Left why   ->
                  let want = ["no project gate found", T.pack (gsBare gs)
                             , "Everything.agda", "--check-command"]
                      missing = [w | w <- want, not (w `T.isInfixOf` why)]
                  in  assert ("missing from the message: " <> show missing) (null missing)

          , runTest "gate discovery: a configured command wins over discovery" $
              case cfgGate of
                Left why   -> pure (Fail ("expected a gate: " <> T.unpack why))
                Right plan -> allOf
                  [ assertEqual "source" GateFromServerConfig (gateSource (gpGate plan))
                  , assertEqual "binary" gate (gpBinary plan)
                  , assertEqual "args" ["pass"] (gpArgs plan)
                  ]

          , runTest "gate discovery: an explicit target outranks the configured command" $
              case cfgTarget of
                Left why   -> pure (Fail ("expected a gate: " <> T.unpack why))
                Right plan -> allOf
                  [ assertEqual "source" GateFromMakefile (gateSource (gpGate plan))
                  , assertEqual "target" (Just "other") (gateTarget (gpGate plan))
                  ]
          ]

        -- A gate that cannot be started at all: the other half of the -1
        -- convention, and the case whose only explanation is the output tail.
        unstartable <- handleCheckProject agdaCfg
                         (GateConfig (Just ["/nonexistent/no-such-gate"]) (Just 60))
                         (paramsAt (gsProject gs))
        crash <- sequence
          [ runTest "check_project: a gate that cannot be started is a failure, explained" $
              withRight unstartable $ \r -> allOf
                [ assert ("success was " <> show (cprSuccess r)) (not (cprSuccess r))
                , assertEqual "exitCode" (-1) (vExitCode (cprVerdict r))
                , assert "not a timeout" (not (cprTimedOut r))
                , assert "not a masked failure" (not (cprMaskedFailure r))
                , assert ("outputTail was " <> show (cprOutputTail r))
                    (maybe False (("failed to run /nonexistent/no-such-gate" `T.isInfixOf`))
                           (cprOutputTail r))
                ]
          ]

        -- Refusals that happen before anything is run.
        ghost <- handleCheckProject agdaCfg defaultGateConfig CheckProjectParams
          { cppTarget         = Nothing
          , cppProjectPath    = Just (gsProject gs </> "no-such-directory")
          , cppMaxDiagnostics = Nothing
          }
        noGate <- handleCheckProject agdaCfg defaultGateConfig (paramsAt (gsBare gs))
        refusals <- sequence
          [ runTest "check_project: a projectPath that does not exist is refused" $
              case ghost of
                Right r -> pure (Fail ("expected a refusal, got success=" <> show (cprSuccess r)))
                Left err ->
                  let msg = failureText err
                  in  assert ("message was " <> show msg)
                        ("projectPath does not exist" `T.isInfixOf` msg
                         && "no-such-directory" `T.isInfixOf` msg)

          , runTest "check_project: a project with no discoverable gate is refused, not reported green" $
              case noGate of
                Right r  -> pure (Fail ("expected a refusal, got success=" <> show (cprSuccess r)))
                Left err -> assert ("message was " <> show (failureText err))
                              ("no project gate found" `T.isInfixOf` failureText err)
          ]

        -- The real make path, end to end: discovery picks the fixture
        -- Makefile's check target, make runs the failing gate, and the report
        -- carries make's own exit code rather than the script's.
        mMake <- findExecutable "make"
        makeRun <- case mMake of
          Nothing -> do
            hPutStrLn stderr "  [skip] make not on PATH; skipping the discovered-make-gate test"
            pure []
          Just _  -> do
            res <- handleCheckProject agdaCfg defaultGateConfig (paramsAt (gsSub gs))
            sequence
              [ runTest "check_project: a discovered make gate runs, and reports make's own exit code" $
                  withRight res $ \r -> allOf
                    [ assert ("success was " <> show (cprSuccess r)) (not (cprSuccess r))
                    , assert ("exitCode was " <> show (vExitCode (cprVerdict r)))
                        (vExitCode (cprVerdict r) /= 0)
                    , assertEqual "source" GateFromMakefile (gateSource (cprGate r))
                    , assertEqual "target" (Just "check") (gateTarget (cprGate r))
                    , assertEqual "makefile" (Just (gsProject gs </> "Makefile"))
                        (gateMakefile (cprGate r))
                    , assertEqual "cwd" (gsProject gs) (ceCwd (cprCommand r))
                    , assertEqual "failingModule" (Just "Gate.Broken") (cprFailingModule r)
                    , assertEqual "firstError code" (Just "NotInScope")
                        (cprFirstError r >>= diagCode)
                    ]
              ]

        pure (failing <> passing <> masked <> timeoutFast <> timeoutOrphan
                <> discovery <> crash <> refusals <> makeRun)

      -- The wrong-checkout refusal, on the scene tier 1d already builds: a gate
      -- run in a worktree the registry does not name resolves its imports
      -- against the other tree, which is the same wrong answer issue #76
      -- refuses for a single file.
      mismatch <- withLibraryScene $ \ls -> do
        let rootCfg = defaultConfig
              { agdaBin   = "/nonexistent/agda-must-not-run"
              , agdaFlags = ["--library-file=" <> lsLibraries ls, "-l", "agda-algebras"]
              }
        res <- handleCheckProject rootCfg defaultGateConfig CheckProjectParams
          { cppTarget         = Nothing
          , cppProjectPath    = Just (lsRootB ls)
          , cppMaxDiagnostics = Nothing
          }
        sequence
          [ runTest "check_project: a project in another checkout of the same library is refused (#76)" $
              case res of
                Left (FailProject pm) -> allOf
                  [ assertEqual "fileRoot" (lsRootB ls) (pmFileRoot pm)
                  , assertEqual "registeredRoot" (lsRootA ls) (pmRegisteredRoot pm)
                  ]
                Left other -> pure (Fail ("expected FailProject, got: "
                                          <> T.unpack (failureText other)))
                Right r    -> pure (Fail ("expected a refusal, got success="
                                          <> show (cprSuccess r)))
          ]

      pure (pureRes <> sceneRes <> mismatch)

-- | contextFor: the project context of a fixture directory.  These fixtures
-- contain no @*.agda-lib@, so resolution cannot report a mismatch; a failure
-- here is a broken fixture rather than a test result.
contextFor :: AgdaConfig -> FilePath -> IO ProjectContext
contextFor cfg dir = do
  resolved <- resolveProjectDir cfg dir
  case resolved of
    Right pc -> pure pc
    Left pm  -> fail ("fixture resolved to a root mismatch: "
                        <> T.unpack (mismatchMessage pm))


-- ---------------------------------------------------------------------------
-- Tier 1g: the requested path — resolution and refusal (issue #101)
--
-- The field failure these tests exist to keep fixed.  An agent working in its
-- own project sent `check_file {"filePath": "src/…/Finite.lagda.md"}` — the
-- path form natural from a project directory — the server resolved it against
-- *its own* working directory, the file was not there, and the missing-file
-- IOException escaped the handler as a bare JSON-RPC `-32603 Internal error`.
-- The agent concluded the server had crashed and never called it again.
--
-- So: a relative path is still resolved against the server's working directory,
-- because that is the only directory the server knows, but the resolution is
-- now checked, and a miss is a structured refusal naming the path as resolved,
-- the directory it was resolved against, and the rule.  The scene below is that
-- shape exactly — a project outside the test process's working directory —
-- and it sits beside tier 1d's wrong-checkout refusal, which is the same
-- discipline one step later in the pipeline.
--
-- No Agda is involved: `agdaBin` names a binary that cannot be executed, so a
-- call that reaches Agda comes back as a Right carrying exit code -1, and a
-- Left is proof the refusal happened first.
-- ---------------------------------------------------------------------------

-- | ClientScene: a project the server is not standing in.
data ClientScene = ClientScene
  { csRoot     :: FilePath  -- ^ The client's project root.
  , csRelative :: FilePath  -- ^ The file, as the client would name it: relative to that root.
  , csFile     :: FilePath  -- ^ The same file, absolutely.
  , csMissing  :: FilePath  -- ^ An absolute path naming nothing.
  , csFifo     :: FilePath  -- ^ A named pipe: exists, is not a regular file.
  }

-- | withClientScene: build the scene under the temp directory, run an action on
-- it, and remove it.
--
--   <tmp>/agda-mcp-client-project/.git/                  (a repository boundary)
--   <tmp>/agda-mcp-client-project/src/Setoid/Algebras/Finite.agda
--
-- 'csRelative' is deliberately a path that also *looks* resolvable from the
-- test process's working directory (agda-mcp/ has a src/ of its own), which is
-- the whole hazard: a relative path is plausible in two trees at once and names
-- the caller's file in only one of them.
withClientScene :: (ClientScene -> IO a) -> IO a
withClientScene act = do
  tmp <- getTemporaryDirectory
  let root = tmp </> "agda-mcp-client-project"
      rel  = "src" </> "Setoid" </> "Algebras" </> "Finite.agda"
      cs   = ClientScene
        { csRoot     = root
        , csRelative = rel
        , csFile     = root </> rel
        , csMissing  = root </> "src" </> "NoSuchModule.agda"
        , csFifo     = root </> "src" </> "Pipe.agda"
        }
  bracket_ (build cs) (removeTree root) (act cs)
  where
    build cs = do
      removeTree (csRoot cs)
      createDirectoryIfMissing True (csRoot cs </> ".git")
      createDirectoryIfMissing True (takeDirectory (csFile cs))
      TIO.writeFile (csFile cs)
        "module Setoid.Algebras.Finite where\n\nopen import Agda.Builtin.Nat\n\nn : Nat\nn = {!!}\n"
      -- A FIFO with no writer reads as immediate EOF, so this fixture cannot
      -- hang the suite even if the file-type check regresses: the call would
      -- then reach Agda and come back a Right, which is what the test catches.
      createNamedPipe (csFifo cs) (ownerReadMode `unionFileModes` ownerWriteMode)

    removeTree d = removeDirectoryRecursive d `catch` \(_ :: SomeException) -> pure ()

-- | withPathFailure: the assertion shape tier 1g repeats — the call was refused,
-- and refused as a path failure rather than as anything else.
withPathFailure :: Either ToolFailure a -> (PathFailure -> IO TestResult) -> IO TestResult
withPathFailure (Left (FailPath pf)) k = k pf
withPathFailure (Left other) _ = pure . Fail $
  "expected a FailPath refusal, got: " <> T.unpack (failureText other)
withPathFailure (Right _) _ = pure (Fail "expected a refusal, got a result")

-- | propertyDoc: one input property's advertised description, read out of the
-- value @tools\/list@ serializes rather than out of the Haskell that builds it.
propertyDoc :: Text -> Text -> Aeson.Value -> Text
propertyDoc tool name v =
  case KM.lookup "properties" (inputSchemaOf tool v) of
    Just (Aeson.Object props) -> case KM.lookup (Key.fromText name) props of
      Just (Aeson.Object p) -> case KM.lookup "description" p of
        Just (Aeson.String d) -> d
        _                     -> ""
      _ -> ""
    _ -> ""

-- | The tools that take a file path.
filePathTools :: [Text]
filePathTools = ["get_goal", "fill_hole", "check_file", "get_diagnostics"]

pathTests :: IO [Bool]
pathTests = do
  hPutStrLn stderr "\n── Requested-path resolution and refusal (tier 1g: #101) ──"
  cwd <- getCurrentDirectory
  withClientScene $ \cs -> do
    let cfg = defaultConfig { agdaBin = "/nonexistent/agda-must-not-run" }
    -- The field-test call itself: the client's own relative path, sent to a
    -- server standing somewhere else.
    relMiss  <- handleCheckFile cfg (CheckFileParams (csRelative cs) Nothing)
    -- The two paths that must keep working: an absolute one, and a relative one
    -- that really is under the server's working directory (the in-repo client).
    absOk    <- handleCheckFile cfg (CheckFileParams (csFile cs) Nothing)
    relOk    <- handleCheckFile cfg (CheckFileParams timeoutFixturePath Nothing)
    -- The second defect: a path naming nothing, and the other three tools.
    absMiss  <- handleCheckFile cfg (CheckFileParams (csMissing cs) Nothing)
    diagMiss <- handleGetDiagnostics cfg (GetDiagnosticsParams (csMissing cs) Nothing)
    goalMiss <- handleGetGoal cfg GetGoalParams
      { ggFilePath = csMissing cs, ggHole = ByIndex 0 }
    fillMiss <- handleFillHole cfg FillHoleParams
      { fhFilePath = csMissing cs, fhHole = ByIndex 0, fhCandidate = "zero" }
    dirCall  <- handleCheckFile cfg (CheckFileParams (csRoot cs) Nothing)
    fifoCall <- handleCheckFile cfg (CheckFileParams (csFifo cs) Nothing)
    fifoProj <- handleCheckProject cfg defaultGateConfig CheckProjectParams
      { cppTarget = Nothing, cppProjectPath = Just (csFifo cs)
      , cppMaxDiagnostics = Nothing }
    projMiss <- handleCheckProject cfg defaultGateConfig CheckProjectParams
      { cppTarget = Nothing, cppProjectPath = Just (csRelative cs)
      , cppMaxDiagnostics = Nothing }

    core <- sequence
      [ runTest "path: a relative filePath from a mismatched cwd is refused, not resolved into the server's tree (#101)" $
          withPathFailure relMiss $ \pf -> allOf
            [ assertEqual "problem"   PathMissing        (pfProblem pf)
            , assert      "relative should be True"      (pfRelative pf)
            , assertEqual "requestedPath" (csRelative cs) (pfRequested pf)
            , assertEqual "resolvedPath"  (cwd </> csRelative cs) (pfResolved pf)
            , assertEqual "serverCwd"     cwd             (pfServerCwd pf)
            , assertEqual "parameter"     "filePath"      (pfParameter pf)
            ]

      , runTest "path: the refusal names the resolved path, the server's directory, and the rule" $
          -- An agent that can read only the error string must still learn
          -- enough to retry successfully on the very next call; that is the
          -- whole repair, since the -32603 this replaces taught nothing.
          withPathFailure relMiss $ \pf ->
            let msg  = pathFailureMessage pf
                want = [ T.pack (cwd </> csRelative cs), T.pack cwd
                       , T.pack (csRelative cs), "RELATIVE", "ABSOLUTE" ]
                missing = [w | w <- want, not (w `T.isInfixOf` msg)]
            in  assert ("missing from the message " <> show msg <> ": " <> show missing)
                  (null missing)

      , runTest "path: the refusal happens before agda is spawned" $
          -- agdaBin is a path that cannot be executed.  Had the call run it, the
          -- result would be a Right carrying exit code -1; a Left proves
          -- resolution short-circuited first.
          assert "expected a refusal rather than a failed agda run" (isLeft relMiss)

      , runTest "path: a relative filePath that IS under the server's directory still resolves" $
          -- The in-repo client, whose working directory really is the server's.
          -- Rejecting every relative path would have broken it for no safety
          -- gain: here cwd resolution is the right answer.
          withRight relOk $ \r ->
            let args = ceArgs (fcrCommand r)
            in  assert ("args were " <> show args)
                  (T.pack (cwd </> timeoutFixturePath) `elem` map T.pack args)

      , runTest "path: an absolute filePath is used exactly as sent" $
          withRight absOk $ \r ->
            let args = ceArgs (fcrCommand r)
            in  assert ("args were " <> show args) (csFile cs `elem` args)

      , runTest "path: a nonexistent absolute filePath is a structured failure, not an internal error" $
          withPathFailure absMiss $ \pf -> allOf
            [ assertEqual "problem"      PathMissing    (pfProblem pf)
            , assert      "relative should be False"    (not (pfRelative pf))
            , assertEqual "resolvedPath" (csMissing cs) (pfResolved pf)
            , assert ("message should name the path, was " <> show (pathFailureMessage pf))
                (T.pack (csMissing cs) `T.isInfixOf` pathFailureMessage pf)
            ]

      , runTest "path: get_goal, fill_hole, and get_diagnostics refuse the same way" $
          -- The read used to be unguarded in all four handlers, so all four are
          -- asserted: fixing one and leaving the others is exactly how this
          -- regressed the first time.
          allOf
            [ withPathFailure goalMiss $ \pf -> assertEqual "get_goal problem" PathMissing (pfProblem pf)
            , withPathFailure fillMiss $ \pf -> assertEqual "fill_hole problem" PathMissing (pfProblem pf)
            , withPathFailure diagMiss $ \pf -> assertEqual "get_diagnostics problem" PathMissing (pfProblem pf)
            ]

      , runTest "path: a directory passed as filePath is refused as a directory" $
          -- Something is there, so "does not exist" would send the caller
          -- looking for the wrong mistake.
          withPathFailure dirCall $ \pf -> allOf
            [ assertEqual "problem" PathNotAFile (pfProblem pf)
            , assert ("message was " <> show (pathFailureMessage pf))
                ("is a directory, not a file" `T.isInfixOf` pathFailureMessage pf)
            ]

      , runTest "path: a path naming a FIFO is refused unread, not opened (Copilot, PR 102)" $
          -- doesFileExist answers "exists and is not a directory", so it admits
          -- FIFOs, sockets, and devices.  Measured before the fix: a FIFO with a
          -- writer attached blocked BS.readFile forever — before --timeout has
          -- anything to bound, since that bounds the agda subprocess and this
          -- read happens first — and /dev/zero read until the heap was exhausted
          -- and the process died.  Neither is reportable: the server does not
          -- survive to answer.
          withPathFailure fifoCall $ \pf -> allOf
            [ assertEqual "problem" (PathNotRegular "a named pipe (FIFO)") (pfProblem pf)
            , assertEqual "resolvedPath" (csFifo cs) (pfResolved pf)
            , assert ("message was " <> show (pathFailureMessage pf))
                ("is not a regular file, it is a named pipe (FIFO)"
                   `T.isInfixOf` pathFailureMessage pf)
            , assert "the wire shape should name the file type"
                ("\"problem\":\"notRegularFile\"" `T.isInfixOf` encodeText pf)
            ]

      , runTest "path: check_project refuses a FIFO anchor rather than anchoring at its parent" $
          -- Nothing reads it there — only its parent directory is taken — but a
          -- gate run against the parent of a FIFO is a gate over a project the
          -- caller cannot have named.
          withPathFailure fifoProj $ \pf -> allOf
            [ assertEqual "parameter" "projectPath" (pfParameter pf)
            , assertEqual "problem" (PathNotRegular "a named pipe (FIFO)") (pfProblem pf)
            ]

      , runTest "path: check_project refuses a projectPath that does not exist, naming the rule" $
          withPathFailure projMiss $ \pf -> allOf
            [ assertEqual "parameter" "projectPath" (pfParameter pf)
            , assertEqual "problem"   PathMissing   (pfProblem pf)
            , assert      "relative should be True" (pfRelative pf)
            , assert ("message was " <> show (pathFailureMessage pf))
                (T.pack cwd `T.isInfixOf` pathFailureMessage pf)
            ]

      , runTest "path: the refusal's wire shape carries the path payload as data" $
          -- Asserted on the encoded JSON, because these key names are what a
          -- client reads instead of parsing the sentence.
          withPathFailure relMiss $ \pf ->
            let wire = encodeText pf
                want = [ "\"pathError\":", "\"parameter\":\"filePath\""
                       , "\"requestedPath\":", "\"resolvedPath\":"
                       , "\"relative\":true", "\"serverCwd\":"
                       , "\"problem\":\"missing\"", "\"error\":" ]
                missing = [k | k <- want, not (k `T.isInfixOf` wire)]
            in  assert ("missing from the wire shape: " <> show missing) (null missing)

      , runTest "path: a file that vanishes between the stat and the read is missing, not unreadable (Copilot, PR 102)" $
          -- The two sites that catch an IOException about a path are the stat and
          -- the open of that same path, and they must agree about the same errno.
          -- They did not: ENOENT from getFileStatus was PathMissing while ENOENT
          -- from BS.readFile was PathUnreadable, so a file deleted in the window
          -- between them came back as "could not be read / check the file's
          -- permissions" — false advice, since there is no file left to have
          -- permissions.  Asserted through the shared classifier rather than by
          -- racing the window, so the test is deterministic.
          let vanished = mkIOError doesNotExistErrorType "openBinaryFile"
                           Nothing (Just (csFile cs))
              refused  = mkIOError permissionErrorType "openBinaryFile"
                           Nothing (Just (csFile cs))
              rendered = pathFailureMessage PathFailure
                { pfParameter = "filePath", pfRequested = csFile cs
                , pfResolved  = csFile cs,  pfRelative  = False
                , pfServerCwd = cwd,        pfProblem   = ioProblem vanished }
          in  allOf
                [ assertEqual "a vanished file" PathMissing (ioProblem vanished)
                , assert ("a refused read was " <> show (ioProblem refused))
                    (case ioProblem refused of PathUnreadable _ -> True; _ -> False)
                , assert ("the refused read should carry the errno, was "
                          <> show (ioProblem refused))
                    (case ioProblem refused of
                       PathUnreadable why -> "permission" `T.isInfixOf` why
                       _                  -> False)
                , assert ("the message should not advise checking permissions: "
                          <> show rendered)
                    (not ("permissions" `T.isInfixOf` rendered))
                , assert ("the message should say the path is not there: "
                          <> show rendered)
                    ("does not exist" `T.isInfixOf` rendered)
                ]

      , runTest "response guard: a bottom inside a tool result surfaces in the guard, not in the writer (Copilot, PR 102)" $ do
          -- A handler can return successfully and hand back a Value whose thunks
          -- are unevaluated; encode in sendResponse forces them, outside every
          -- try in the server.  A bottom reachable from a tool result would then
          -- kill the loop rather than become a tool error — worse than the
          -- -32603 the guard exists to prevent, since the client sees the
          -- transport close instead of an answer.  forceResponse is what moves
          -- that moment inside the guarded region.
          outcome <- try (forceResponse
            (Aeson.object ["message" Aeson..= (error "kaboom" :: Text)]))
              :: IO (Either SomeException Aeson.Value)
          assert "expected the bottom to be raised by forceResponse" (isLeft outcome)

      , runTest "response guard: a well-formed tool result passes through unchanged" $ do
          let value = Aeson.object ["success" Aeson..= True, "holes" Aeson..= ([] :: [Int])]
          forced <- forceResponse value
          assertEqual "value" value forced

      , runTest "descriptions: every filePath property says whose working directory it resolves against (#101)" $
          -- The descriptions used to say "absolute or relative to cwd" without
          -- saying whose, and for any client outside this repository the honest
          -- answer was never the one meant.
          assertEqual "tools whose filePath description still fails to state the rule" []
            [ tool
            | tool <- filePathTools
            , let doc = propertyDoc tool "filePath" advertisedTools
            , not (   "working directory" `T.isInfixOf` doc
                   && "ABSOLUTE"          `T.isInfixOf` doc
                   && not ("relative to cwd" `T.isInfixOf` doc) )
            ]
      ]

    unreadable <- unreadableFileTest cfg cs
    pure (core <> unreadable)

-- | unreadableFileTest: a file that exists and cannot be opened.
--
-- The case existence checks cannot rule out, and the reason the read is guarded
-- rather than merely preceded by a 'doesFileExist': the client learns the path
-- and the syscall's own words instead of @-32603 Internal error@.
--
-- Skipped when the permission bits do not bite — running as root, or on a
-- filesystem that ignores them — rather than asserted and failed, since neither
-- says anything about this server.
unreadableFileTest :: AgdaConfig -> ClientScene -> IO [Bool]
unreadableFileTest cfg cs = do
  let locked = csRoot cs </> "src" </> "Locked.agda"
  TIO.writeFile locked "module Locked where\n"
  before <- getPermissions locked
  setPermissions locked emptyPermissions
  stillReadable <- either (const False) (const True)
    <$> (try (BS.readFile locked) :: IO (Either SomeException BS.ByteString))
  result <- if stillReadable then pure Nothing
            else Just <$> handleCheckFile cfg (CheckFileParams locked Nothing)
  setPermissions locked before
  removeFile locked
  case result of
    Nothing -> do
      hPutStrLn stderr "  [skip] the file is readable despite empty permissions (root?); \
                       \skipping the unreadable-file test"
      pure []
    Just res -> fmap (: []) . runTest
      "path: a file that exists but cannot be read is a structured failure naming the path" $
      withPathFailure res $ \pf -> allOf
        [ assert ("problem was " <> show (pfProblem pf))
            (case pfProblem pf of PathUnreadable _ -> True; _ -> False)
        , assertEqual "resolvedPath" locked (pfResolved pf)
        , assert ("message was " <> show (pathFailureMessage pf))
            ("was refused by the operating system" `T.isInfixOf` pathFailureMessage pf)
          -- The summary must not name a syscall or a cause: this same case is
          -- produced by the stat, where no read happens, and by errnos that
          -- have nothing to do with permissions (Copilot's fourth review).
        , assert ("message should not assert a cause: " <> show (pathFailureMessage pf))
            (not ("check the file's permissions" `T.isInfixOf` pathFailureMessage pf))
        , assert "the wire shape should carry the underlying detail"
            ("\"detail\":" `T.isInfixOf` encodeText pf)
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
        let params = GetGoalParams { ggFilePath = fixturePath, ggHole = ByIndex 0 }
        result <- handleGetGoal cfg params
        case result of
          Left err -> pure (Fail $ "get_goal failed: " <> T.unpack (failureText err))
          Right info -> assertEqual "goal" "A" (giGoal info)

    , runTest "get_goal: Fixture01 hole 1 goal is exactly \"⊤\" (#70)" $ do
        let params = GetGoalParams { ggFilePath = fixturePath, ggHole = ByIndex 1 }
        result <- handleGetGoal cfg params
        case result of
          Left err -> pure (Fail $ "get_goal failed: " <> T.unpack (failureText err))
          Right info -> assertEqual "goal" "⊤" (giGoal info)

    , runTest "get_goal: Fixture01 hole 2 goal is exactly \"x ≡ x\" (#70)" $ do
        let params = GetGoalParams { ggFilePath = fixturePath, ggHole = ByIndex 2 }
        result <- handleGetGoal cfg params
        case result of
          Left err -> pure (Fail $ "get_goal failed: " <> T.unpack (failureText err))
          Right info -> assertEqual "goal" "x ≡ x" (giGoal info)

    , runTest "get_goal: Fixture01 hole 0 context contains 'x : A'" $ do
        let params = GetGoalParams { ggFilePath = fixturePath, ggHole = ByIndex 0 }
        result <- handleGetGoal cfg params
        case result of
          Left err -> pure (Fail $ "get_goal failed: " <> T.unpack (failureText err))
          Right info ->
            let names = map ctxName (giContext info)
            in  assert "'x' should be in context" ("x" `elem` names)

    , runTest "fill_hole: Fixture01 hole 0 with 'x' succeeds" $ do
        let params = FillHoleParams
              { fhFilePath  = fixturePath
              , fhHole      = ByIndex 0
              , fhCandidate = "x"
              }
        result <- handleFillHole cfg params
        case result of
          Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
          Right fr -> assertEqual "status" FillOk (frStatus fr)

    , runTest "fill_hole: Fixture01 hole 0 with 'tt' fails (type error)" $ do
        let params = FillHoleParams
              { fhFilePath  = fixturePath
              , fhHole      = ByIndex 0
              , fhCandidate = "tt"
              }
        result <- handleFillHole cfg params
        case result of
          Left err -> pure (Fail $ "fill_hole failed unexpectedly: " <> T.unpack (failureText err))
          Right fr -> assertEqual "status" FillTypeError (frStatus fr)

    , runTest "check_file: Fixture01 reports holes" $ do
        let params = CheckFileParams
              { cfFilePath = fixturePath, cfMaxDiagnostics = Nothing }
        result <- handleCheckFile cfg params
        case result of
          Left err -> pure (Fail $ "check_file failed: " <> T.unpack (failureText err))
          Right fcr ->
            assert "should report at least 1 hole" (fcrHolesCount fcr > 0)

      -- The fast path against a *real* Agda (issue #77): a check that completes
      -- must not be flagged as a timeout, and must carry a plausible duration.
      -- The tier-1c tests pin the same invariants against the fake binary; this
      -- one pins that the real subprocess is measured the same way.
    , runTest "check_file: a real check is not a timeout and carries elapsedMs" $ do
        let params = CheckFileParams
              { cfFilePath = fixturePath, cfMaxDiagnostics = Nothing }
        result <- handleCheckFile cfg params
        case result of
          Left err -> pure (Fail $ "check_file failed: " <> T.unpack (failureText err))
          Right fcr -> do
            r1 <- assert "timedOut should be False" (not (fcrTimedOut fcr))
            case r1 of
              Fail m -> pure (Fail m)
              Pass   -> assert ("elapsedMs = " <> show (fcrElapsedMs fcr))
                          (fcrElapsedMs fcr > 0)

    , runTest "get_goal: a real goal query carries elapsedMs" $ do
        let params = GetGoalParams { ggFilePath = fixturePath, ggHole = ByIndex 0 }
        result <- handleGetGoal cfg params
        case result of
          Left err   -> pure (Fail $ "get_goal failed: " <> T.unpack (failureText err))
          Right info -> assert ("elapsedMs = " <> show (giElapsedMs info))
                          (maybe False (> 0) (giElapsedMs info))

    , runTest "fill_hole: a real fill carries elapsedMs and is not a timeout" $ do
        let params = FillHoleParams
              { fhFilePath = fixturePath, fhHole = ByIndex 0, fhCandidate = "x" }
        result <- handleFillHole cfg params
        case result of
          Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
          Right fr -> do
            r1 <- assert "status should not be timeout" (frStatus fr /= FillTimeout)
            case r1 of
              Fail m -> pure (Fail m)
              Pass   -> assert ("elapsedMs = " <> show (frElapsedMs fr))
                          (frElapsedMs fr > 0)

    , runTest "get_diagnostics: Fixture01 reports holes" $ do
        let params = GetDiagnosticsParams
              { gdFilePath = fixturePath, gdMaxDiagnostics = Nothing }
        result <- handleGetDiagnostics cfg params
        case result of
          Left err -> pure (Fail $ "get_diagnostics failed: " <> T.unpack (failureText err))
          Right dr ->
            assert "should report at least 1 hole" (not . null $ drHoles dr)
    ]
  hier <- hierIntegrationTests cfg repoRoot
  verdict <- fillVerdictTests cfg
  holes <- holeModelIntegrationTests cfg
  diags <- diagnosticIntegrationTests cfg
  handles <- holeAddressingIntegrationTests cfg
  pure (base <> hier <> verdict <> holes <> diags <> handles)


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
            let params = GetGoalParams { ggFilePath = useFile, ggHole = ByIndex 0 }
            result <- handleGetGoal hierCfg params
            case result of
              Left err   -> pure (Fail $ "get_goal failed: " <> T.unpack (failureText err))
              Right info -> assert "goal should be non-empty" (not . T.null $ giGoal info)

        , runTest "get_goal: Proofs.Use reports its declared (hierarchical) module name" $ do
            let params = GetGoalParams { ggFilePath = useFile, ggHole = ByIndex 0 }
            result <- handleGetGoal hierCfg params
            case result of
              Left err   -> pure (Fail $ "get_goal failed: " <> T.unpack (failureText err))
              Right info -> assertEqual "module" (Just "Proofs.Use") (giModule info)

        , runTest "get_goal: Proofs.Use context contains 'x' (Debug import injected)" $ do
            let params = GetGoalParams { ggFilePath = useFile, ggHole = ByIndex 0 }
            result <- handleGetGoal hierCfg params
            case result of
              Left err   -> pure (Fail $ "get_goal failed: " <> T.unpack (failureText err))
              Right info ->
                assert "'x' should be in context"
                  ("x" `elem` map ctxName (giContext info))

        , runTest "fill_hole: Proofs.Use with cross-directory 'thing' succeeds" $ do
            let params = FillHoleParams
                  { fhFilePath = useFile, fhHole = ByIndex 0, fhCandidate = "thing" }
            result <- handleFillHole hierCfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
              Right fr -> assertEqual "status" FillOk (frStatus fr)

        , runTest "fill_hole: Proofs.Use with ill-typed 'tt' is a type error" $ do
            let params = FillHoleParams
                  { fhFilePath = useFile, fhHole = ByIndex 0, fhCandidate = "tt" }
            result <- handleFillHole hierCfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed unexpectedly: " <> T.unpack (failureText err))
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
                  { fhFilePath = fixture, fhHole = ByIndex 0, fhCandidate = "implicitOnly" }
            result <- handleFillHole cfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed unexpectedly: " <> T.unpack (failureText err))
              Right fr -> do
                r1 <- assertEqual "status" FillTypeError (frStatus fr)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assert "message should name the unsolved metas"
                    (maybe False ("UnsolvedMetaVariables" `T.isInfixOf`) (frMessage fr))

        , runTest "fill_hole: well-typed candidate with another hole open stays ok" $ do
            let params = FillHoleParams
                  { fhFilePath = fixture, fhHole = ByIndex 0, fhCandidate = "zero" }
            result <- handleFillHole cfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
              Right fr -> assertEqual "status" FillOk (frStatus fr)

        , runTest "fill_hole: candidate introducing a new sub-hole stays ok" $ do
            let params = FillHoleParams
                  { fhFilePath = fixture, fhHole = ByIndex 0, fhCandidate = "suc {!!}" }
            result <- handleFillHole cfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
              Right fr -> assertEqual "status" FillOk (frStatus fr)

        -- Since issue #71, tracking matches tolerance: a `?` sub-hole the
        -- candidate introduces is both excused by the verdict and counted by
        -- remainingHoles — here hole h plus the new `?`.
        , runTest "fill_hole: a '?' sub-hole is tolerated AND counted (#71)" $ do
            let params = FillHoleParams
                  { fhFilePath = fixture, fhHole = ByIndex 0, fhCandidate = "suc ?" }
            result <- handleFillHole cfg params
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
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
              { ggFilePath = variants, ggHole = ByIndex 3 }
            case result of
              Left err   -> pure (Fail $ "get_goal failed: " <> T.unpack (failureText err))
              Right info -> assertEqual "goal" "Nat" (giGoal info)

        , runTest "fill_hole: comment decoys do not shift hole indices (#71)" $ do
            -- Hole 0 (a = {!!}) is preceded by comment/string decoy tokens;
            -- remainingHoles == 3 proves the fill hit the real hole, not a
            -- decoy (writing into a comment would leave all 4 holes open).
            result <- handleFillHole cfg FillHoleParams
              { fhFilePath = variants, fhHole = ByIndex 0, fhCandidate = "zero" }
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
              Right fr -> do
                r1 <- assertEqual "status" FillOk (frStatus fr)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assertEqual "remainingHoles" (Just 3) (frRemainingHoles fr)

        , runTest "fill_hole: a standalone ? hole is addressable and fillable" $ do
            result <- handleFillHole cfg FillHoleParams
              { fhFilePath = variants, fhHole = ByIndex 3, fhCandidate = "zero" }
            case result of
              Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
              Right fr -> do
                r1 <- assertEqual "status" FillOk (frStatus fr)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assertEqual "remainingHoles" (Just 3) (frRemainingHoles fr)

        , runTest "get_goal: {! zero !} in a .lagda.md ≡ the same code in a .agda" $ do
            mdGoal    <- handleGetGoal cfg GetGoalParams
              { ggFilePath = lagdaMd, ggHole = ByIndex 0 }
            plainGoal <- handleGetGoal cfg GetGoalParams
              { ggFilePath = plainTwin, ggHole = ByIndex 0 }
            case (mdGoal, plainGoal) of
              (Right md, Right plain) -> do
                r1 <- assertEqual "goals agree" (giGoal plain) (giGoal md)
                case r1 of
                  Fail m -> pure (Fail m)
                  Pass   -> assertEqual "goal" "Nat" (giGoal md)
              (Left err, _) -> pure (Fail $ "get_goal (.lagda.md) failed: " <> T.unpack (failureText err))
              (_, Left err) -> pure (Fail $ "get_goal (.agda) failed: " <> T.unpack (failureText err))

        , runTest "fill_hole: {! zero !} in a .lagda.md fills like in a .agda" $ do
            mdFill    <- handleFillHole cfg FillHoleParams
              { fhFilePath = lagdaMd, fhHole = ByIndex 0, fhCandidate = "zero" }
            plainFill <- handleFillHole cfg FillHoleParams
              { fhFilePath = plainTwin, fhHole = ByIndex 0, fhCandidate = "zero" }
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
              (Left err, _) -> pure (Fail $ "fill_hole (.lagda.md) failed: " <> T.unpack (failureText err))
              (_, Left err) -> pure (Fail $ "fill_hole (.agda) failed: " <> T.unpack (failureText err))

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
                              { ggFilePath = f, ggHole = ByIndex 0 }) files
            let bad = [ (takeFileName f, r)
                      | (f, r) <- zip files results
                      , either (const True) ((/= "Nat") . giGoal) r
                      ]
            assert ("failures: " <> show (map fst bad)) (null bad)

        , runTest "fill_hole: prose {!!} decoys are not addressable (#73)" $ do
            -- LiterateMd has exactly one real hole; its prose decoys must
            -- not create an index 1.
            result <- handleFillHole cfg FillHoleParams
              { fhFilePath = lagdaMd, fhHole = ByIndex 1, fhCandidate = "zero" }
            case result of
              Left err -> assert "error names the missing index"
                            ("Hole index 1" `T.isInfixOf` failureText err)
              Right _  -> pure (Fail "expected Left for a prose decoy index")

        , runTest "get_diagnostics: .lagda.md hole position is in literate coordinates" $ do
            src <- TIO.readFile lagdaMd
            result <- handleGetDiagnostics cfg GetDiagnosticsParams
              { gdFilePath = lagdaMd, gdMaxDiagnostics = Nothing }
            case (result, expectedHolePos src) of
              (Left err, _)  -> pure (Fail $ "get_diagnostics failed: " <> T.unpack (failureText err))
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
-- Tier 2e: Structured diagnostics against real Agda (issue #74)
--
-- One fixture per error class of the feedback document's § 5 corpus, each
-- asserting the three things a client needs and could not get before: the
-- machine-readable `code`, the `range` — which no diagnostic carried at all
-- under Agda 2.8.0, the bug this issue opens with — and the `involved` payload
-- that § 5's third column names for that class.
--
-- Every expected position is computed from the fixture's own text rather than
-- written down, so editing a fixture's header comment cannot silently turn a
-- position assertion into a lie.
-- ---------------------------------------------------------------------------

-- | Where the § 5 fixtures live (relative to agda-mcp/, as cabal test runs).
diagnosticFixtureDir :: FilePath
diagnosticFixtureDir = "test" </> "resources" </> "diagnostics"

-- | posOfNth: the 1-based (line, col) of the k-th (0-based) occurrence of
-- @needle@ — the coordinates Agda prints for a token at that spot.
posOfNth :: Int -> Text -> Text -> Maybe (Int, Int)
posOfNth k src needle = go k 0
  where
    go n from = case T.breakOn needle (T.drop from src) of
      (_, r) | T.null r -> Nothing
      (pre, _)
        | n <= 0    -> Just (posAt (from + T.length pre))
        | otherwise -> go (n - 1) (from + T.length pre + T.length needle)
    posAt i =
      let before = T.take i src
      in  (T.count "\n" before + 1, T.length (T.takeWhileEnd (/= '\n') before) + 1)

-- | rangeOfNth: the range Agda reports for that occurrence — starting at its
-- first character and ending one past its last, which is how Agda spells spans.
rangeOfNth :: Int -> Text -> Text -> Maybe DiagRange
rangeOfNth k src needle = do
  (ln, col) <- posOfNth k src needle
  pure (DiagRange ln col ln (col + T.length needle))

-- | showAgdaRange: a same-line range in Agda's own @LINE.COL-COL@ spelling, for
-- the assertions that compare against a location Agda printed inside a message.
showAgdaRange :: DiagRange -> Text
showAgdaRange r = T.pack $
  show (rngStartLine r) <> "." <> show (rngStartCol r) <> "-" <> show (rngEndCol r)

-- | withFixtureDiagnostics: check one § 5 fixture with a real Agda, and hand the
-- assertion the fixture's text alongside the diagnostics @check_file@ returned.
withFixtureDiagnostics
  :: AgdaConfig -> String -> FilePath
  -> (Text -> [Diagnostic] -> IO TestResult) -> IO Bool
withFixtureDiagnostics cfg name file k = runTest name $ do
  let path = diagnosticFixtureDir </> file
  src    <- TIO.readFile path
  result <- handleCheckFile cfg
    CheckFileParams { cfFilePath = path, cfMaxDiagnostics = Nothing }
  case result of
    Left err  -> pure (Fail $ "check_file failed: " <> T.unpack (failureText err))
    Right fcr -> k src (fcrDiagnostics fcr)

-- | needCode: the diagnostic with this code, or a failure naming what did come
-- back — which is the message you want when Agda's wording has moved.
needCode :: Text -> [Diagnostic] -> (Diagnostic -> IO TestResult) -> IO TestResult
needCode c ds k = case byCode c ds of
  Just d  -> k d
  Nothing -> pure . Fail $
    "no [" <> T.unpack c <> "] diagnostic; got " <> show (codesOf ds)

diagnosticIntegrationTests :: AgdaConfig -> IO [Bool]
diagnosticIntegrationTests cfg = do
  present <- doesFileExist (diagnosticFixtureDir </> "UnequalTerms.agda")
  if not present
    then do
      hPutStrLn stderr $ "\n  [skip] diagnostic fixtures not found in "
        <> diagnosticFixtureDir
      pure []
    else do
      hPutStrLn stderr
        "\n── Integration tests (tier 2e: structured diagnostics, #74) ──"
      sequence
        [ withFixtureDiagnostics cfg
            "diagnostics: ModuleDoesntExport (warning) precedes its NotInScope"
            "ModuleDoesntExport.agda" $ \src ds ->
              allOf
                [ -- Root cause first: the warning that says the name will not
                  -- resolve, then the error that it did not.
                  assertEqual "codes, root cause first"
                    [Just "ModuleDoesntExport", Just "NotInScope"] (codesOf ds)
                , needCode "ModuleDoesntExport" ds $ \d -> allOf
                    [ assertEqual "severity" DiagWarning (diagSeverity d)
                    , assertEqual "range" (rangeOfNth 0 src "using (usable; absentName)")
                        (diagRange d)
                    , assertEqual "involved.candidates" ["absentName"]
                        (invCandidates (diagInvolved d))
                    ]
                , needCode "NotInScope" ds $ \d -> allOf
                    [ assertEqual "severity" DiagError (diagSeverity d)
                      -- The second occurrence: the use site, not the import.
                    , assertEqual "range" (rangeOfNth 1 src "absentName") (diagRange d)
                    ]
                ]

        , withFixtureDiagnostics cfg
            "diagnostics: NotInScope carries range and 'did you mean' candidates"
            "NotInScope.agda" $ \src ds ->
              needCode "NotInScope" ds $ \d -> allOf
                [ assertEqual "range" (rangeOfNth 0 src "zeroo") (diagRange d)
                , assertEqual "involved.candidates"
                    [ "Agda.Builtin.Nat.Nat.zero", "Agda.Builtin.Nat.zero"
                    , "Nat.zero", "zero" ]
                    (invCandidates (diagInvolved d))
                  -- The body, not just the header line, is what makes the
                  -- message worth reading.
                , assert ("message was " <> show (diagMessage d))
                    ("Not in scope" `T.isInfixOf` diagMessage d)
                ]

        , withFixtureDiagnostics cfg
            "diagnostics: AmbiguousName carries the qualified candidates"
            "AmbiguousName.agda" $ \src ds ->
              needCode "AmbiguousName" ds $ \d -> allOf
                [ assertEqual "range" (rangeOfNth 0 src "shared") (diagRange d)
                , assertEqual "involved.candidates"
                    ["DiagAmbigA.shared", "DiagAmbigB.shared"]
                    (invCandidates (diagInvolved d))
                ]

        , withFixtureDiagnostics cfg
            "diagnostics: ClashingDefinition carries the previous definition"
            "ClashingDefinition.agda" $ \src ds ->
              needCode "ClashingDefinition" ds $ \d ->
                -- The clash is the second `least`; its origin is the first, the
                -- record field re-exported into this scope.
                case (rangeOfNth 1 src "least", rangeOfNth 0 src "least") of
                  (Just clash, Just origin) -> allOf
                    [ assertEqual "range" (Just clash) (diagRange d)
                    , assert ("involved.candidates were "
                               <> show (invCandidates (diagInvolved d)))
                        (any ((("ClashingDefinition.agda:" <> showAgdaRange origin)
                                `T.isSuffixOf`))
                             (invCandidates (diagInvolved d)))
                    ]
                  _ -> pure (Fail "fixture no longer contains two `least` tokens")

        , withFixtureDiagnostics cfg
            "diagnostics: UnequalTerms carries actual, expected, and the range"
            "UnequalTerms.agda" $ \src ds ->
              needCode "UnequalTerms" ds $ \d -> allOf
                [ assertEqual "range" (rangeOfNth 0 src "true") (diagRange d)
                , assertEqual "involved.actual"   (Just "Bool")
                    (invActual (diagInvolved d))
                , assertEqual "involved.expected" (Just "Nat")
                    (invExpected (diagInvolved d))
                ]

        , withFixtureDiagnostics cfg
            "diagnostics: UnsolvedConstraints + UnsolvedMetaVariables"
            "UnsolvedMetas.agda" $ \src ds ->
              allOf
                [ assertEqual "codes, in Agda's order"
                    [Just "UnsolvedConstraints", Just "UnsolvedMetaVariables"]
                    (codesOf ds)
                , needCode "UnsolvedConstraints" ds $ \d -> allOf
                    [ -- This one has no position at all: the header starts the
                      -- line, and a parser keyed on ": error:" never saw it.
                      assertEqual "range" Nothing (diagRange d)
                    , assert ("metaTypes were " <> show (invMetaTypes (diagInvolved d)))
                        (case invMetaTypes (diagInvolved d) of
                           [c] -> "blocked on" `T.isInfixOf` c
                           _   -> False)
                    ]
                , needCode "UnsolvedMetaVariables" ds $ \d -> allOf
                    [ assertEqual "range" (rangeOfNth 1 src "blocked") (diagRange d)
                    , assertEqual "metaTypes" 1
                        (length (invMetaTypes (diagInvolved d)))
                    ]
                ]

          -- The cap and the total, against a live check: one diagnostic kept out
          -- of two, and the one kept is the root cause rather than the first
          -- thing Agda happened to print.
        , runTest "diagnostics: maxDiagnostics caps the list and reports the total" $ do
            let path = diagnosticFixtureDir </> "ModuleDoesntExport.agda"
            result <- handleCheckFile cfg
              CheckFileParams { cfFilePath = path, cfMaxDiagnostics = Just 1 }
            case result of
              Left err  -> pure (Fail $ "check_file failed: " <> T.unpack (failureText err))
              Right fcr -> allOf
                [ assertEqual "diagnostics" [Just "ModuleDoesntExport"]
                    (codesOf (fcrDiagnostics fcr))
                , assertEqual "diagnosticsTotal" 2 (fcrDiagnosticsTotal fcr)
                ]

          -- get_diagnostics counts every diagnostic, not just the kept ones:
          -- a capped payload must never read as a cleaner file.
        , runTest "get_diagnostics: counts are over all diagnostics, not the capped list" $ do
            let path = diagnosticFixtureDir </> "ModuleDoesntExport.agda"
            result <- handleGetDiagnostics cfg
              GetDiagnosticsParams { gdFilePath = path, gdMaxDiagnostics = Just 1 }
            case result of
              Left err -> pure (Fail $ "get_diagnostics failed: " <> T.unpack (failureText err))
              Right dr -> allOf
                [ assertEqual "errors"           1 (drErrors dr)
                , assertEqual "warnings"         1 (drWarnings dr)
                , assertEqual "diagnostics kept" 1 (length (drDiagnostics dr))
                , assertEqual "diagnosticsTotal" 2 (drDiagnosticsTotal dr)
                , assert "success should be False" (not (drSuccess dr))
                ]
        ]


-- ---------------------------------------------------------------------------
-- Tier 2f: stable hole handles against real Agda (issue #79)
--
-- The acceptance criterion, run twice: a two-hole file stays addressable by
-- position after its first hole is filled, with no index bookkeeping in the
-- client — once on a plain .agda and once on its .lagda.md twin, where the
-- coordinates are literate-file coordinates and every prose decoy is a chance
-- to get them wrong.
--
-- What makes this a test rather than a demonstration is the pair of assertions
-- at the end: the position that named the second hole before the fill still
-- names it after, and the *index* that named it before now names nothing.  One
-- of those two handles survived the edit; the other is the bookkeeping § 3.8 of
-- the feedback document describes an agent losing.
-- ---------------------------------------------------------------------------

holeAddressingIntegrationTests :: AgdaConfig -> IO [Bool]
holeAddressingIntegrationTests cfg = do
  let resources = "test" </> "resources"
      twoHoles  = resources </> "TwoHoles.agda"
      twoHolesL = resources </> "TwoHolesLiterate.lagda.md"
      lagdaMd   = resources </> "LiterateMd.lagda.md"
      plainTwin = resources </> "HolePlain.agda"
      fixtures  = [twoHoles, twoHolesL, lagdaMd, plainTwin]
  exists <- mapM doesFileExist fixtures
  if not (and exists)
    then do
      hPutStrLn stderr "\n  [skip] hole-addressing fixtures not found"
      pure []
    else do
      hPutStrLn stderr
        "\n── Integration tests (tier 2f: stable hole handles, #79) ──"
      before   <- mapM BS.readFile fixtures
      reanchor <- mapM (reanchorTest cfg) [twoHoles, twoHolesL]
      parity   <- sequence
        [ runTest "by position: a .lagda.md and its .agda twin answer alike (#79)" $ do
            mdSrc    <- TIO.readFile lagdaMd
            plainSrc <- TIO.readFile plainTwin
            case (findHoles (flavourOf lagdaMd) mdSrc, findHoles (flavourOf plainTwin) plainSrc) of
              ([mh], [ph]) -> do
                -- Each file is addressed in its OWN coordinates — the hole sits
                -- on a different line in each — which is the whole point: the
                -- client reads the position out of that file's hole listing and
                -- hands it back, and never learns which flavour it is talking to.
                let mdRef    = ByPosition (hsLine mh) (hsCol mh)
                    plainRef = ByPosition (hsLine ph) (hsCol ph)
                mdGoal    <- handleGetGoal cfg GetGoalParams
                  { ggFilePath = lagdaMd,   ggHole = mdRef }
                plainGoal <- handleGetGoal cfg GetGoalParams
                  { ggFilePath = plainTwin, ggHole = plainRef }
                mdFill    <- handleFillHole cfg FillHoleParams
                  { fhFilePath = lagdaMd,   fhHole = mdRef,    fhCandidate = "zero" }
                plainFill <- handleFillHole cfg FillHoleParams
                  { fhFilePath = plainTwin, fhHole = plainRef, fhCandidate = "zero" }
                case (mdGoal, plainGoal, mdFill, plainFill) of
                  (Right mg, Right pg, Right mf, Right pf) -> allOf
                    [ assert "the twins' holes sit on different lines"
                        (hsLine mh /= hsLine ph)
                    , assertEqual "goals agree"       (giGoal pg)   (giGoal mg)
                    , assertEqual "goal"              "Nat"         (giGoal mg)
                    , assertEqual "fill statuses agree" (frStatus pf) (frStatus mf)
                    , assertEqual "fill status"       FillOk        (frStatus mf)
                    , assertEqual "re-anchored hole lists agree" (frHoles pf) (frHoles mf)
                    , assertEqual "the candidate closed the last hole" [] (frHoles mf)
                    ]
                  (Left e, _, _, _) -> pure (Fail $ "get_goal (.lagda.md): "  <> T.unpack (failureText e))
                  (_, Left e, _, _) -> pure (Fail $ "get_goal (.agda): "      <> T.unpack (failureText e))
                  (_, _, Left e, _) -> pure (Fail $ "fill_hole (.lagda.md): " <> T.unpack (failureText e))
                  (_, _, _, Left e) -> pure (Fail $ "fill_hole (.agda): "     <> T.unpack (failureText e))
              (ms, ps) -> pure . Fail $
                "expected 1 hole in each twin, got " <> show (length ms)
                <> " and " <> show (length ps)

        -- The limit of a position, pinned rather than papered over.  The
        -- re-anchoring tests above fill with a same-length candidate on another
        -- line, where the surviving hole does not move; a candidate that spans
        -- two lines moves it, and the contract is that the response says so
        -- (a Copilot review catch on PR #99 — the claim used to be that a
        -- position survives any fill elsewhere, which is false).
        , runTest "fill_hole: a multiline candidate moves later holes, and holes says where (#79)" $ do
            src <- TIO.readFile twoHoles
            let flav      = flavourOf twoHoles
                candidate = "suc\n      zero"   -- one line becomes two
            case (findHoles flav src, substituteHole flav 0 candidate src) of
              ([h0, h1], Just patched) -> do
                result <- handleFillHole cfg FillHoleParams
                  { fhFilePath  = twoHoles
                  , fhHole      = ByPosition (hsLine h0) (hsCol h0)
                  , fhCandidate = candidate
                  }
                case result of
                  Left err -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
                  Right fr -> allOf
                    [ assertEqual "status" FillOk (frStatus fr)
                    , assertEqual "the response re-anchors the survivor one line lower"
                        [(0, hsLine h1 + 1, hsCol h1)]
                        [ (hiIndex h, hiLine h, hiCol h) | h <- frHoles fr ]
                    -- And the coordinates held from before the fill are now
                    -- wrong in the way that matters: they name no hole, so a
                    -- client reusing them gets the loud miss, never another hole.
                    , assert "the pre-fill position no longer names a hole"
                        (isLeft (resolveHoleRef twoHoles flav patched
                                   (ByPosition (hsLine h1) (hsCol h1))))
                    , assertEqual "the re-anchored position does" (Right 0)
                        (resolveHoleRef twoHoles flav patched
                           (ByPosition (hsLine h1 + 1) (hsCol h1)))
                    ]
              (hs, _) -> pure . Fail $ "expected exactly 2 holes, got " <> show (length hs)

        -- The miss reaches the tool boundary intact.  Resolution happens before
        -- Agda is started, so this costs no subprocess; it is here to pin that
        -- the message a client sees is the one the resolver wrote.
        , runTest "get_goal: a prose position is a loud miss, not a nearby hole (#79)" $ do
            mdSrc  <- TIO.readFile lagdaMd
            result <- handleGetGoal cfg GetGoalParams
              { ggFilePath = lagdaMd
              , ggHole     = ByPosition (proseDecoyLine mdSrc) (proseDecoyCol mdSrc)
              }
            case (result, findHoles LiterateMd mdSrc) of
              (Right _, _)  -> pure (Fail "a prose decoy position should address no hole")
              (Left err, holes) -> let msg = failureText err in allOf
                [ assert "says no hole is there" ("No hole at line" `T.isInfixOf` msg)
                , assert "names the real hole instead of resolving to it"
                    (all (\h -> ("line " <> T.pack (show (hsLine h)) <> ", column "
                                  <> T.pack (show (hsCol h))) `T.isInfixOf` msg) holes)
                ]
        ]
      after    <- mapM BS.readFile fixtures
      restored <- runTest "hole-addressing tests restore their fixtures byte-exactly" $
        assert "files unchanged" (before == after)
      pure (reanchor <> parity <> [restored])

-- | reanchorTest: one fixture through the whole re-anchoring loop.
--
-- Fill the first hole by position; check the response's own hole list already
-- names the second hole's position (and its new index); then write the
-- candidate back, as a client keeping it would, and address that second hole by
-- the coordinates read BEFORE the fill.  The fixture is restored either way.
reanchorTest :: AgdaConfig -> FilePath -> IO Bool
reanchorTest cfg path =
  runTest ("re-anchoring after a fill: " <> takeFileName path) $ do
    orig <- BS.readFile path
    src  <- TIO.readFile path
    let flav = flavourOf path
    case findHoles flav src of
      [h0, h1] -> do
        let p0 = ByPosition (hsLine h0) (hsCol h0)
            p1 = ByPosition (hsLine h1) (hsCol h1)
        fill <- handleFillHole cfg FillHoleParams
          { fhFilePath = path, fhHole = p0, fhCandidate = "zero" }
        case (fill, substituteHole flav 0 "zero" src) of
          (Left err, _) -> pure (Fail $ "fill_hole failed: " <> T.unpack (failureText err))
          (_, Nothing)  -> pure (Fail "substituteHole returned Nothing for hole 0")
          (Right fr, Just patchedSrc) -> do
            anchored <- allOf
              [ assertEqual "status" FillOk (frStatus fr)
              -- The re-anchoring payload: one hole left, still where it was,
              -- and renumbered — the shift, reported rather than left to guess.
              , assertEqual "the response's re-anchored hole list"
                  [(0, hsLine h1, hsCol h1)]
                  [ (hiIndex h, hiLine h, hiCol h) | h <- frHoles fr ]
              , assertEqual "remainingHoles is that list's length"
                  (Just (length (frHoles fr))) (frRemainingHoles fr)
              ]
            case anchored of
              Fail m -> pure (Fail m)
              Pass   ->
                -- Keep the candidate, the way a client would after an ok, and
                -- ask about the other hole with the handle held all along.
                bracket_ (BS.writeFile path (TE.encodeUtf8 patchedSrc))
                         (BS.writeFile path orig) $ do
                  goal  <- handleGetGoal cfg GetGoalParams
                    { ggFilePath = path, ggHole = p1 }
                  stale <- handleGetGoal cfg GetGoalParams
                    { ggFilePath = path, ggHole = ByIndex 1 }
                  allOf
                    [ case goal of
                        Right info -> assertEqual "goal at the unmoved position" "Nat" (giGoal info)
                        Left err    -> pure . Fail $
                          "get_goal by the pre-fill position failed: "
                          <> T.unpack (failureText err)
                    , case stale of
                        Left err -> assert "the stale index fails loudly"
                                      ("Hole index 1" `T.isInfixOf` failureText err)
                        Right _  -> pure (Fail "index 1 should no longer name a hole")
                    ]
      hs -> pure . Fail $ "expected exactly 2 holes, got " <> show (length hs)


-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  hPutStrLn stderr "agda-mcp test suite"

  -- Tier 0: pure unit tests — hole finding, marker parsing.
  pureResults <- pureTests
  -- Tier 0b: structured diagnostics over captured Agda output (no Agda).
  diagResults <- diagnosticTests
  -- Tier 1a: hole-model tests (no Agda, but needs fixture files).
  holeResults <- holeModelTests
  -- Tier 1b: corpus / search tests (no Agda, but needs fixture file).
  corpusResults <- corpusTests
  -- Tier 1c: timeout enforcement, driven by a fake agda (no real Agda needed).
  timeoutResults <- timeoutTests
  -- Tier 1d: the response echo and root resolution (#72/#76).  Runs *after*
  -- the timeout tests: it leaves AGDA_MCP_FAKE_EXIT set, and their fast-path
  -- case asserts the stand-in's default exit status of 0.
  echoResults <- echoTests
  -- Tier 1e: hole addressing — position vs index, and the parse of both (#79).
  addressResults <- holeAddressingTests
  -- Tier 1f: the whole-project gate (#78), driven by a fixture gate script.
  gateResults <- gateTests
  -- Tier 1g: the requested path — how it resolves, and how it refuses (#101).
  pathResults <- pathTests
  -- Tier 2: integration tests (only if agda + fixtures are available).
  mEnv <- probeAgdaEnv
  integrationResults <- case mEnv of
    Nothing           -> do
      hPutStrLn stderr "\n── Integration tests (tier 2): SKIPPED ──"
      pure []
    Just (cfg, fixture, repoRoot) -> integrationTests cfg fixture repoRoot

  let allResults =
        pureResults <> diagResults <> holeResults <> corpusResults
          <> timeoutResults <> echoResults <> addressResults <> gateResults
          <> pathResults <> integrationResults
      total  = length allResults
      passed = length (filter id allResults)
      failed = total - passed

  hPutStrLn stderr $ "\n" <> show passed <> "/" <> show total <> " tests passed."
  if failed > 0 then exitFailure else exitSuccess
