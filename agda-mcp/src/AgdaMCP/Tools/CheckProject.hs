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
--     conjunction — exit 0, in time, and no failure evidence in the output —
--     while @verdict.exitCode@ echoes the gate's own status verbatim and is
--     never overridden.  The extra conjunct can only turn a green gate red,
--     never a red one green, and when it fires it is named: @maskedFailure@.
--
--     "Failure evidence" is two recognizers, not a general theory: Agda's own
--     error diagnostics, and the gate's own failure lines ('gateFailureLines' —
--     make reporting a recipe that died, which is what a missing tool or a
--     failed non-Agda step looks like).  A mask that prints neither is reported
--     as a pass, and there is no honest way around that from outside the
--     wrapper.  What follows from it is the rule that @outputTail@ is returned
--     whatever the verdict: the response must never say "pass" while withholding
--     the one thing that could contradict it.
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
  , failingModuleOf
  , gateFailureLines
  , outputTailOf
  , projectVerdictMeaning
  , projectTimeoutMessage
  , maxTailLines
  , maxTailChars
  ) where

import Data.List (find, nub)
import Data.Text (Text)
import qualified Data.Text as T

import System.Directory (getCurrentDirectory)

import AgdaMCP.Agda
  ( AgdaConfig (..), AgdaResult (..), debugLog, progressModules, runCommand )
import AgdaMCP.Diagnostics (capDiagnostics, parseDiagnostics)
import AgdaMCP.Gate
  ( GateConfig, GatePlan (..), checkTimeoutOf, resolveGate )
import AgdaMCP.Path (resolveRequestedAnchor)
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
--      module it stopped in, how far it got, and the tail of what it printed —
--      that last whatever the verdict, since a mask this server cannot
--      recognize is reported as a pass and the output is then the only evidence
--      there is.
handleCheckProject
  :: AgdaConfig -> GateConfig -> CheckProjectParams
  -> IO (Either ToolFailure CheckProjectResult)
