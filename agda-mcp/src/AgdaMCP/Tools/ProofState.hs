-- | ProofState.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Tools/ProofState.hs
--
-- Description:
--   Core proof-state tools for the agda-mcp server.
--
--   Each function implements one MCP tool.  They share an 'AgdaConfig' and call the
--   Agda binary via 'AgdaMCP.Agda'.  The agent invokes these through JSON-RPC tool calls;
--   the MCP server layer (AgdaMCP.Server) dispatches to the appropriate handler.
--
--   Tools:
--   * get_goal        - inspect goal type + context at a hole
--   * fill_hole       - try a candidate term and report typecheck result
--   * check_file      - load/reload a file and return all diagnostics
--   * get_diagnostics - lightweight summary (hole count, error count)
--
--   Design note: a hole is addressed by position, and every answer re-anchors
--   (issue #79).
--     get_goal and fill_hole take a 'AgdaMCP.Holes.HoleRef': a @(line, column)@
--     in the file as written, or the older 0-based @holeIndex@.  The position is
--     the handle to prefer.  A fill renumbers every index after it whether or
--     not any text moved, while it moves a position only when the candidate
--     changes the text above it.  A position inside no hole is an error
--     naming the file's holes, never a guess at the nearest one.  Because
--     neither handle survives an arbitrary edit, fill_hole and check_file answer
--     with the full hole list, the shape get_diagnostics already returned, so
--     the next address comes from the last response rather than from the
--     client's memory.  fill_hole's list describes the file /as the candidate
--     leaves it/, which is what the client will have once it keeps the
--     candidate; the bytes on disk are restored either way.
--
--   Design note: diagnostics are structured (issue #74).
--     check_file and get_diagnostics report each diagnostic with Agda's own
--     @code@, its @file@ and @range@, the bounded full message body, and an
--     @involved@ payload naming the types, candidates, or metas the message is
--     about, ordered most-likely-root-cause first and capped by the call's
--     @maxDiagnostics@ (with the pre-cap total reported).  All of that lives in
--     'AgdaMCP.Diagnostics', which is pure; these handlers only prepend the
--     timeout notice, apply the cap, and count.
--
--   Design note: every response says what it ran, against which tree (issues
--   #72, #76).
--     Before Agda is started, 'AgdaMCP.Project.resolveProject' decides the
--     library context from the requested path — the nearest @*.agda-lib@ above
--     it, falling back to the flags the server was started with — and refuses
--     the call outright when the file belongs to a different checkout of a
--     library this server has registered elsewhere.  Every response, success or
--     failure, then carries three keys: @verdict@ (the @agda@ command this call
--     is equivalent to, what a green result means, and Agda's exit code),
--     @command@ (binary, argument vector, working directory), and @project@
--     (the resolved root and the registry that decided it).  Success is a
--     function of the exit code alone; the diagnostics text never gets a vote,
--     so an Agda message-format change can empty the diagnostics list but can
--     never turn a failing build green.
--
--   Design note: the requested path is resolved and read before anything else
--   (issue #101).
--     All four tools go through 'AgdaMCP.Path.withSourceFile', which absolutises
--     the client's @filePath@, requires it to name a readable file, and reads it
--     under a guard.  Two things follow.  A relative path is resolved against
--     the /server's/ working directory — the only directory the server knows,
--     and normally not the client's project — so one that names nothing is
--     refused with a 'AgdaMCP.Types.PathFailure' stating the resolved path, that
--     directory, and the rule, instead of being resolved silently into the wrong
--     tree.  And a missing or unreadable file is that same structured failure
--     rather than an 'IOException' escaping the handler as @-32603 Internal
--     error@, which is what it used to be: an error naming neither the path nor
--     the rule, and the one the #83 field test measured a client abandoning the
--     server over.  Path resolution runs /before/ 'withProject' deliberately:
--     there is no library tree to resolve for a file that is not there.
--
--   Design note: every call is bounded and timed (issue #77).
--     Each tool spawns a cold @agda@ subprocess, bounded by 'AgdaConfig''s
--     @agdaTimeout@.  When that bound is hit the subprocess (and its process
--     group) is killed and the tool reports the timeout in its own vocabulary:
--     fill_hole as @status: "timeout"@, check_file and get_diagnostics as
--     @success: false@ with an explanatory error diagnostic, get_goal as a Left
--     naming the bound.  Every response also carries @elapsedMs@ and
--     @checkedFromSource@, so an agent can distinguish a slow cold call that
--     built @.agdai@ interfaces from a genuinely slow one.
--
--   Design note: the module name get_goal reports is Agda's own (issue #100).
--     It is read from Agda's @Checking M (path).@ progress line in the run this
--     call already makes, so it is the name Agda resolved from the include path:
--     what an @import@ of this file must say, what Agda's own messages print,
--     and the name of a file whose header is anonymous (@module _ where@), which
--     no reading of the source can supply.  The source scan is the fallback for
--     when Agda did not say — a warm run prints nothing, and a parse error, a
--     header that does not match its file name, or a timeout never reaches the
--     line — and there the name the header /claims/ is the answer worth having,
--     since the claim is the diagnosis when Agda will not accept it.  This is
--     the project's own thesis applied to its implementation: where Agda can
--     answer, ask Agda; the scan is the pre-flight approximation, not the
--     authority.  ('AgdaMCP.Agda.agdaModuleNameOf' reads the line;
--     'AgdaMCP.Tools.CheckProject' has read the same one since #78.)
--
--   Design note: every line scan reads the code-only view (issues #73, #100).
--     A source file's raw text carries things that look like Agda and are not: a
--     literate prose paragraph opening with @module@, a commented-out
--     declaration, the embedded Haskell of a @{-# FOREIGN GHC … #-}@ pragma.
--     'ensureDebugImport' and 'moduleNameOf' therefore scan
--     'AgdaMCP.Holes.codeOnly' — the source with prose, comments, and pragmas
--     blanked, every character position preserved — so the header they find is
--     the header Agda finds, and a line index found there still splices into the
--     original text.  Scanning the raw source instead is what made get_goal
--     report a module name read from a prose line (issue #100): the same fixture
--     whose prose #73 already stopped fooling the import injection.
--
--   Design note: all four tools typecheck the file IN PLACE.
--     Agda decides a module's name from where its file sits relative to the include
--     path, so a module embedded in a library at a hierarchical path (e.g. FLRP.Bridge
--     at src/FLRP/Bridge.lagda.md) only resolves when it is checked at its real
--     location, with the library's src root on the include path (supplied by the
--     caller's `-l <lib>` flag).  An earlier version copied the file to a scratch
--     directory before checking it; that works for flat top-level modules but collides
--     with the module's canonical file for library-embedded ones (ModuleDefinedInOtherFile
--     / ModuleNameDoesntMatchFileName).  See issue #66.
--
--     get_goal and fill_hole must still alter the source (inject the reporting macro,
--     or substitute a candidate), so they patch the real file transiently and restore
--     it under 'Control.Exception.bracket_'.  The original is captured and restored as
--     raw bytes ('Data.ByteString'), so the file is returned byte-for-byte even if Agda
--     errors or the call is interrupted; no encoding or newline round-trip is involved.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.ProofState
  ( handleGetGoal
  , handleFillHole
  , handleCheckFile
  , handleGetDiagnostics
    -- * Exposed for testing
  , ensureDebugImport
  , moduleNameOf
  , errorTagsOf
  , onlyOpenHoleErrors
  , batchVerdictMeaning
  , fillVerdictMeaning
  , goalVerdictMeaning
  ) where

import Control.Applicative ((<|>))
import Control.Exception (bracket_)
import qualified Data.ByteString as BS
import Data.List (find, findIndex)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

import AgdaMCP.Agda
  ( AgdaConfig, AgdaResult (..), agdaFlags, agdaModuleNameOf
  , checkedFromSourceOf, debugLog, parseGoalContext, reportExpr, runAgda
  , timeoutMessage
  )
import AgdaMCP.Diagnostics (capDiagnostics, parseDiagnostics)
import AgdaMCP.Holes
  ( HoleSpan (..), LiterateFlavour, codeOnly, findHoles, flavourOf
  , injectReportExpr, resolveHoleRef, substituteHole
  )
import AgdaMCP.Path (withSourceFile)
import AgdaMCP.Project
  ( fileDirIncludeFlags, projectExtraFlags, resolveProject, withEffectiveFlags )
import AgdaMCP.Types

-- ---------------------------------------------------------------------------
-- get_goal
-- ---------------------------------------------------------------------------

-- | handleGetGoal: inspect goal type and local context at the addressed hole.
--
-- 1. Read source file.
-- 2. Resolve the caller's 'HoleRef' — a @(line, column)@ position or a
--    @holeIndex@ — against that source (issue #79).
-- 3. Ensure @open import AgdaDojang.Debug@ is in scope (inject it if absent) so the
--    @reportGoalCtx@ macro resolves.
-- 4. Replace the hole with @reportGoalCtx ?@.
-- 5. Typecheck the patched file IN PLACE (restoring the original afterwards).
-- 6. Parse the AGDADOJANG_REQ_BEGIN/END block from Agda's output.
-- 7. Return structured (goal, context).
--
-- Steps 2 and 3 are in that order deliberately.  The caller's position is a
-- position in the file /as it stands/, while the import injection shifts every
-- line below the module header down by one; resolving first turns the position
-- into an index, which the injection cannot disturb because an import line
-- introduces no holes.
--
-- Failures are 'ToolFailure' rather than bare 'Text' because this is the one
-- proof-state tool whose timeout cannot ride inside a success-shaped response —
-- there is no goal to report — and the measurements the call did produce
-- (@elapsedMs@, the cache signal) must not be dropped with it (issue #77).
handleGetGoal :: AgdaConfig -> GetGoalParams -> IO (Either ToolFailure GoalInfo)
handleGetGoal cfg0 params =
  withSourceFile (ggFilePath params) $ \absPath origBytes src ->
    withProject cfg0 absPath $ \pc cfg ->
        case resolveHoleRef absPath (flavourOf absPath) src (ggHole params) of
          Left miss -> pure (Left (FailMessage miss))
          Right idx -> do
            let label = holeLabel (flavourOf absPath) src idx
            case injectReportExpr (reportExpr cfg) (flavourOf absPath) idx
                   (ensureDebugImport (flavourOf absPath) src) of
              -- Unreachable in practice: 'resolveHoleRef' validated the index
              -- against the same scan, and the injected import adds no holes.
              Nothing -> pure . Left . FailMessage $
                "Could not splice the reporting macro over " <> label
                <> " in " <> T.pack absPath
              Just patched -> do
                result <- runInPlace cfg absPath origBytes patched
                -- DEBUG: show what Agda actually returned
                debugLog cfg $ "get_goal: exit=" <> T.pack (show (arExitCode result))
                  <> " timedOut=" <> T.pack (show (arTimedOut result))
                  <> " elapsedMs=" <> T.pack (show (arElapsedMs result))
                debugLog cfg $ "get_goal stdout: " <> T.take 500 (arStdout result)
                debugLog cfg $ "get_goal stderr: " <> T.take 500 (arStderr result)
                -- Agda may emit markers on stdout or stderr; check both.
                let combined = arStdout result <> "\n" <> arStderr result
                    verdict  = patchedVerdict result goalVerdictMeaning
                      (label <> " replaced by '" <> reportExpr cfg <> " ?'")
                if arTimedOut result
                  -- A timeout is reported as such rather than as "could not parse
                  -- markers": the markers are missing because Agda was killed, and
                  -- saying so is what tells the caller to raise the bound.  It is a
                  -- structured failure so the response still carries the timing,
                  -- cache, and project metadata the call produced on the way down.
                  then pure . Left . FailTimeout $ TimeoutFailure
                    { tfMessage = timeoutMessage cfg <> "; no goal was reported for "
                        <> label <> " in " <> T.pack absPath
                    , tfElapsedMs         = arElapsedMs result
                    , tfCheckedFromSource = checkedFromSourceOf result
                    , tfVerdict           = verdict
                    , tfCommand           = arCommand result
                    , tfProject           = pc
                    }
                  else case parseGoalContext combined of
                    Nothing -> pure . Left . FailMessage $
                      "Could not parse goal/context markers from Agda output.\n"
                      <> "ran: " <> commandLine (arCommand result) <> "\n"
                      <> "output:\n" <> T.take 2000 combined
                    Just (goal, ctx) ->
                      pure . Right $ GoalInfo
                        { giGoal    = goal
                        , giContext = ctx
                        -- The name Agda resolved for this file (e.g. FLRP.Bridge),
                        -- from its own progress line in the run above; the name the
                        -- source declares is the fallback for when Agda did not say,
                        -- and is itself scanned off the code-only view, so neither
                        -- answer can come from prose or a comment (issue #100).
                        , giModule  = agdaModuleNameOf absPath result
                                        <|> moduleNameOf (flavourOf absPath) src
                        , giElapsedMs         = Just (arElapsedMs result)
                        , giCheckedFromSource = checkedFromSourceOf result
                        , giVerdict = Just verdict
                        , giCommand = Just (arCommand result)
                        , giProject = Just pc
                        }


-- ---------------------------------------------------------------------------
-- fill_hole
-- ---------------------------------------------------------------------------

-- | handleFillHole: try substituting @candidate@ into the addressed hole and
-- typecheck.
--
-- 1. Read source, resolve the caller's 'HoleRef' (a @(line, column)@ position
--    or a @holeIndex@), substitute the candidate over that hole's span.
-- 2. Typecheck the patched file IN PLACE (restoring the original afterwards).
-- 3. Exit 0 → ok.  A non-zero exit is ok only when 'onlyOpenHoleErrors' holds,
--    i.e. every reported error is an open hole's @[UnsolvedInteractionMetas]@;
--    a candidate that leaves @[UnsolvedMetaVariables]@ or
--    @[UnsolvedConstraints]@ behind is a type error (issue #69).
-- 4. Answer with the hole list of the patched source, so a client that keeps
--    the candidate re-anchors on positions without a second call (issue #79).
--    Those are the holes of the file /as this candidate leaves it/; the bytes
--    on disk are restored, so until the candidate is written back the file
--    still has the holes it started with.
handleFillHole :: AgdaConfig -> FillHoleParams -> IO (Either ToolFailure FillResult)
handleFillHole cfg0 params =
  withSourceFile (fhFilePath params) $ \absPath origBytes src ->
    withProject cfg0 absPath $ \pc cfg ->
        case resolveHoleRef absPath (flavourOf absPath) src (fhHole params) of
          Left miss -> pure (Left (FailMessage miss))
          Right idx -> do
            let label = holeLabel (flavourOf absPath) src idx
            case substituteHole (flavourOf absPath) idx (fhCandidate params) src of
              -- Unreachable in practice: 'resolveHoleRef' validated the index
              -- against the same scan of the same text.
              Nothing -> pure . Left . FailMessage $
                "Could not splice the candidate over " <> label
                <> " in " <> T.pack absPath
              Just patched -> do
                result <- runInPlace cfg absPath origBytes patched
                -- Agda 2.8.0 emits some errors on stdout; check both streams.
                let combined = arStdout result <> "\n" <> arStderr result
                    -- Verdict (issues #69, #77).  The timeout arm comes first: a killed
                    -- process exits on its signal (-2 SIGINT, -15 SIGTERM), which is
                    -- otherwise indistinguishable from an ordinary failure, and calling
                    -- an unfinished typecheck a type_error would be a false verdict.
                    -- Below it, a non-zero exit is ok only when every reported error is
                    -- an open hole's [UnsolvedInteractionMetas]; 'onlyOpenHoleErrors'
                    -- explains why this is a whitelist.  An exit code of -1 means the
                    -- agda binary could not be run at all.
                    status
                      | arTimedOut result           = FillTimeout
                      | arExitCode result == 0      = FillOk
                      | arExitCode result == (-1)   = FillCrash
                      | onlyOpenHoleErrors combined = FillOk
                      | otherwise                   = FillTypeError
                    msg
                      | arTimedOut result = Just (timeoutMessage cfg)
                      | status == FillOk  = Nothing
                      | otherwise         = Just (T.take 2000 combined)
                    -- The holes left in the patched source (every Agda hole
                    -- syntax, code regions only): the re-anchoring payload, of
                    -- which remainingHoles is the count.
                    remaining = holeInfosOf (findHoles (flavourOf absPath) patched)
                pure . Right $ FillResult
                  { frStatus    = status
                  , frCandidate = fhCandidate params
                  , frMessage   = msg
                  , frRemainingHoles = Just (length remaining)
                  , frHoles     = remaining
                  , frElapsedMs = arElapsedMs result
                  , frCheckedFromSource = checkedFromSourceOf result
                  , frVerdict   = patchedVerdict result fillVerdictMeaning
                      (label <> " replaced by the candidate")
                  , frCommand   = arCommand result
                  , frProject   = pc
                  }


-- ---------------------------------------------------------------------------
-- check_file
-- ---------------------------------------------------------------------------

-- | handleCheckFile: load/reload an Agda file and return all diagnostics.
--
-- The diagnostics are structured (issue #74): each carries Agda's own @code@,
-- its @file@ and @range@, the bounded full message body, and the entities the
-- message names.  They are ordered most-likely-root-cause first and capped at
-- @maxDiagnostics@, with the pre-cap total reported alongside so a truncated
-- list is never read as a short one.
--
-- @success@ is @exit code 0, in time@ and nothing else.  The diagnostics list
-- is a convenience over Agda's prose and gets no vote in the verdict: were it
-- otherwise, the position-parsing drift that issue #74 records would have been
-- a silent green build rather than a cosmetic gap (issue #72).
handleCheckFile :: AgdaConfig -> CheckFileParams -> IO (Either ToolFailure FileCheckResult)
handleCheckFile cfg0 params =
  withSourceFile (cfFilePath params) $ \absPath _bytes src ->
    withProject cfg0 absPath $ \pc cfg -> do
      result <- runAgda cfg absPath
      let combined = arStdout result <> "\n" <> arStderr result
          -- On a timeout the parsed diagnostics describe only what Agda managed to
          -- print before it was killed, so the timeout itself is prepended as an
          -- error.  Without it the response would be an empty diagnostics list next
          -- to success:false — accurate but unactionable.  It is prepended after
          -- the root-cause sort rather than through it: it explains why the rest of
          -- the list is short, so it belongs first whatever else was found.
          allDiags = [ timeoutDiagnostic cfg | arTimedOut result ]
                       <> parseDiagnostics combined
          (diags, total) = capDiagnostics (cfMaxDiagnostics params) allDiags
          holes   = holeInfosOf (findHoles (flavourOf absPath) src)
          success = arExitCode result == 0 && not (arTimedOut result)
      pure . Right $ FileCheckResult
        { fcrSuccess     = success
        , fcrDiagnostics = diags
        , fcrDiagnosticsTotal = total
        , fcrHolesCount  = length holes
        , fcrHoles       = holes
        , fcrTimedOut    = arTimedOut result
        , fcrElapsedMs   = arElapsedMs result
        , fcrCheckedFromSource = checkedFromSourceOf result
        , fcrVerdict     = plainVerdict result batchVerdictMeaning
        , fcrCommand     = arCommand result
        , fcrProject     = pc
        }


-- ---------------------------------------------------------------------------
-- get_diagnostics
-- ---------------------------------------------------------------------------

-- | handleGetDiagnostics: diagnostic summary; run Agda, count errors/warnings/holes.
--
-- Each hole is reported with its 0-based index (the @holeIndex@ accepted by
-- get_goal / fill_hole) and its 1-based line/column in the file as written —
-- literate-file coordinates for literate sources (issue #73).
--
-- The diagnostics are the structured ones of issue #74, root-cause ordered and
-- capped at @maxDiagnostics@; the error and warning counts are over /every/
-- diagnostic found, not over the capped list, so shortening the payload never
-- understates how much is wrong.
--
-- @success@ and @verdict@ are the same fields, with the same derivation from
-- Agda's exit code, that @check_file@ returns: the two tools differ in what
-- they summarize, never in what green means (issue #72).  The counts, by
-- contrast, come from parsing Agda's prose, so they can drift with its message
-- format, which is exactly why they are not what the verdict is read from.
handleGetDiagnostics :: AgdaConfig -> GetDiagnosticsParams -> IO (Either ToolFailure DiagnosticsResult)
handleGetDiagnostics cfg0 params =
  withSourceFile (gdFilePath params) $ \absPath _bytes src ->
    withProject cfg0 absPath $ \pc cfg -> do
      result <- runAgda cfg absPath
      let combined = arStdout result <> "\n" <> arStderr result
          -- As in check_file: a timeout is itself an error diagnostic, so it lands in
          -- both the list and the error count rather than vanishing into a summary
          -- that reads "0 errors" because Agda never finished reporting any.
          allDiags = [ timeoutDiagnostic cfg | arTimedOut result ]
                       <> parseDiagnostics combined
          (diags, total) = capDiagnostics (gdMaxDiagnostics params) allDiags
          countOf sev = length (filter ((== sev) . diagSeverity) allDiags)
      pure . Right $ DiagnosticsResult
        { drFilePath = gdFilePath params
        , drErrors   = countOf DiagError
        , drWarnings = countOf DiagWarning
        , drHoles    = holeInfosOf (findHoles (flavourOf absPath) src)
        , drSuccess  = arExitCode result == 0 && not (arTimedOut result)
        , drDiagnostics = diags
        , drDiagnosticsTotal = total
        , drTimedOut = arTimedOut result
        , drElapsedMs = arElapsedMs result
        , drCheckedFromSource = checkedFromSourceOf result
        , drVerdict  = plainVerdict result batchVerdictMeaning
        , drCommand  = arCommand result
        , drProject  = pc
        }


-- ---------------------------------------------------------------------------
-- The response echo (issues #72, #76)
-- ---------------------------------------------------------------------------

-- | withProject: resolve the file's library context, then run the tool body
-- with the flags that resolution implies.
--
-- The gate every proof-state tool passes through.  A 'ProjectMismatch', where
-- the requested file belongs to a different checkout of a library this server has
-- registered elsewhere, short-circuits here, /before/ Agda is started and
-- before any in-place patching, so a wrong-tree answer is not merely unreported
-- but impossible.  On the ordinary path the body gets the resolved context to
-- echo and a config whose flags reach the file's own tree.
--
-- This is also the /only/ place the effective flags are assembled: the server's
-- own, plus whatever resolution implies ('projectExtraFlags'), plus (only for
-- a file no provided include directory reaches) the requested file's own
-- directory, the @-i@ that lets a flat top-level module resolve at its real
-- path (issue #66).  The condition is 'fileDirIncludeFlags': for a file inside
-- a hierarchical project the unconditional extra root made short-name imports
-- ambiguous (issue #103).  Assembling them anywhere else is how
-- the echo and the invocation drift apart: 'withEffectiveFlags' restates the
-- context from the very list handed to Agda, so @project.selectedLibraries@ and
-- @project.includePaths@ cannot describe a context Agda did not see, and a
-- client trusting @project@ gets the same answer as one parsing @command.args@.
withProject
  :: AgdaConfig
  -> FilePath
  -> (ProjectContext -> AgdaConfig -> IO (Either ToolFailure a))
  -> IO (Either ToolFailure a)
withProject cfg absPath body = do
  resolved <- resolveProject cfg absPath
  case resolved of
    Left mismatch -> pure (Left (FailProject mismatch))
    Right pc      -> do
      let baseFlags = agdaFlags cfg <> projectExtraFlags pc
      dirFlags <- fileDirIncludeFlags baseFlags pc absPath
      let effFlags = baseFlags <> dirFlags
      body (withEffectiveFlags effFlags pc) cfg { agdaFlags = effFlags }

-- | plainVerdict: the verdict for a tool that checked the file as it stands.
plainVerdict :: AgdaResult -> Text -> Verdict
plainVerdict result meaning = Verdict
  { vEquivalentTo = commandLine (arCommand result)
  , vMeaning      = meaning
  , vExitCode     = arExitCode result
  }

-- | patchedVerdict: the verdict for a tool that checked a transiently-patched
-- copy of the file.
--
-- @get_goal@ and @fill_hole@ both rewrite the source before running Agda, so
-- naming the bare command would be a false equivalence: nobody running it
-- themselves would reproduce the result.  The patch is named alongside the
-- command, together with the fact that the file is restored either way.
patchedVerdict :: AgdaResult -> Text -> Text -> Verdict
patchedVerdict result meaning patchNote = Verdict
  { vEquivalentTo = commandLine (arCommand result)
      <> ", run against that file with " <> patchNote
      <> " (the file on disk is restored afterwards, byte for byte)"
  , vMeaning      = meaning
  , vExitCode     = arExitCode result
  }

-- | batchVerdictMeaning: what @success@ means for @check_file@ and
-- @get_diagnostics@.
--
-- The sentence issue #72 exists to publish.  It is deliberately explicit that
-- there is no interaction mode and no tolerance for outstanding metas, because the
-- field report's original complaint (§ 3.1) was a guess that the server ran Agda
-- interactively, which is plausible, wrong, and expensive: an agent that cannot
-- rule it out runs the real checker anyway and the tool call is pure overhead.
batchVerdictMeaning :: Text
batchVerdictMeaning =
  "success is true if and only if that command exited 0, so it means exactly \
  \what green means in a batch build. Unsolved metavariables, unsolved \
  \constraints, and open holes all make agda exit non-zero and so make success \
  \false; there is no interaction mode anywhere in this server. The verdict is \
  \read from the exit code alone — never from the diagnostics text — so a \
  \change in Agda's message format can empty the diagnostics list but cannot \
  \turn a failing build green."

-- | fillVerdictMeaning: what @status@ means for @fill_hole@, in particular,
-- the exact set of failures its @ok@ tolerates (issue #69).
fillVerdictMeaning :: Text
fillVerdictMeaning =
  "status is \"ok\" if and only if that command exited 0, or failed with \
  \nothing but [UnsolvedInteractionMetas] (holes still open in the file), \
  \including any new sub-hole the candidate itself introduced, which is a \
  \successful refinement. Every other failure is \"type_error\", including \
  \[UnsolvedMetaVariables] and [UnsolvedConstraints]: a candidate that leaves \
  \a meta unsolved does not pass the build and is not ok here either. A run \
  \killed by --timeout is \"timeout\" (the candidate was never judged) and an \
  \agda binary that could not be started at all is \"crash\"."

-- | goalVerdictMeaning: what @get_goal@'s exit code is, and is not, evidence of.
goalVerdictMeaning :: Text
goalVerdictMeaning =
  "the goal and context are read from the reporting macro's marker block in \
  \that command's output. exitCode is that command's own, and is normally \
  \non-zero even when the goal is reported correctly, because the injected \
  \macro leaves an interaction point behind: it is evidence about this \
  \introspection run, not a verdict on the file. Use check_file for that."


-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- | runInPlace: typecheck a transiently-patched version of a file at its real path.
--
-- Writes @patched@ (as UTF-8) over @absPath@, runs Agda there on the flags
-- 'withProject' assembled — the caller's @-l \<lib\>@, hence the library's src root,
-- plus whatever resolution added, plus @-i \<dir-of-file\>@ — then restores
-- @originalBytes@.  It adds no flags of its own, so what the response echoes under
-- @command@ and @project@ is exactly what ran here too.
-- Both the write and the restore go through 'Data.ByteString', and
-- the restore runs under 'bracket_', so the file is returned to its exact original
-- bytes even if Agda errors or the call is interrupted; i.e., no encoding or newline
-- round-trip is involved.  Checking at the real path (rather than a scratch copy) is
-- what lets hierarchically-named library modules resolve; see the module header and
-- issue #66.
--
-- The timeout path restores exactly like every other path, and by construction
-- rather than by luck: 'AgdaMCP.Agda.runAgda' reports a timeout as a /value/
-- ('arTimedOut') after it has killed and reaped the subprocess, so it returns
-- normally and 'bracket_' runs its restore action the same way it does after a
-- clean typecheck.  A timed-out @fill_hole@ therefore leaves the fixture
-- byte-identical (issue #77); the test suite pins this.
--
-- Only the file's /contents/ are restored, not its modification time: the restore write
-- deliberately leaves a fresh mtime.  That is intentional; a newer mtime forces Agda to
-- re-typecheck from the restored source on its next load under any interface-freshness
-- rule, whereas resetting mtime to the original (older) value could let Agda reuse an
-- @.agdai@ built from the transiently-patched content (e.g. a fill_hole candidate that
-- completed the module).  Editors that compare content, not mtime alone, will not prompt,
-- since the bytes are unchanged.
runInPlace :: AgdaConfig -> FilePath -> BS.ByteString -> Text -> IO AgdaResult
runInPlace cfg absPath originalBytes patched =
  bracket_
    (BS.writeFile absPath (TE.encodeUtf8 patched))
    (BS.writeFile absPath originalBytes)
    (runAgda cfg absPath)


-- | holeInfosOf: a scan's spans as the wire hole list — the one construction
-- behind @get_diagnostics@'s, @check_file@'s, and @fill_hole@'s @holes@ key, so
-- the three cannot describe holes differently (issue #79).
--
-- The goal is the cheap placeholder the shape has always carried: listing holes
-- costs one pure scan, whereas a real goal per hole costs one Agda run per hole.
holeInfosOf :: [HoleSpan] -> [HoleInfo]
holeInfosOf holes =
  [ HoleInfo
      { hiIndex = i
      , hiLine  = hsLine h
      , hiCol   = hsCol h
      , hiGoal  = "?"  -- Lightweight: no goal extraction here.
      }
  | (i, h) <- zip [0 ..] holes
  ]

-- | holeLabel: how a resolved hole is named in a sentence — the position first,
-- because that is the handle to reuse, with the index it resolved to alongside.
--
-- 'AgdaMCP.Holes.describeHole' is the same facts as a list entry
-- (@index 0 at line 22, column 5@); this is the prose form that reads correctly
-- inside a verdict's patch note or a timeout message.
holeLabel :: LiterateFlavour -> Text -> Int -> Text
holeLabel flav src i = case drop i (findHoles flav src) of
  (h : _) -> "the hole at line " <> T.pack (show (hsLine h))
               <> ", column " <> T.pack (show (hsCol h))
               <> " (index " <> T.pack (show i) <> ")"
  []      -> "hole index " <> T.pack (show i)


-- | timeoutDiagnostic: the timeout rendered as an ordinary error diagnostic, so
-- callers that already walk @diagnostics@ see it without special-casing the
-- @timedOut@ flag.  It is ours rather than Agda's, so it carries no code,
-- position, or payload; 'plainDiagnostic' is exactly that shape.
timeoutDiagnostic :: AgdaConfig -> Diagnostic
timeoutDiagnostic cfg = plainDiagnostic DiagError (timeoutMessage cfg)


-- | ensureDebugImport: ensure @open import AgdaDojang.Debug@ is in scope at the top
-- level (best-effort).
--
-- The @reportGoalCtx@ macro get_goal injects lives in @AgdaDojang.Debug@; a library
-- file being inspected will not normally import it.  If the top-level module already
-- imports it this is a no-op; otherwise the import is inserted immediately after the
-- module header; i.e. after the header's closing @where@, which may be several lines
-- below the @module@ keyword when the module is parameterised (common in agda-algebras).
-- agda-dojang is on the library path (@-l agda-dojang@), so the import resolves.
--
-- Literate and lexical awareness (issues #71/#73/#100): all line scans run over the
-- code-only view of the source ('codeOnly'), which blanks literate prose, comment,
-- and pragma text, so a line that happens to start with @module@ (or mention the
-- import) without being code can neither misplace the injection nor suppress it; the
-- header is found inside a code region, where the inserted line is Agda-visible.  The
-- import also inherits the header line's indentation, which keeps it inside
-- indentation-delimited code blocks (@.lagda.rst@); an unindented insert there would
-- terminate the block.  Masking preserves the line structure, so line indices found on
-- the masked text splice correctly into the original.
--
-- The "already imported?" scan is restricted to the *top-level* prelude — the lines
-- after the top-level module header, up to the first nested @module@ — so an import
-- inside a nested module (which does not bring names into the surrounding scope) does
-- not suppress injection.  Both that scan and the header search look at real
-- import/module lines (not mere substrings), so a passing mention of @AgdaDojang.Debug@
-- or @module@ in prose or in a comment neither suppresses the injection nor misplaces
-- it.  When no @module … where@ header is found the source is returned unchanged
-- (get_goal then surfaces the resulting scope error), so injection is best-effort, not
-- guaranteed.
ensureDebugImport :: LiterateFlavour -> Text -> Text
ensureDebugImport flav src =
  case moduleHeaderSpan codeLs of
    Nothing -> src   -- no top-level module header found; leave as-is (best-effort)
    Just (hdrLine, afterHdr)
      | any isDebugImportLine (takeWhile (not . opensModule) (drop afterHdr codeLs)) -> src
      | otherwise ->
          let indent          = T.takeWhile isIndentChar (codeLs !! hdrLine)
              (before, after) = splitAt afterHdr (T.lines src)
          in  T.unlines (before <> [indent <> "open import AgdaDojang.Debug"] <> after)
  where
    codeLs = T.lines (codeOnly flav src)

    isIndentChar c = c == ' ' || c == '\t'

    -- A genuine import of the module: the first token is an import-introducing
    -- keyword, @import@ is present, and @AgdaDojang.Debug@ appears as a whole module
    -- token; so neither an inline @-- … AgdaDojang.Debug@ trailer (blanked before the
    -- scan) nor a longer name such as @AgdaDojang.Debug.Extra@ is mistaken for the
    -- import.
    isDebugImportLine ln =
      case T.words ln of
        ws@(w : _) -> w `elem` ["import", "open", "private"]
                   && "import"           `elem` ws
                   && "AgdaDojang.Debug"  `elem` ws
        []         -> False

-- | opensModule: does this (code-only) line open a @module@ declaration?  The keyword
-- must stand as the line's first token, so a definition named @moduleAxioms@ is not a
-- header.  A nested @module …@ line also ends the top-level prelude: imports below it
-- are not in the surrounding scope, so they must not count as "already imported".
opensModule :: Text -> Bool
opensModule ln = case T.words ln of
  (w : _) -> w == "module"
  []      -> False

-- | moduleHeaderSpan: locate the top-level module header in code-only source lines
-- ('codeOnly').  Returns the 0-based index of the @module@ line and the index just
-- past the header's closing line — the first subsequent line carrying a standalone
-- @where@ token (they may be the same line, or several apart for a parameterised
-- module).  Returns @Nothing@ if no header is found.
moduleHeaderSpan :: [Text] -> Maybe (Int, Int)
moduleHeaderSpan ls = do
  i    <- findIndex opensModule ls
  jRel <- findIndex (\l -> "where" `elem` T.words l) (drop i ls)
  pure (i, i + jRel + 1)

-- | moduleNameOf: the declared top-level module name, parsed from the @module …@
-- header line of the code-only view of the source ('codeOnly').  This is the
-- *declared* name (e.g. @FLRP.Bridge@) not the file's base name, which would mangle a
-- hierarchical module to its last segment and strip only one extension from a literate
-- @.lagda.md@ file.
--
-- Reading the code-only view is what makes the answer the /declared/ name rather than
-- the first thing in the file that reads like a header: the flavour blanks literate
-- prose discussing module structure, and the lexical scan blanks a commented-out header
-- (issue #100).  Returns @Nothing@ when the file declares no module.
moduleNameOf :: LiterateFlavour -> Text -> Maybe Text
moduleNameOf flav src = do
  hdr <- find opensModule (T.lines (codeOnly flav src))
  case T.words hdr of
    -- 'opensModule' pins the first token as the keyword, so the second is the name.
    (_ : name : _) -> Just name
    _              -> Nothing


-- | errorTagsOf: every bracketed error name in Agda's output, in order of
-- appearance.  Agda (≥ 2.6.4) prints one @…: error: [TagName]@ header line per
-- error; warning headers say @warning: [TagName]@ and are deliberately not
-- collected; a warning never flips a fill verdict.
errorTagsOf :: Text -> [Text]
errorTagsOf out =
  [ tag
  | ln <- T.lines out
  , let (_, rest) = T.breakOn marker ln
  , not (T.null rest)
  , let tag = T.takeWhile (/= ']') (T.drop (T.length marker) rest)
  , not (T.null tag)
  ]
  where
    marker = "error: ["

-- | onlyOpenHoleErrors: does a failed typecheck fail /only/ because of open
-- holes?
--
-- Interaction metas are always visible holes in the source — the file's other,
-- still-open holes, or new sub-holes the candidate itself introduced (a
-- successful refinement, per the tool contract).  So a non-zero exit is
-- attributable to open holes exactly when every reported error is
-- @[UnsolvedInteractionMetas]@.  Anything else — @[UnsolvedMetaVariables]@,
-- @[UnsolvedConstraints]@, a scope or type error — is a defect the strict gate
-- (@agda \<file\>@) would report, and calling it ok is the trust failure of
-- issue #69: a candidate that "typechecks" per fill_hole yet fails the build.
--
-- This replaces an earlier tag /blacklist/, which reported ok whenever an open
-- hole's interaction metas appeared alongside an unlisted error class (e.g.
-- [UnsolvedMetaVariables] from an implicit nothing constrains).  As a whitelist,
-- unrecognized error classes fail closed, including a failure whose output
-- carries no parsable error header at all.
onlyOpenHoleErrors :: Text -> Bool
onlyOpenHoleErrors combined =
  case errorTagsOf combined of
    []   -> False
    tags -> all (== "UnsolvedInteractionMetas") tags
