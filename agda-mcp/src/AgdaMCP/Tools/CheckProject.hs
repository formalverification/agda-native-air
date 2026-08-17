-- | CheckProject.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Tools/CheckProject.hs
--
-- Description:
--   The whole-project check tool, @check_project@ (issue #78).
--
--   The other four tools answer questions about one file.  This one runs the
--   project's own acceptance gate — the command a human runs before saying the
--   work is done — and reports its verdict.  It exists because of a specific,
--   documented failure: in the field session of
--   docs/feedback/flrp-agda-mcp-improvements.md § 3.5, the gate was a 10–20
--   minute @make check@ over a generated @Everything.agda@, and the agent ran it
--   four times as a backgrounded Bash job, each time defending by hand against a
--   wrapper script whose last command was an @echo@ — so the shell exited 0
--   whatever @make@ had done, and the log had to be grepped for @error:@.  That
--   is the workflow this tool replaces, trap included.
--
--   The v1 contract is deliberately modest: run the real gate, and never
--   misreport its exit code.
--
--   Design note — what @success@ is a function of.
--     The per-file tools read success off Agda's exit code and nothing else
--     (issue #72), because there the only failure mode worth defending against
--     is Agda's prose drifting and silently turning a red build green.  A gate
--     has a second one, and it is the one the field session actually met: a
--     wrapper can report 0 for a build that failed.  So @success@ here is a
--     conjunction — exit 0, in time, and no error diagnostic in the output —
--     while @verdict.exitCode@ echoes the gate's own status verbatim and is
--     never overridden.  The extra conjunct can only turn a green gate red,
--     never a red one green, and when it fires it is named: @maskedFailure@.
--
--   Design note — bounded like everything else (issue #77), but sized for a
--   project.
--     The gate runs through 'AgdaMCP.Agda.runCommand', so it is spawned into
--     its own process group and killed group-wide on the SIGINT → SIGTERM →
--     SIGKILL ladder at the bound — which for a @make@ gate means the whole
--     build tree dies, not just @make@.  The bound is its own flag
--     (@--check-timeout@, default 30 minutes) rather than the per-call
--     @--timeout@ (default 5 minutes), because a whole-project check is exactly
--     the call that legitimately runs for tens of minutes.  A timed-out response
--     still carries how far the run got: @modulesChecked@, and the module Agda
--     was checking when it was killed.
--
--   Design note — no streaming, in this version.
--     The MCP transport in 'AgdaMCP.Server' is a synchronous line loop with no
--     progress-notification plumbing, so this call blocks for the duration of
--     the gate and reports its timings at the end.  Progress notifications are
--     follow-on scope; @modulesChecked@ and @failingModule@ are what a caller
--     gets instead, and on a timeout they are what say where the run reached.
--     Narrowing a check to files changed @since@ a revision is likewise
--     follow-on scope, deliberately not built here.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.CheckProject
  ( handleCheckProject
    -- * Exposed for testing
  , progressModules
  , parseCheckingLine
  , failingModuleOf
  , outputTailOf
  , projectVerdictMeaning
  , projectTimeoutMessage
  , maxTailLines
  , maxTailChars
  ) where

import Data.List (find, nub)
import Data.Text (Text)
import qualified Data.Text as T

import System.Directory
  ( doesDirectoryExist, doesFileExist, getCurrentDirectory, makeAbsolute )
import System.FilePath (takeDirectory)

import AgdaMCP.Agda
  ( AgdaConfig (..), AgdaResult (..), runCommand )
import AgdaMCP.Diagnostics (capDiagnostics, parseDiagnostics)
import AgdaMCP.Gate
  ( GateConfig, GatePlan (..), checkTimeoutOf, resolveGate )
import AgdaMCP.Project (resolveProjectDir, withEffectiveFlags)
import AgdaMCP.Types


-- ---------------------------------------------------------------------------
-- check_project
-- ---------------------------------------------------------------------------

-- | handleCheckProject: run the project's gate and report what it said.
--
-- The order of operations is the contract:
--
--   1. Resolve the anchor — the requested @projectPath@, or the server's own
--      working directory.  A path that does not exist is an error, not an
--      excuse to check something else.
--   2. Resolve the library context from that anchor, refusing outright when it
--      belongs to a different checkout of a library this server has registered
--      elsewhere (issue #76) — the same refusal, for the same reason, that the
--      per-file tools make.
--   3. Decide the gate ('AgdaMCP.Gate.resolveGate'), failing loudly when there
--      is none rather than reporting a check that never happened.
--   4. Run it bounded, and report: the verdict, the structured first error, the
--      module it stopped in, how far it got, and — when the check did not pass —
--      the tail of what it printed.
handleCheckProject
  :: AgdaConfig -> GateConfig -> CheckProjectParams
  -> IO (Either ToolFailure CheckProjectResult)
handleCheckProject cfg gcfg params = do
  mAnchor <- resolveAnchor (cppProjectPath params)
  case mAnchor of
    Left err     -> pure (Left (FailMessage err))
    Right anchor -> do
      resolved <- resolveProjectDir cfg anchor
      case resolved of
        Left mismatch -> pure (Left (FailProject mismatch))
        Right pc      -> do
          mPlan <- resolveGate gcfg cfg pc anchor (cppTarget params)
          case mPlan of
            Left why   -> pure (Left (FailMessage why))
            Right plan -> Right <$> runGate cfg gcfg params pc plan

-- | runGate: run a resolved gate and assemble the response.
runGate
  :: AgdaConfig -> GateConfig -> CheckProjectParams -> ProjectContext -> GatePlan
  -> IO CheckProjectResult
runGate cfg gcfg params pc plan = do
  let bound  = checkTimeoutOf gcfg
      runCfg = cfg { agdaTimeout = bound }
  result <- runCommand runCfg (gpBinary plan) (gpArgs plan) (gpCwd plan)
  let combined = arStdout result <> "\n" <> arStderr result
      -- Agda's own diagnostics, from whichever stream they arrived on.  The
      -- timeout notice is ours, so it is kept out of 'parsed' and prepended to
      -- the reported list: it belongs in the payload the caller reads, but it
      -- must not be able to take part in the masked-failure test below.
      parsed   = parseDiagnostics combined
      timedOut = arTimedOut result
      allDiags = [ plainDiagnostic DiagError (projectTimeoutMessage bound) | timedOut ]
                   <> parsed
      (diags, total) = capDiagnostics (cppMaxDiagnostics params) allDiags
      firstErr = find ((== DiagError) . diagSeverity) allDiags
      -- The field-session trap: exit 0 with errors in the log.  Judged on
      -- Agda's diagnostics alone, and only on a run that finished.
      masked   = arExitCode result == 0 && not timedOut
                   && any ((== DiagError) . diagSeverity) parsed
      success  = arExitCode result == 0 && not timedOut && not masked
      progress = progressModules combined
      (failMod, failFile) = failingModuleOf progress firstErr
  pure CheckProjectResult
    { cprSuccess          = success
    , cprTimedOut         = timedOut
    , cprMaskedFailure    = masked
    , cprElapsedMs        = arElapsedMs result
    , cprTimeoutSeconds   = bound
    , cprGate             = gpGate plan
    , cprDiagnostics      = diags
    , cprDiagnosticsTotal = total
    , cprFirstError       = firstErr
    , cprFailingModule    = failMod
    , cprFailingFile      = failFile
    , cprModulesChecked   = length (nub (map fst progress))
      -- Only on a failure: a passing gate's output is noise, while a failing
      -- one can have failed for a reason Agda never printed — a missing target,
      -- a shell error, a killed build — and leaving the caller to infer it from
      -- an empty diagnostics list is how a tool sends someone back to the shell.
    , cprOutputTail       = if success then Nothing else outputTailOf combined
    , cprVerdict          = projectVerdict result
    , cprCommand          = arCommand result
    , cprProject          = reportedContext pc plan
    }

-- | reportedContext: the project block to echo.
--
-- For the @Everything@ gate this server assembles Agda's flags, so the context
-- is restated from the very list Agda received ('withEffectiveFlags'), exactly
-- as the per-file tools do.  For a @make@ or configured gate it is not: the
-- gate chooses its own Agda invocation, and claiming its include paths would be
-- an invention.  What is reported then is the server's own configuration, and
-- the tool description says so.
reportedContext :: ProjectContext -> GatePlan -> ProjectContext
reportedContext pc plan = case gateSource (gpGate plan) of
  GateFromEverything -> withEffectiveFlags (gpArgs plan) pc
  _                  -> pc

-- | resolveAnchor: the directory discovery and resolution start from.
--
-- A file anchors its own directory, so a caller can pass the file it happens to
-- be editing.  A path that does not exist is refused: silently anchoring at its
-- parent would run a real gate over a project the caller did not name, and
-- report a pass about it.
resolveAnchor :: Maybe FilePath -> IO (Either Text FilePath)
resolveAnchor Nothing     = Right <$> getCurrentDirectory
resolveAnchor (Just path) = do
  abs'   <- makeAbsolute path
  isDir  <- doesDirectoryExist abs'
  isFile <- doesFileExist abs'
  pure $ if isDir  then Right abs'
    else if isFile then Right (takeDirectory abs')
    else Left $
      "agda-mcp: projectPath does not exist: " <> T.pack abs'
      <> "\n  Pass a file or directory inside the project, or omit projectPath"
      <> " to check the project this server is standing in."


-- ---------------------------------------------------------------------------
-- The verdict
-- ---------------------------------------------------------------------------

-- | projectVerdict: what ran, what its verdict means, and the gate's own exit
-- code.
--
-- 'vEquivalentTo' is a command a human can paste: the gate's working directory
-- is part of the invocation for a @make@ gate, so it is named rather than
-- assumed.  The @cd@ is rendered through 'commandLine' too, so a path with a
-- space is quoted the same way every other argument is.
projectVerdict :: AgdaResult -> Verdict
projectVerdict result = Verdict
  { vEquivalentTo = "(" <> cdTo <> " && " <> commandLine echo <> ")"
  , vMeaning      = projectVerdictMeaning
  , vExitCode     = arExitCode result
  }
  where
    echo = arCommand result
    cdTo = commandLine CommandEcho
      { ceBinary = "cd", ceArgs = [ceCwd echo], ceCwd = ceCwd echo }

-- | projectVerdictMeaning: the sentence a client reads instead of this source.
--
-- It has to say two things at once: that the exit code is never massaged, and
-- that a zero exit code alone is not taken as a pass.  Those sound contrary and
-- are not — the asymmetry is the point, and the field session is why it exists.
projectVerdictMeaning :: Text
projectVerdictMeaning =
  "success is true if and only if that command exited 0, finished inside the \
  \--check-timeout bound, and printed no error diagnostic. exitCode is the \
  \gate's own status, echoed verbatim and never overridden or reinterpreted, so \
  \a failing gate cannot be reported green. The reverse is possible and \
  \deliberate: a gate that exits 0 while its output carries Agda errors is \
  \reported as success:false with maskedFailure:true, because a wrapper script \
  \whose last command is an echo exits 0 whatever make did — the trap that made \
  \the field session grep its build logs for 'error:', which is exactly what \
  \this tool exists to make unnecessary. So the output can turn a green gate \
  \red, never a red gate green."

-- | projectTimeoutMessage: the timeout, as the caller needs to read it — the
-- bound that was hit, and the reason it is usually the wrong bound rather than
-- a hung build.
projectTimeoutMessage :: Maybe Int -> Text
projectTimeoutMessage mBound =
  "the project gate timed out after " <> bound
  <> " (raise --check-timeout if this gate legitimately runs longer; a cold"
  <> " whole-project check that must build .agdai interfaces for a large"
  <> " library can take tens of minutes)"
  where
    bound = maybe "the configured bound" (\n -> T.pack (show n) <> "s") mBound


-- ---------------------------------------------------------------------------
-- Reading the gate's output
-- ---------------------------------------------------------------------------

-- | progressModules: the modules Agda announced it was checking, in the order
-- it announced them.
--
-- Agda prints @Checking M (/path/M.agda).@ when it re-typechecks a module from
-- source — indented by import depth, and interleaved with whatever @make@ is
-- printing — and prints nothing at all for a module it loaded from a warm
-- @.agdai@ interface.  Two useful facts follow: the count of distinct names is
-- how much of the project was actually rebuilt, and the last name is where a
-- killed run got to.
progressModules :: Text -> [(Text, FilePath)]
progressModules txt = [ e | ln <- T.lines txt, Just e <- [parseCheckingLine ln] ]

-- | parseCheckingLine: one @Checking M (/path/M.agda).@ line, or 'Nothing'.
--
-- The shape is required in full — the keyword, the parenthesised path, and the
-- trailing period — so that a line of prose beginning with the word "Checking"
-- is not mistaken for progress.  This mirrors what
-- 'AgdaMCP.Diagnostics.parseDiagnostics' already treats as a block boundary.
parseCheckingLine :: Text -> Maybe (Text, FilePath)
parseCheckingLine raw = do
  rest <- T.stripPrefix "Checking " (T.stripStart raw)
  body <- T.stripSuffix "." (T.stripEnd rest)
  let (nameT, parenT) = T.breakOn "(" body
      name            = T.strip nameT
  path <- T.stripSuffix ")" =<< T.stripPrefix "(" (T.stripEnd parenT)
  if T.null name || T.null path then Nothing else Just (name, T.unpack path)

-- | failingModuleOf: where the gate stopped.
--
-- With a located first error, that error's file is authoritative and the module
-- name is whichever @Checking@ line announced it (the last one, if a module was
-- checked more than once).  Without one — a timeout, or an error Agda printed
-- with no position — the answer is the last module the run started, which is
-- the progress report a blocking call can otherwise not give.  An unannounced
-- file yields the file and no module rather than a guess.
failingModuleOf :: [(Text, FilePath)] -> Maybe Diagnostic -> (Maybe Text, Maybe FilePath)
failingModuleOf progress mErr = case mErr >>= diagFile of
  Just file -> (moduleFor file, Just file)
  Nothing   -> case lastMaybe progress of
    Just (name, file) -> (Just name, Just file)
    Nothing           -> (Nothing, Nothing)
  where
    moduleFor file = lastMaybe [ name | (name, f) <- progress, f == file ]

    lastMaybe [] = Nothing
    lastMaybe xs = Just (last xs)

-- | outputTailOf: the end of the gate's output, bounded.
--
-- The replacement for the @tail -50 build.log@ half of the workflow this tool
-- absorbs: when a gate fails for a reason that is not an Agda diagnostic — no
-- such target, a missing tool, a killed build — this is the only thing that
-- says what happened.  Both bounds are on the text as emitted, elision marker
-- included, so a client budgeting 'maxTailChars' is never handed more.
outputTailOf :: Text -> Maybe Text
outputTailOf raw
  | T.null trimmed = Nothing
  | otherwise      = Just (byChars (byLines trimmed))
  where
    trimmed = T.strip raw

    byLines t
      | dropped <= 0 = t
      | otherwise    = T.intercalate "\n" (lineMarker dropped : drop dropped ls)
      where
        ls      = T.lines t
        dropped = length ls - maxTailLines

    lineMarker n = "… " <> T.pack (show n) <> " earlier lines elided …"

    byChars t
      | T.length t <= maxTailChars = t
      | otherwise = charMarker <> T.takeEnd (maxTailChars - T.length charMarker) t

    charMarker = "… earlier output elided …\n"

-- | How many trailing lines of the gate's output to keep.
maxTailLines :: Int
maxTailLines = 40

-- | A second bound, for output whose lines are enormous.
maxTailChars :: Int
maxTailChars = 4000