handleCheckProject cfg gcfg params = do
  mAnchor <- resolveAnchor (cppProjectPath params)
  case mAnchor of
    Left failure -> pure (Left (FailPath failure))
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
  -- Under --verbose, say which gate was chosen /before/ running it: a gate can
  -- run for tens of minutes, and an operator watching stderr should not have to
  -- wait for the response to learn what is running.
  debugLog runCfg $ "check_project: gate " <> T.pack (show (gateSource (gpGate plan)))
    <> " → " <> T.pack (unwords (gpBinary plan : gpArgs plan))
    <> " (cwd " <> T.pack (maybe "<server's>" id (gpCwd plan)) <> ")"
  result <- runCommand runCfg (gpBinary plan) (gpArgs plan) (gpCwd plan)
  debugLog runCfg $ "check_project: exit=" <> T.pack (show (arExitCode result))
    <> " timedOut=" <> T.pack (show (arTimedOut result))
    <> " elapsedMs=" <> T.pack (show (arElapsedMs result))
  let combined = arStdout result <> "\n" <> arStderr result
      -- Agda's own diagnostics, from whichever stream they arrived on.  The
      -- timeout notice is ours, so it is kept out of 'parsed' and prepended to
      -- the reported list: it belongs in the payload the caller reads, but it
      -- must not be able to take part in the masked-failure test below.
      parsed   = parseDiagnostics combined
      timedOut = arTimedOut result
      -- The field-session trap: exit 0 with a failure in the log.  Two kinds of
      -- evidence count, because a masked gate need not have failed inside Agda —
      -- Agda's own error diagnostics, and the gate's own failure lines (make
      -- reporting a recipe that died, which is what a missing tool or a failed
      -- non-Agda step looks like).
      agdaErrors   = any ((== DiagError) . diagSeverity) parsed
      gateFailures = gateFailureLines combined
      masked   = arExitCode result == 0 && not timedOut
                   && (agdaErrors || not (null gateFailures))
      success  = arExitCode result == 0 && not timedOut && not masked
      -- When the mask is caught by a gate failure line alone, that line is the
      -- only thing explaining the verdict, so it is reported as a diagnostic of
      -- ours.  When Agda did report errors, they are the root cause and this
      -- would only push them out of firstError.
      maskDiags = [ plainDiagnostic DiagError (maskedMessage ln)
                  | masked, not agdaErrors, ln <- take 1 gateFailures ]
      allDiags = [ plainDiagnostic DiagError (projectTimeoutMessage bound) | timedOut ]
                   <> maskDiags
                   <> parsed
      (diags, total) = capDiagnostics (cppMaxDiagnostics params) allDiags
      firstErr = find ((== DiagError) . diagSeverity) allDiags
      progress = progressModules combined
      -- Only a check that did not pass has a module it stopped in.  Asking
      -- unconditionally made a green run name the last module it checked as the
      -- one it "stopped in" — a successfully checked module labelled as failing
      -- (Copilot's third review of PR 98).
      (failMod, failFile)
        | success   = (Nothing, Nothing)
        | otherwise = failingModuleOf progress firstErr
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
      -- Returned whatever the verdict, and that is the point.  A masked failure
      -- this server does not recognize — a wrapper hiding a failure that printed
      -- nothing we can key on — is a run reported as a pass, and withholding the
      -- output exactly there would leave the caller with no way to see it at all.
      -- The tail is what makes an unrecognized mask visible rather than silent;
      -- it also costs nothing on a quiet gate, whose output is empty.
    , cprOutputTail       = outputTailOf combined
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
--
-- Omitting @projectPath@ anchors at the server's own working directory, which
-- is the documented default — "the project this server is standing in".  A
-- @projectPath@ that /is/ given goes through 'resolveRequestedAnchor', so a
-- relative one is resolved against that same directory and, when that names
-- nothing, refused with the rule stated rather than left for the caller to
-- infer (issue #101).
resolveAnchor :: Maybe FilePath -> IO (Either PathFailure FilePath)
resolveAnchor Nothing     = Right <$> getCurrentDirectory
resolveAnchor (Just path) = resolveRequestedAnchor "projectPath" path


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
  \--check-timeout bound, and printed no failure evidence. exitCode is the \
  \gate's own status whenever the gate produced one, echoed verbatim and never \
  \reinterpreted, so a failing gate cannot be reported green. Two runs have no \
  \status of their own and report -1: a gate that could not be started at all, \
  \and one killed at the bound. timedOut tells those two apart, and a gate that \
  \could not be started says so in outputTail; a killed process's real status is \
  \the signal that took it down, which is indistinguishable from an ordinary \
  \failure, which is why this server reports the fact as a flag rather than as a \
  \magic exit code. The reverse is possible and \
  \deliberate: a gate that exits 0 while its output carries an Agda error or a \
  \make failure line is reported as success:false with maskedFailure:true, \
  \because a wrapper script whose last command is an echo exits 0 whatever make \
  \did — the trap that made the field session grep its build logs for 'error:', \
  \which is exactly what this tool exists to make unnecessary. So the output can \
  \turn a green gate red, never a red gate green. Those two recognizers are not \
  \a general theory of failure: a mask that prints neither is reported as a \
  \pass, which is why outputTail is returned whatever the verdict."

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

-- | failingModuleOf: where the gate stopped.
--
-- With a located first error, that error's file is authoritative and the module
-- name is whichever @Checking@ line announced it (the last one, if a module was
-- checked more than once).  Without one — a timeout, or an error Agda printed
-- with no position — the answer is the last module the run started, which is
-- the progress report a blocking call can otherwise not give.  An unannounced
-- file yields the file and no module rather than a guess.
--
-- The caller asks this only of a check that did not pass: on a green run the
-- last module started is simply the last module checked, and calling it the
-- module the gate "stopped in" would be a failure report about a success.
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

-- | gateFailureLines: lines in which the gate itself reports having failed, as
-- distinct from Agda reporting a type error.
--
-- The gap this closes was found in review of the first version: @maskedFailure@
-- was judged from Agda's diagnostics alone, so a wrapper that masked a failure
-- Agda never saw — a missing tool, a failed non-Agda step, @make@ giving up —
-- still came back @success: true@, which is precisely the trap the tool claims
-- to remove.
--
-- What is recognized is GNU make's own error line, in the shapes it prints:
--
-- > make: *** [Makefile:12: check] Error 2
-- > make[1]: *** No rule to make target 'check'.  Stop.
-- > gmake: *** [check] Error 1
--
-- The @make@-family name is required before the @: *** @, so a line that merely
-- quotes one (in Agda's output, or in a recipe echoing a command) is not
-- evidence.  This is a list of recognized markers rather than a general theory
-- of failure, and the contract says so: a mask this list does not recognize is
-- reported as a pass — which is why 'cprOutputTail' is now returned whatever
-- the verdict, so the caller can see the evidence even when the server could
-- not name it.
gateFailureLines :: Text -> [Text]
gateFailureLines txt =
  [ line | raw <- T.lines txt, let line = T.strip raw, isMakeFailure line ]
  where
    isMakeFailure line =
      let (before, rest) = T.breakOn ": *** " line
      in  not (T.null rest) && T.takeWhile (/= '[') before `elem` makeNames

    -- The program name make prints, including the @make[N]@ of a sub-make.
    makeNames = ["make", "gmake", "mingw32-make"]

-- | maskedMessage: the diagnostic that explains a mask caught by a gate failure
-- line rather than by an Agda error.
maskedMessage :: Text -> Text
maskedMessage line =
  "the gate exited 0, but its output reports a failure: " <> line
  <> " — reported as success:false with maskedFailure:true, since a wrapper's"
  <> " exit status is its last command's and says nothing about what failed"
  <> " inside it."

-- | outputTailOf: the end of the gate's output, bounded.
--
-- The replacement for the @tail -50 build.log@ half of the workflow this tool
-- absorbs: when a gate fails for a reason that is not an Agda diagnostic — no
-- such target, a missing tool, a killed build — this is the only thing that
-- says what happened.
--
-- Each marker is paid for out of the bound it announces — one line of the line
-- budget, one character of the character budget — so the result satisfies the
-- documented limit rather than exceeding it by the width of the marker.  That
-- is 'AgdaMCP.Diagnostics.boundMessage''s rule, and this deviated from it until
-- Copilot's third review of PR 98 caught the extra line.
outputTailOf :: Text -> Maybe Text
outputTailOf raw
  | T.null trimmed = Nothing
  | otherwise      = Just (byChars (byLines trimmed))
  where
    trimmed = T.strip raw

    byLines t
      | length ls <= maxTailLines = t
      | otherwise = T.intercalate "\n" (lineMarker dropped : drop dropped ls)
      where
        ls      = T.lines t
        kept    = maxTailLines - 1   -- the first line is the marker
        dropped = length ls - kept

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
