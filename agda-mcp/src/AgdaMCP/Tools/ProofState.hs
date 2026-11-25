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
--     naming the file's holes, never a guess at the nearest one, except in a
--     file with exactly one hole, where a position on its line or no address
--     at all reaches it (issue #201), and both answers say which hole they
--     used and how (@addressed@).  Because
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
--     when a goal comes back and Agda named no module, which in practice means a
--     client whose flags include @--trace-imports=0@: that silences the progress
--     line while the goal markers still arrive.  The other ways Agda can decline
--     to say do not reach this field at all — a parse error, a header that does
--     not match its file name, or a timeout ends the call as a 'Left', and a
--     failure carries no @module@ (for the mismatch, Agda's own message names
--     both the module it found and the file it wanted, and that message is what
--     the failure reports).  So the fallback keeps a /successful/ answer
--     complete; it is not a diagnosis channel.  This is
--     the project's own thesis applied to its implementation: where Agda can
--     answer, ask Agda; the scan is the pre-flight approximation, not the
--     authority.  ('AgdaMCP.Agda.agdaModuleNameOf' reads the line;
--     'AgdaMCP.Tools.CheckProject' has read the same one since #78.)
--
--   Design note: every line scan reads the code-only view (issues #73, #100).
--     A source file's raw text carries things that look like Agda and are not: a
--     literate prose paragraph opening with @module@, a commented-out
--     declaration, the embedded Haskell of a @{-# FOREIGN GHC … #-}@ pragma, or
--     a declaration-shaped line sitting inside a @{! … !}@ hole, which Agda
--     lexes as one token and never parses.
--     'ensureDebugImport' and 'moduleNameOf' therefore scan
--     'AgdaMCP.Holes.codeOnly' (the source with prose, comments, and pragmas
--     blanked, a leading byte-order mark left out, and every line and column
--     preserved), so the header they find is the header Agda finds, on line 1
--     of a marked file too, and a line index found there still splices into
--     the original text.  Scanning the raw source instead is what made get_goal
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
--     it ('runInPlace').  The original is captured and restored as raw bytes
--     ('Data.ByteString'), so the file is returned byte-for-byte even if Agda
--     errors or the call is interrupted; no encoding or newline round-trip is involved.
--
--   Design note: the file is written only over bytes the server knows (issue #136).
--     The server is not the file's only writer: an editor beside the agent saves
--     when its user does.  So 'runInPlace' writes the patched text only while the
--     file still holds the bytes this call read, and restores the original only
--     while the file still holds the patched text it wrote.  A file found
--     changed is left as the other writer left it, and the call fails
--     ('AgdaMCP.Types.FailFileChanged') without a verdict, since Agda may have
--     read either text.  Until #136 the restore was unconditional, and a save
--     made during a check was overwritten by it.  The guard narrows the time
--     in which a save can be lost from the whole check to the instant between
--     a comparison and the write after it (measured: tenths of a millisecond);
--     it does not close it, and 'runInPlace' says why nothing here can.
--
--   Design note: fill_hole can leave a candidate in the file, or answer the
--   edit (issue #136).
--     By default it restores the file, as it always has, and its answer is what
--     it was.  @apply: true@ keeps the candidate when, and only when, its status
--     is ok and the file still holds the bytes the server wrote; the answer's
--     @applied@ says which happened.  @patch: true@ adds the edit that was
--     checked ('AgdaMCP.Patch.textPatch'), on every status, for a client that
--     applies it to a text of its own: an editor changes its buffer, not the
--     file.  The candidate is spliced as it was sent, with nothing added
--     ('AgdaMCP.Holes.spliceSpan'), so what is checked, what is written, and
--     what the patch says are one text.

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
  , unexplainedFailureTail
  , InPlaceEnd (..)
  , InPlaceOps (..)
  , runInPlace
  , runInPlaceWith
  ) where

import Control.Applicative ((<|>))
import Control.Exception (mask, onException, uninterruptibleMask_)
import qualified Data.ByteString as BS
import GHC.Clock (getMonotonicTimeNSec)
import Data.List (find, findIndex)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

import AgdaMCP.Agda
  ( AgdaConfig, AgdaResult (..), agdaFlags, agdaModuleNameOf
  , checkedFromSourceOf, debugLog, parseGoalContext, reportExpr, runAgda
  , timeoutMessage
  )
import AgdaMCP.Diagnostics
  ( attachUnsolvedMetas, capDiagnostics, parseDiagnostics )
import AgdaMCP.Digest (sourceDigest)
import AgdaMCP.Holes
  ( HoleSpan (..), LiterateFlavour, ResolvedHole (..), codeOnly, findHoles
  , flavourOf, injectReportExpr, resolveHoleRef, spliceSpan
  )
import AgdaMCP.Patch (textPatch)
import AgdaMCP.Path (readRegularFile, withSourceFile)
import AgdaMCP.Interaction
  ( GoalContext (..), GoalCtxEntry (..), InteractionLanes, IPoint (..)
  , IRange (..), LaneEvent (..), LaneFailure (..), LaneGoal (..)
  , LaneMeta (..), LoadReport (..), LoadedInfo (..), cmdGoalTypeContext
  , ensureLoaded, goalContextOf, peekLoadedGoals, runQuery, withLane
  )
import AgdaMCP.Project
  ( fileDirIncludeFlags, projectExtraFlags, resolveProject, withEffectiveFlags )
import AgdaMCP.Tools.CheckProject (outputTailOf)
import AgdaMCP.Tools.LiveQueries
  ( interactionFailure, laneCommandEcho, laneEchoFrom, pointForHole )
import AgdaMCP.Types

-- ---------------------------------------------------------------------------
-- get_goal
-- ---------------------------------------------------------------------------

-- | handleGetGoal: inspect goal type and local context at the addressed hole.
--
-- The preferred path is the interaction lane (issue #108): resolve the
-- 'HoleRef' against the source (issue #79), then 'laneGoal' loads the file
-- in the per-root child (reused when unchanged), verifies the addressed
-- hole against Agda's announced interaction point by coordinates, and asks
-- @Cmd_goal_type_context@ — no file mutation, and the response says
-- @source: "interaction-lane"@.
--
-- 'injectedGoal' is the fallback (@source: "injected-macro"@), used when the
-- lane cannot serve (see 'laneGoal' for the exact cases).  Its mechanism is
-- the original one:
--
-- 1. Ensure @open import AgdaDojang.Debug@ is in scope (inject it if absent)
--    so the @reportGoalCtx@ macro resolves.
-- 2. Replace the hole with @reportGoalCtx ?@.
-- 3. Typecheck the patched file IN PLACE (restoring the original afterwards).
-- 4. Parse the AGDADOJANG_REQ_BEGIN/END block from Agda's output.
-- 5. Return structured (goal, context).
--
-- Resolution before injection is deliberate.  The caller's position is a
-- position in the file /as it stands/, while the import injection shifts every
-- line below the module header down by one; resolving first turns the position
-- into an index, which the injection cannot disturb because an import line
-- introduces no holes.
--
-- Failures are 'ToolFailure' rather than bare 'Text' because this is the one
-- proof-state tool whose timeout cannot ride inside a success-shaped response —
-- there is no goal to report — and the measurements the call did produce
-- (@elapsedMs@, the cache signal) must not be dropped with it (issue #77).
handleGetGoal
  :: InteractionLanes -> AgdaConfig -> GetGoalParams
  -> IO (Either ToolFailure GoalInfo)
handleGetGoal lanes cfg0 params =
  withSourceFile (ggFilePath params) $ \absPath origBytes src ->
    withProject cfg0 absPath $ \pc cfg ->
        case resolveHoleRef absPath (flavourOf absPath) src (ggHole params) of
          Left miss -> pure (Left (FailMessage miss))
          Right rh -> do
            -- Whichever path answers, the answer names the hole it is for and
            -- how the address reached it (issue #201).
            let idx         = rhIndex rh
                withAddress = fmap (\gi -> gi { giAddressed = Just (addressedOf rh) })
            -- The lane first (issue #108): Agda's own goal display, no file
            -- mutation, answered from the warm child when one serves this
            -- root.  Falls back to the injection below whenever the lane
            -- cannot answer — except on a lane timeout, which is surfaced
            -- rather than silently doubling the call's bound with a second
            -- full run.
            viaLane <- laneGoal lanes cfg pc absPath src (ggReload params)
                         (ggRewrite params) idx
            case viaLane of
              Right (Just info) -> pure (withAddress (Right info))
              Left tf           -> pure (Left tf)
              Right Nothing     ->
                withAddress <$> injectedGoal cfg pc absPath origBytes src idx

-- | injectedGoal: the original reporting-macro mechanism, now the fallback
-- path of @get_goal@ (issue #108) — unchanged in behavior, and the only path
-- that can report binder visibility.
injectedGoal
  :: AgdaConfig -> ProjectContext -> FilePath -> BS.ByteString -> Text -> Int
  -> IO (Either ToolFailure GoalInfo)
injectedGoal cfg pc absPath origBytes src idx =
  case injectReportExpr (reportExpr cfg) (flavourOf absPath) idx
         (ensureDebugImport (flavourOf absPath) src) of
    -- Unreachable in practice: 'resolveHoleRef' validated the index
    -- against the same scan, and the injected import adds no holes.
    Nothing -> pure . Left . FailMessage $
      "Could not splice the reporting macro over " <> label
      <> " in " <> T.pack absPath
    Just patched -> do
      -- The macro is never kept: the file is restored, unless another writer
      -- changed it under the check, and then there is no goal to report,
      -- because the text Agda read is not known (issue #136).
      ran <- runInPlace cfg absPath origBytes (TE.encodeUtf8 patched) (const False)
      case ran of
        Left changed      -> pure (Left (FailFileChanged changed))
        Right (result, _) -> reportFrom result
  where
    label = holeLabel (flavourOf absPath) src idx

    reportFrom result = do
      -- DEBUG: show what Agda actually returned
      debugLog cfg $ "get_goal: exit=" <> T.pack (show (arExitCode result))
        <> " timedOut=" <> T.pack (show (arTimedOut result))
        <> " elapsedMs=" <> T.pack (show (arElapsedMs result))
      debugLog cfg $ "get_goal stdout: " <> T.take 500 (arStdout result)
      debugLog cfg $ "get_goal stderr: " <> T.take 500 (arStderr result)
      -- Agda may emit markers on stdout or stderr; check both.
      let combined = arStdout result <> "\n" <> arStderr result
          verdict  = patchedVerdict result goalVerdictMeaning
            (label <> " replaced by '" <> reportExpr cfg <> " ?'") restoredNote
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
              , giSource  = Just "injected-macro"
              , giLane    = Nothing
              , giAddressed = Nothing
              -- The macro prints @inferType >=> normalise@, whatever
              -- the call asked for, so a caller that asked for
              -- another mode can see that it did not get it (#248).
              , giRewrite = Just Normalised
              }


-- | laneGoal: try to answer @get_goal@ from the interaction lane.
--
-- @Right (Just info)@ is a complete answer; @Right Nothing@ means the lane
-- cannot serve this call and the injection fallback should run — a load
-- failure (the injection will report it as it always has), a crashed or
-- unspawnable child, a shutdown-latched registry, or a shape mismatch
-- between the lexical hole index and the announced interaction points.
-- @Left@ is reserved for the one case where falling back would be worse
-- than failing: a lane timeout has consumed the call's bound, and a second
-- full run behind it would double what the contract promises, so it
-- surfaces as the same structured failure the live-query tools raise.
--
-- The hole index is the lexical scan's (already validated by
-- 'resolveHoleRef'), and 'pointForHole' holds the point at that index to the
-- scanned hole's coordinates, which covers the day the two enumerations
-- disagree, by declining rather than answering about the wrong hole.
--
-- The display mode is the caller's @rewrite@ (issue #248), and the answer
-- reports the mode Agda says it printed in, falling back to the one sent.
laneGoal
  :: InteractionLanes -> AgdaConfig -> ProjectContext -> FilePath -> Text
  -> Bool -> Rewrite -> Int -> IO (Either ToolFailure (Maybe GoalInfo))
laneGoal lanes cfg pc absPath src reload rw idx = do
  startNs <- getMonotonicTimeNSec
  out <- withLane lanes cfg (pcRoot pc) $ \lh -> do
    loaded <- ensureLoaded lh reload absPath (agdaFlags cfg)
    case loaded of
      Left lf  -> pure (Left lf)
      Right lr -> case lrOutcome lr of
        Left _   -> pure (Right Nothing)
        -- The selected point must BE the addressed hole, not merely exist;
        -- any mismatch declines to the fallback.
        Right li -> case pointForHole (flavourOf absPath) src idx (liPoints li) of
          Nothing -> pure (Right Nothing)
          Just p  -> do
            rs <- runQuery lh absPath (cmdGoalTypeContext rw (ipId p))
            case rs of
              Left lf     -> pure (Left lf)
              Right resps -> case goalContextOf resps of
                Nothing -> pure (Right Nothing)
                Just gc -> do
                  lane  <- laneEchoFrom (pcRoot pc) lh lr
                  echo  <- laneCommandEcho cfg
                  endNs <- getMonotonicTimeNSec
                  pure . Right . Just $ GoalInfo
                    { giGoal    = gcType gc
                    , giContext =
                        [ CtxEntry
                            { ctxName       = geName e
                            , ctxType       = geBinding e
                            , ctxVisibility = Nothing
                            , ctxIndex      = Nothing
                            }
                        | e <- gcEntries gc ]
                    -- Agda's announced name, stored at load time so even a
                    -- reused load knows it; the declared name is the same
                    -- fallback the injection path uses (issue #100).
                    , giModule  = liModule li
                                    <|> moduleNameOf (flavourOf absPath) src
                    , giElapsedMs         =
                        Just (fromIntegral ((endNs - startNs) `div` 1_000_000))
                      -- Absent when the per-load argv muted Agda's progress
                      -- channel: the load's own evidence for this field is
                      -- exactly what --trace-imports=0 silences (issue #114).
                    , giCheckedFromSource = lrCheckedFromSource lr
                    , giVerdict = Nothing
                    , giCommand = Just echo
                    , giProject = Just pc
                    , giSource  = Just "interaction-lane"
                    , giLane    = Just lane
                    , giAddressed = Nothing
                    , giRewrite = gcRewrite gc <|> Just rw
                    }
  case out of
    Right (Right mInfo) -> pure (Right mInfo)
    Right (Left lf)     -> surfaceOrDecline startNs lf
    Left lf             -> surfaceOrDecline startNs lf
  where
    surfaceOrDecline startNs lf
      | lfEvent lf == LaneTimeout =
          Left . FailInteraction <$> interactionFailure pc cfg startNs lf
      | otherwise = pure (Right Nothing)

-- ---------------------------------------------------------------------------
-- fill_hole
-- ---------------------------------------------------------------------------

-- | handleFillHole: try substituting @candidate@ into the addressed hole and
-- typecheck.
--
-- 1. Read source, resolve the caller's 'HoleRef' (a @(line, column)@ position
--    or a @holeIndex@), substitute the candidate over that hole's span, as it
--    was sent and with nothing added.
-- 2. Typecheck the patched file IN PLACE.
-- 3. Exit 0 → ok.  A non-zero exit is ok only when 'onlyOpenHoleErrors' holds,
--    i.e. every reported error is an open hole's @[UnsolvedInteractionMetas]@;
--    a candidate that leaves @[UnsolvedMetaVariables]@ or
--    @[UnsolvedConstraints]@ behind is a type error (issue #69).
-- 4. Restore the file, unless the call passed @apply: true@ and the status is
--    ok: then the candidate stays, and @applied@ says so (issue #136).  Either
--    is done only while the file still holds the bytes written in step 2; a
--    file another writer changed is left alone and the call fails without a
--    verdict ('runInPlace').
-- 5. Answer with the hole list of the patched source, so a client that keeps
--    the candidate re-anchors on positions without a second call (issue #79).
--    Those are the holes of the file /as this candidate leaves it/: the file's
--    own holes once it is applied, and until then the holes it will have when
--    the candidate is written back.
-- 6. With @patch: true@, add the edit that was checked, on every status: it
--    says what was tried, and @status@ says what Agda made of it (issue #136).
handleFillHole :: AgdaConfig -> FillHoleParams -> IO (Either ToolFailure FillResult)
handleFillHole cfg0 params =
  withSourceFile (fhFilePath params) $ \absPath origBytes src ->
    withProject cfg0 absPath $ \pc cfg ->
        case resolveHoleRef absPath (flavourOf absPath) src (fhHole params) of
          Left miss -> pure (Left (FailMessage miss))
          Right rh -> do
            let hole         = rhSpan rh
                label        = holeLabel (flavourOf absPath) src (rhIndex rh)
                candidate    = fhCandidate params
                -- One splice serves the check, the apply, and the patch: the
                -- resolved span of the text just read, replaced by the
                -- candidate as sent.
                patched      = spliceSpan hole candidate src
                patchedBytes = TE.encodeUtf8 patched
                -- Agda 2.8.0 emits some errors on stdout; check both streams.
                combinedOf result = arStdout result <> "\n" <> arStderr result
                -- Verdict (issues #69, #77).  The timeout arm comes first: a killed
                -- process exits on its signal (-2 SIGINT, -15 SIGTERM), which is
                -- otherwise indistinguishable from an ordinary failure, and calling
                -- an unfinished typecheck a type_error would be a false verdict.
                -- Below it, a non-zero exit is ok only when every reported error is
                -- an open hole's [UnsolvedInteractionMetas]; 'onlyOpenHoleErrors'
                -- explains why this is a whitelist.  An exit code of -1 means the
                -- agda binary could not be run at all.
                statusOf result
                  | arTimedOut result                       = FillTimeout
                  | arExitCode result == 0                  = FillOk
                  | arExitCode result == (-1)               = FillCrash
                  | onlyOpenHoleErrors (combinedOf result)  = FillOk
                  | otherwise                               = FillTypeError
                -- An apply keeps an accepted candidate and nothing else: a
                -- type error, a timeout and a crash restore the file.
                keeps result = fhApply params && statusOf result == FillOk
            ran <- runInPlace cfg absPath origBytes patchedBytes keeps
            case ran of
              Left changed -> pure (Left (FailFileChanged changed))
              Right (result, end) -> do
                let status = statusOf result
                    msg
                      | arTimedOut result = Just (timeoutMessage cfg)
                      | status == FillOk  = Nothing
                      | otherwise         = Just (T.take 2000 (combinedOf result))
                    -- The holes left in the patched source (every Agda hole
                    -- syntax, code regions only): the re-anchoring payload, of
                    -- which remainingHoles is the count.
                    remaining = holeInfosOf (findHoles (flavourOf absPath) patched)
                pure . Right $ FillResult
                  { frStatus    = status
                  , frCandidate = candidate
                  , frAddressed = addressedOf rh
                  , frMessage   = msg
                  , frRemainingHoles = Just (length remaining)
                  , frHoles     = remaining
                  , frElapsedMs = arElapsedMs result
                  , frCheckedFromSource = checkedFromSourceOf result
                  , frVerdict   = patchedVerdict result fillVerdictMeaning
                      (label <> " replaced by the candidate")
                      (case end of
                         Restored -> restoredNote
                         Kept     -> "the candidate was left in the file: apply")
                  , frCommand   = arCommand result
                  , frProject   = pc
                  , frApplied   = if fhApply params then Just (end == Kept) else Nothing
                  , frPatch     =
                      if fhPatch params
                        then Just (textPatch absPath origBytes src
                                     (hsStart hole) (hsEnd hole) candidate patchedBytes)
                        else Nothing
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
handleCheckFile
  :: InteractionLanes -> AgdaConfig -> CheckFileParams
  -> IO (Either ToolFailure FileCheckResult)
handleCheckFile lanes cfg0 params =
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
          parsed   = parseDiagnostics combined
          allDiags = [ timeoutDiagnostic cfg | arTimedOut result ] <> parsed
          (diags, total) = capDiagnostics (cfMaxDiagnostics params) allDiags
          success = arExitCode result == 0 && not (arTimedOut result)
      -- Fill each hole's goal type from the interaction lane when — and only
      -- when — a lane already holds a matching load of these very bytes
      -- (issue #108), and from the same peek give the unsolved-meta
      -- diagnostics each meta's name and type (issue #115).  A peek, never a
      -- spawn or a load: the batch tools' cost model and verdict source are
      -- untouched, and the placeholder "?" and the prose-only meta payload
      -- remain the answer when no warm lane can vouch for more.
      lanePeek <- peekLoadedGoals lanes cfg (pcRoot pc) absPath (agdaFlags cfg)
      let holes = fillHoleGoals (liGoals <$> lanePeek)
                    (holeInfosOf (findHoles (flavourOf absPath) src))
      pure . Right $ FileCheckResult
        { fcrSuccess     = success
        , fcrDiagnostics = attachUnsolvedMetas (involvedMetasOf lanePeek) diags
        , fcrDiagnosticsTotal = total
        , fcrHolesCount  = length holes
        , fcrHoles       = holes
        , fcrTimedOut    = arTimedOut result
        , fcrElapsedMs   = arElapsedMs result
        , fcrCheckedFromSource = checkedFromSourceOf result
        , fcrOutputTail  = unexplainedFailureTail result parsed combined
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
handleGetDiagnostics
  :: InteractionLanes -> AgdaConfig -> GetDiagnosticsParams
  -> IO (Either ToolFailure DiagnosticsResult)
handleGetDiagnostics lanes cfg0 params =
  withSourceFile (gdFilePath params) $ \absPath _bytes src ->
    withProject cfg0 absPath $ \pc cfg -> do
      result <- runAgda cfg absPath
      let combined = arStdout result <> "\n" <> arStderr result
          -- As in check_file: a timeout is itself an error diagnostic, so it lands in
          -- both the list and the error count rather than vanishing into a summary
          -- that reads "0 errors" because Agda never finished reporting any.
          parsed   = parseDiagnostics combined
          allDiags = [ timeoutDiagnostic cfg | arTimedOut result ] <> parsed
          (diags, total) = capDiagnostics (gdMaxDiagnostics params) allDiags
          countOf sev = length (filter ((== sev) . diagSeverity) allDiags)
      -- The same warm-lane peek as check_file (issues #108 and #115).
      lanePeek <- peekLoadedGoals lanes cfg (pcRoot pc) absPath (agdaFlags cfg)
      pure . Right $ DiagnosticsResult
        { drFilePath = gdFilePath params
        , drErrors   = countOf DiagError
        , drWarnings = countOf DiagWarning
        , drHoles    = fillHoleGoals (liGoals <$> lanePeek)
                         (holeInfosOf (findHoles (flavourOf absPath) src))
        , drSuccess  = arExitCode result == 0 && not (arTimedOut result)
        , drDiagnostics = attachUnsolvedMetas (involvedMetasOf lanePeek) diags
        , drDiagnosticsTotal = total
        , drTimedOut = arTimedOut result
        , drElapsedMs = arElapsedMs result
        , drCheckedFromSource = checkedFromSourceOf result
          -- As in check_file (issue #346): the rule lives in one function, so
          -- the two tools cannot disagree on when the tail is sent.
        , drOutputTail = unexplainedFailureTail result parsed combined
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
-- command, together with what became of the file afterwards: 'restoredNote',
-- or, for a candidate an apply kept, that it was left there (issue #136).
patchedVerdict :: AgdaResult -> Text -> Text -> Text -> Verdict
patchedVerdict result meaning patchNote afterNote = Verdict
  { vEquivalentTo = commandLine (arCommand result)
      <> ", run against that file with " <> patchNote
      <> " (" <> afterNote <> ")"
  , vMeaning      = meaning
  , vExitCode     = arExitCode result
  }

-- | restoredNote: what a verdict says of a file that was put back.
restoredNote :: Text
restoredNote = "the file on disk is restored afterwards, byte for byte"

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

-- | What became of the file at the end of an in-place check.
data InPlaceEnd
  = Restored  -- ^ The original bytes were written back.
  | Kept      -- ^ The patched bytes were left in the file (an apply).
  deriving (Eq, Show)

-- | runInPlace: typecheck a patched version of a file at its real path, and
-- afterwards restore the original or keep the patch, writing only over bytes
-- the server knows (issue #136).
--
-- Writes @patchedBytes@ over @absPath@, runs Agda there on the flags
-- 'withProject' assembled — the caller's @-l \<lib\>@, hence the library's src root,
-- plus whatever resolution added, plus @-i \<dir-of-file\>@ — then restores
-- @originalBytes@, unless @keep@ says of Agda's result that the patch stays.
-- It adds no flags of its own, so what the response echoes under
-- @command@ and @project@ is exactly what ran here too.  Checking at the real
-- path (rather than a scratch copy) is what lets hierarchically-named library
-- modules resolve; see the module header and issue #66.
--
-- The file has other writers (an editor saves when its user does), so each
-- write is made only while the file holds what this call last knew it to hold:
--
--   * the patched bytes go over the file only if it still holds
--     @originalBytes@, the bytes this call read; otherwise nothing is written,
--     Agda is not run, and the answer is 'ChangedBeforeCheck';
--   * the restore, and equally the decision to keep, happens only if the file
--     still holds @patchedBytes@; otherwise the file is left as it was found
--     and the answer is 'ChangedDuringCheck', with no result: Agda may have
--     read the patched text or the other writer's, and nothing here can tell
--     which.  A file that can no longer be read at all (removed, replaced by
--     something that is not a regular file) is left alone the same way.
--
-- What this narrows and what it does not: a save made at any time during
-- Agda's run, which is seconds to minutes long, is now seen and kept.  The
-- comparison and the write that follows it are still separate system calls
-- (a read, then a truncation and a write), so a save that lands between them
-- is overwritten as before.  Traced on the server over 30 calls (strace,
-- ext4, 2026-11-24), the end of the read and the truncation were 0.12 to
-- 0.51 ms apart before the check (median 0.21) and 0.12 to 2.5 ms apart at
-- the settlement (median 0.23), against 0.10 to 0.14 s between the two
-- writes on that small module, the tracing included.  Nothing here can close
-- it against a writer that takes no lock: an
-- advisory lock binds only the writers that ask for it, and an editor does
-- not; and replacing the file by a rename compares nothing either, changes
-- the file's identity, and loses a save written through a descriptor an
-- editor already holds.  Nor are two servers kept apart: one that reads the
-- file during another's check takes the patched text for the original, and
-- restores to it (issue #370).
--
-- Every write goes through 'Data.ByteString', and every path that returns
-- ends in the settlement above: after a clean run, a timeout (which
-- 'AgdaMCP.Agda.runAgda' reports as a /value/, 'arTimedOut', after it has
-- killed and reaped the subprocess; issue #77), and an exception thrown at
-- the waiting thread alike, so a call that is cancelled never keeps a patch
-- (the suite cancels one while Agda runs, one while the patch is being
-- written, and one during the settlement).  The whole call runs under
-- 'mask', and the two steps that touch the file (the comparison with the
-- patch write, and the settlement) under 'uninterruptibleMask_', because
-- 'mask' alone does not hold an exception off a file operation that blocks:
-- GHC's @openFile@ makes an interruptible @open(2)@ under 'mask' and
-- delivers a pending exception when that call fails or is interrupted, which
-- it can be on a network or FUSE file system, and an exception taken inside
-- the settlement would end it before its write (Copilot's review of PR 371).
-- On ext4 and tmpfs that did not happen once: of 165,173 and 129,194
-- exceptions thrown at 200,000 masked read-then-write rounds on each, none
-- arrived inside a round (GHC 9.10.3, threaded, 2026-11-24).  So the suite
-- holds this through 'runInPlaceWith', with a read and a write that block.
-- The cost is that a read or a write that never returns cannot be cancelled.
--
-- What no handler reaches: a write that fails is not retried, its
-- 'IOException' goes to the caller, and since a write is a truncation and
-- then a write the file may be left short; and a process that is killed runs
-- no handler at all, so SIGTERM or SIGKILL during a check leaves the patched
-- text in the file, as it always has, while SIGINT, which the runtime raises
-- as an exception, restores (measured on the server before and after issue
-- #136; issue #370).
--
-- Only the file's /contents/ are restored, not its modification time: the restore write
-- deliberately leaves a fresh mtime.  That is intentional; a newer mtime forces Agda to
-- re-typecheck from the restored source on its next load under any interface-freshness
-- rule, whereas resetting mtime to the original (older) value could let Agda reuse an
-- @.agdai@ built from the transiently-patched content (e.g. a fill_hole candidate that
-- completed the module).  Editors that compare content, not mtime alone, will not prompt,
-- since the bytes are unchanged.  A kept patch is not written again, so the file
-- keeps the modification time of the write Agda read, and an interface Agda
-- wrote for it is an interface of the file as it stands.
runInPlace
  :: AgdaConfig
  -> FilePath
  -> BS.ByteString          -- ^ The file's bytes, as this call read them.
  -> BS.ByteString          -- ^ The patched bytes to check.
  -> (AgdaResult -> Bool)   -- ^ Keep the patched bytes after this result?
  -> IO (Either FileChanged (AgdaResult, InPlaceEnd))
runInPlace cfg absPath = runInPlaceWith InPlaceOps
  { -- The same guarded read the tools start with.
    ipoRead  = either (const Nothing) Just <$> readRegularFile "filePath" absPath
  , ipoWrite = BS.writeFile absPath
  , ipoCheck = runAgda cfg absPath
  } absPath

-- | What a guarded in-place check does to the world: it reads the file,
-- replaces its bytes, and runs Agda on it.
--
-- 'runInPlace' passes the real three.  The suite passes ones that record the
-- masking state they run in, and ones that block, because what
-- 'runInPlaceWith' promises about a cancellation that arrives while the file
-- is being read or written cannot be shown on a local file, whose reads and
-- writes do not block.
data InPlaceOps = InPlaceOps
  { ipoRead  :: IO (Maybe BS.ByteString)
    -- ^ The file's bytes now, or Nothing when it is no longer a readable
    --   regular file.
  , ipoWrite :: BS.ByteString -> IO ()
    -- ^ Replace the file's bytes.
  , ipoCheck :: IO AgdaResult
    -- ^ Run Agda on the file.
  }

-- | runInPlaceWith: 'runInPlace' over the given operations; see there for
-- the guard, and for why the two steps that touch the file cannot be
-- interrupted.
runInPlaceWith
  :: InPlaceOps
  -> FilePath               -- ^ The file, for the failure's text.
  -> BS.ByteString          -- ^ The file's bytes, as this call read them.
  -> BS.ByteString          -- ^ The patched bytes to check.
  -> (AgdaResult -> Bool)   -- ^ Keep the patched bytes after this result?
  -> IO (Either FileChanged (AgdaResult, InPlaceEnd))
runInPlaceWith ops absPath originalBytes patchedBytes keep = mask $ \unmask -> do
  -- An exception that arrives during this step is taken at 'unmask' below,
  -- inside the handler's reach, so a patch that was written is settled.
  written <- uninterruptibleMask_ $ do
    found <- ipoRead ops
    if found /= Just originalBytes
      then pure (Left (changed ChangedBeforeCheck originalBytes found))
      else Right () <$ ipoWrite ops patchedBytes
  case written of
    Left failure -> pure (Left failure)
    Right ()     -> do
      result  <- unmask (ipoCheck ops) `onException` settle False
      settled <- settle (keep result)
      pure ((,) result <$> settled)
  where
    -- An exception that arrives during the settlement is taken when the call
    -- leaves 'mask', after the file is as it should be.
    settle :: Bool -> IO (Either FileChanged InPlaceEnd)
    settle keepIt = uninterruptibleMask_ $ do
      now <- ipoRead ops
      if now /= Just patchedBytes
        then pure (Left (changed ChangedDuringCheck patchedBytes now))
        else if keepIt
          then pure (Right Kept)
          else Right Restored <$ ipoWrite ops originalBytes

    changed when expected found = FileChanged
      { fchFile     = absPath
      , fchWhen     = when
      , fchExpected = sourceDigest expected
      , fchFound    = sourceDigest <$> found
      }


-- | holeInfosOf: a scan's spans as the wire hole list — the one construction
-- behind @get_diagnostics@'s, @check_file@'s, and @fill_hole@'s @holes@ key, so
-- the three cannot describe holes differently (issue #79).
--
-- The goal is the cheap placeholder the shape has always carried: listing holes
-- costs one pure scan, whereas a real goal per hole costs one Agda run per hole.
-- | fillHoleGoals: replace hole-listing placeholders with the goal types a
-- warm lane holds for these bytes (issue #108).  Matching is by the hole's
-- starting (line, col), the coordinates the parity tests pin between the
-- lexical scan and Agda's interaction points; a hole the lane cannot vouch
-- for keeps the \"?\" placeholder.
fillHoleGoals :: Maybe [LaneGoal] -> [HoleInfo] -> [HoleInfo]
fillHoleGoals Nothing      hs = hs
fillHoleGoals (Just goals) hs = map fill hs
  where
    fill h = case [ lgType g
                  | g <- goals
                  , Just r <- [lgRange g]
                  , irLine r == hiLine h, irCol r == hiCol h
                  , not (T.null (lgType g)) ] of
      (t : _) -> h { hiGoal = t }
      []      -> h

-- | involvedMetasOf: a warm lane's unsolved metas in the wire shape the
-- diagnostics carry (issue #115) — the other half of the same peek
-- 'fillHoleGoals' reads, and the same silence when the peek declined.
--
-- The lane's own range type becomes the diagnostics' one so a client parses a
-- single range shape everywhere; both are 1-based line and column in the file
-- as written, so this is a re-labelling and not a conversion.
involvedMetasOf :: Maybe LoadedInfo -> [InvolvedMeta]
involvedMetasOf = maybe [] (map involvedMeta . liMetas)
  where
    involvedMeta m = InvolvedMeta
      { imName  = lmetaName m
      , imType  = lmetaType m
      , imRange = diagRangeOf <$> lmetaRange m
      }
    diagRangeOf r = DiagRange (irLine r) (irCol r) (irEndLine r) (irEndCol r)

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

-- | unexplainedFailureTail: the @outputTail@ of @check_file@ and
-- @get_diagnostics@ (issue #346), sent only when nothing else in the answer
-- says why the run failed.
--
-- The case it exists for is a process named as @--agda-bin@ that fails
-- without printing anything 'parseDiagnostics' recognizes: a launcher that
-- refuses (@scripts/agda-for-flake.sh@ exits 69 with one line naming the
-- cause), an Agda internal error (exit 154 and an @__IMPOSSIBLE__@ banner), a
-- missing shared library, a binary that could not be started at all ('runAgda'
-- puts the exception on stderr and reports exit -1).  Each of those used to
-- answer @success: false@, an exit code, and an empty list, and the model had
-- no word of why.  The tail is 'outputTailOf' of the same combined output the
-- parser read, so its bounds and shape are @check_project@'s.
--
-- Every other run answers as before, which keeps the answers of issue #184 at
-- their size:
--
--   * a success (exit 0, in time) has nothing to explain;
--   * a failure with at least one parsed diagnostic has its explanation in the
--     list.  The test is on what the parser found, before the @maxDiagnostics@
--     cap; the cap keeps at least one (zero means no limit), so the list a
--     caller sees is empty exactly when this one is;
--   * a timeout is decided here, as the issue asks: no tail.  The timeout
--     diagnostic already names the bound and what to do about it, and what a
--     killed run printed is where it got (Agda's @Checking@ lines, or the
--     launcher's @nix build@ progress on a cold key), not why it failed; it
--     would add up to 4,000 characters to an answer that is not silent.  The
--     launcher's nix output is the one place a tail could tell more (a build,
--     not a typecheck, ran out of time), and the diagnostic's advice, raise
--     @--timeout@, is right for both.
unexplainedFailureTail :: AgdaResult -> [Diagnostic] -> Text -> Maybe Text
unexplainedFailureTail result parsed combined
  | arExitCode result == 0 = Nothing
  | arTimedOut result      = Nothing
  | not (null parsed)      = Nothing
  | otherwise              = outputTailOf combined


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
-- import also inherits the indentation of the module's /body/, which keeps it inside
-- indentation-delimited code blocks (@.lagda.rst@) and, more generally, makes it a
-- layout sibling of the declarations it joins.  Masking preserves the line structure,
-- so line indices found on the masked text splice correctly into the original.
--
-- The "already imported?" scan is restricted to the *top-level* prelude — the lines
-- after the top-level module header, up to the first nested @module@ — so an import
-- inside a nested module (which does not bring names into the surrounding scope) does
-- not suppress injection.  Nor does an import-shaped line inside a hole: the
-- code-only view blanks holes, so a @{! open import AgdaDojang.Debug !}@ left in a
-- proof is hole text, not an import, and the injection still happens (it did not
-- before, and get_goal then failed with @reportGoalCtx@ out of scope).  Both that scan and the header search look at real
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
          let (before, after) = splitAt afterHdr (T.lines src)
          in  T.unlines
                (before <> [bodyIndent hdrLine afterHdr <> "open import AgdaDojang.Debug"] <> after)
  where
    codeLs = T.lines (codeOnly flav src)

    isIndentChar c = c == ' ' || c == '\t'

    -- The inserted line has to be a layout /sibling/ of the module's other
    -- declarations, so it takes the indentation of the first of them rather than the
    -- header's.  A header at column 1 whose body is indented is legal Agda, and an
    -- insert at column 1 there makes every existing declaration a continuation of the
    -- import: Agda answers @[ParseError]@ and get_goal fails on a file that checks
    -- fine (measured; Copilot's third review of PR 105).  Comment-only and prose lines
    -- are blank in the code-only view, so they cannot supply the indentation.  With no
    -- declaration to match — an empty module body — the header's own indentation is the
    -- only guess available, and it is the one that keeps the line inside an
    -- indentation-delimited code block.
    bodyIndent hdr afterHdr =
      case dropWhile (T.null . T.strip) (drop afterHdr codeLs) of
        (l : _) -> T.takeWhile isIndentChar l
        []      -> T.takeWhile isIndentChar (codeLs !! hdr)

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
