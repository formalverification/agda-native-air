-- | Interaction.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Interaction.hs
--
-- Description:
--   The interaction lane (issue #75): a persistent @agda --interaction-json@
--   child per resolved project root, serving read-only knowledge queries —
--   types, normal forms, name resolution, module exports — as structured data.
--
--   This module is the process and protocol layer only.  The tool handlers
--   live in AgdaMCP.Tools.LiveQueries; the wire protocol itself — framing,
--   escaping, command shapes, response kinds, and every gotcha the design
--   observes — is documented in docs/agda-mcp-interaction-lane.md, which was
--   probed against the pinned Agda 2.8.0 before this module was written.
--   Where behavior here looks arbitrary (the sentinel after every command,
--   the startup flush, the reload policy), that document holds the measured
--   reason.
--
--   The two-lane policy, restated where the second lane is implemented:
--   nothing in this module ever produces a build verdict.  Interaction mode
--   is tolerant — @Cmd_load@ SUCCEEDS on a file with open holes — so
--   check_file, check_project, and fill_hole keep reading batch @agda@'s
--   exit code, and the tools built on this lane say in their descriptions
--   that they inform and never decide.
--
--   Design notes, briefly (each is probed, none is assumed):
--
--   * One child per resolved project root ('AgdaMCP.Project' supplies the
--     root, per call, exactly as it does for the batch tools).  Since #103 a
--     server is routinely asked about foreign checkouts, so the registry is
--     a map of roots, not a slot.
--   * Requests are serialized per lane under an 'MVar'.  The registry is
--     safe for concurrent callers on distinct roots, but the stdio server
--     loop that drives it today is itself serial, so at most one request is
--     ever in flight — capability, not yet behavior.  Responses are read
--     line by line, keyed on the JSON @kind@ field, never on line position;
--     @JSON> @ prompt markers float mid-stream and are stripped wherever
--     they appear.
--   * After every command the lane sends @Cmd_show_version@ and collects
--     until that sentinel's unmistakable response.  Commands execute
--     strictly in order (a reader thread queues them for a single
--     executor), so everything before the sentinel belongs to the command.
--   * Every string embedded in an IOTCM line is a Haskell string literal;
--     'show' is the escaper.  A raw @\\x@ in an expression rejects the whole
--     line with a plain-text @cannot read:@ reply.
--   * A file is (re)loaded only on evidence: first sight, a path switch, a
--     changed (mtime, size) stamp, changed flags, a failed previous load, or
--     the client's own @reload: true@ (the escape hatch for a changed
--     dependency, which no stamp on the queried file can see).  A file with
--     open holes writes no interface, so an unconditional re-load would
--     re-typecheck the module on every query — the cost this lane exists to
--     remove.  The failure side of the policy is the reverse: a failed load
--     is retried on every request, so a fix in a dependency is noticed at
--     the first opportunity.
--   * A hung command is handled with the issue-#77 ladder
--     ('AgdaMCP.Agda.escalateAndReap') applied to the child's process group,
--     and the lane is respawned on next use.  A crashed or hung lane
--     surfaces as structured data ('LaneFailure'), never as a bare JSON-RPC
--     -32603 — the #101 lesson.
--   * An idle lane is shut down by closing its stdin, which Agda answers by
--     exiting cleanly (probed: rc 0 on EOF); a reaper thread sweeps on a
--     fixed cadence.  Server shutdown latches the registry closed and drains
--     every lane, waiting for any a request still holds.

{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData          #-}

module AgdaMCP.Interaction
  ( -- * The lane registry
    InteractionLanes
  , newInteractionLanes
  , shutdownLanes
  , laneIdleSeconds
    -- * Running requests against one root's lane
  , LaneHandle
  , withLane
  , ensureLoaded
  , runQuery
  , laneAgdaVersion
  , laneSentLines
  , laneWasSpawned
  , lanePidOf
    -- * Request outcomes
  , LaneFailure (..)
  , LaneEvent (..)
  , LoadReport (..)
  , LoadAction (..)
  , LoadedInfo (..)
    -- * Wire model (pure; exposed for testing)
  , IResponse (..)
  , IRange (..)
  , IPoint (..)
  , LaneGoal (..)
  , stripPrompts
  , parseResponseLine
  , errorMessageOf
  , interactionPointsOf
  , goalsOf
  , goalInfoOf
  , pointContaining
    -- * IOTCM construction (pure; exposed for testing)
  , iotcmLine
  , hsShow
  , hsShowList
  , cmdLoad
  , cmdInferToplevel
  , cmdInferAtGoal
  , cmdComputeToplevel
  , cmdComputeAtGoal
  , cmdWhyInScopeToplevel
  , cmdWhyInScopeAtGoal
  , cmdModuleContentsToplevel
  , cmdGoalTypeContext
  , cmdShowVersion
    -- * Provenance prose (pure; exposed for testing)
  , SrcLoc (..)
  , ProvenanceStep (..)
  , ScopeCandidate (..)
  , parseSrcLoc
  , parseWhyInScope
  , parseAmbiguousName
  , parseDidYouMean
  , errorCodeOf
  ) where

import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import Control.Concurrent.MVar
  (MVar, modifyMVar, newMVar, putMVar, readMVar, takeMVar, tryTakeMVar)
import Control.Exception
  ( AsyncException, IOException, SomeException, catch, fromException
  , mask, onException, throwIO, try
  )
import Control.Monad (forever)
import Data.Aeson (Value (..), decodeStrict')
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Char8 as BS8
import Data.IORef
  (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time.Clock (UTCTime)
import qualified Data.Vector as V
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import System.Directory (getFileSize, getModificationTime)
import System.FilePath (equalFilePath)
import System.IO (Handle, hClose, hFlush, hPutStrLn, hSetBinaryMode)
import System.Process
  ( CreateProcess (..), Pid, ProcessHandle, StdStream (..)
  , createProcess, getPid, getProcessExitCode, proc
  )
import System.Timeout (timeout)

import AgdaMCP.Agda (AgdaConfig (..), escalateAndReap, parseCheckingLine)


-- ---------------------------------------------------------------------------
-- Wire model
-- ---------------------------------------------------------------------------

-- | IResponse: one line of the child's stdout, classified by its @kind@.
--
-- The constructors cover what the lane acts on; everything else is kept as
-- 'IOther' (a JSON object of some other kind) or 'IUnreadable' (a non-JSON
-- line, such as the @cannot read:@ reply to a malformed IOTCM), so nothing
-- the child says is ever silently dropped from a diagnostic trail.
data IResponse
  = IDisplayInfo Text Value   -- ^ @DisplayInfo@: its @info.kind@ and @info@ object.
  | IInteractionPoints [IPoint]
  | IRunningInfo Text         -- ^ Progress prose (@Checking M (path).@).
  | IOther Text Value         -- ^ Any other JSON kind (Status, highlighting, …).
  | IUnreadable Text          -- ^ A line that was not JSON.
  deriving (Eq, Show)

-- | IRange: a source range in the coordinates of the file as written —
-- 1-based line and column, literate coordinates for literate files (probed on
-- LiterateMd: the interaction point sits exactly where 'AgdaMCP.Holes' puts
-- the hole).
data IRange = IRange
  { irLine    :: Int
  , irCol     :: Int
  , irEndLine :: Int
  , irEndCol  :: Int
  } deriving (Eq, Show)

-- | IPoint: one interaction point, as announced by @Cmd_load@'s terminal
-- @InteractionPoints@ response.  The range is optional on the wire; a
-- rangeless point cannot be addressed by position and is kept only so the
-- count stays honest.
data IPoint = IPoint
  { ipId    :: Int
  , ipRange :: Maybe IRange
  } deriving (Eq, Show)

-- | LaneGoal: one visible goal from @AllGoalsWarnings@ — an interaction point
-- together with the goal type Agda printed for it.  This is what lets a load
-- answer "what does each hole want" with no source mutation at all.
data LaneGoal = LaneGoal
  { lgId    :: Int
  , lgRange :: Maybe IRange
  , lgType  :: Text
  } deriving (Eq, Show)

-- | stripPrompts: remove every leading @JSON> @ marker from a line.
--
-- The marker is printed by the child's reader thread as it consumes input,
-- concurrently with the executor's output, so it can stand alone, prefix a
-- response, or stack; it carries no framing information (§ 2.1 of the design
-- document).
stripPrompts :: Text -> Text
stripPrompts t = case T.stripPrefix "JSON> " t of
  Just rest -> stripPrompts rest
  Nothing   -> t

-- | parseResponseLine: classify one stdout line.
--
-- A line that is empty after prompt stripping yields 'Nothing'; everything
-- else is some 'IResponse'.  The parse is keyed on the @kind@ field alone.
parseResponseLine :: Text -> Maybe IResponse
parseResponseLine raw =
  let line = stripPrompts raw
  in if T.null (T.strip line) then Nothing else Just (classify line)
  where
    classify line = case decodeStrict' (TE.encodeUtf8 line) of
      Just v@(Object o) -> case textField "kind" o of
        Just "DisplayInfo" ->
          case KM.lookup "info" o of
            Just info@(Object io) ->
              IDisplayInfo (fromMaybe "" (textField "kind" io)) info
            _ -> IOther "DisplayInfo" v
        Just "InteractionPoints" ->
          IInteractionPoints (pointsFrom (KM.lookup "interactionPoints" o))
        Just "RunningInfo" ->
          IRunningInfo (fromMaybe "" (textField "message" o))
        Just k  -> IOther k v
        Nothing -> IOther "" v
      _ -> IUnreadable line

    pointsFrom (Just (Array a)) = mapMaybe pointFrom (V.toList a)
    pointsFrom _                = []

    pointFrom (Object o) = do
      i <- intField "id" o
      pure (IPoint i (rangeField o))
    pointFrom _ = Nothing

-- | errorMessageOf: the message of a @DisplayInfo@/@Error@ response.
--
-- The observed shape is @info.error.message@; @info.message@ is accepted too,
-- so a formatting change degrades to a still-useful answer rather than to
-- silence.
errorMessageOf :: IResponse -> Maybe Text
errorMessageOf (IDisplayInfo "Error" (Object io)) =
  case KM.lookup "error" io of
    Just (Object eo) -> textField "message" eo
    _                -> textField "message" io
errorMessageOf _ = Nothing

-- | interactionPointsOf: the points of the first @InteractionPoints@ response
-- in a collection, if any.  Its presence is what marks a load as successful
-- (§ 2.4 of the design document); a failed load never emits one.
interactionPointsOf :: [IResponse] -> Maybe [IPoint]
interactionPointsOf rs = listToMaybe [ps | IInteractionPoints ps <- rs]

-- | goalsOf: the visible goals of the last @AllGoalsWarnings@ in a
-- collection — each goal's interaction point and printed type.
goalsOf :: [IResponse] -> [LaneGoal]
goalsOf rs = case [io | IDisplayInfo "AllGoalsWarnings" (Object io) <- rs] of
  [] -> []
  os -> goalsFrom (last os)
  where
    goalsFrom io = case KM.lookup "visibleGoals" io of
      Just (Array a) -> mapMaybe goalFrom (V.toList a)
      _              -> []
    goalFrom (Object g) = case KM.lookup "constraintObj" g of
      Just (Object c) -> do
        i <- intField "id" c
        pure (LaneGoal i (rangeField c) (fromMaybe "" (textField "type" g)))
      _ -> Nothing
    goalFrom _ = Nothing

-- | goalInfoOf: the @goalInfo@ object of a @GoalSpecific@ response — where
-- goal-scoped answers (inferred types, goal contexts) live.
goalInfoOf :: IResponse -> Maybe Value
goalInfoOf (IDisplayInfo "GoalSpecific" (Object io)) = KM.lookup "goalInfo" io
goalInfoOf _ = Nothing

-- | pointContaining: the interaction point whose range contains the 1-based
-- position.  With a column, containment is positional (start inclusive, end
-- exclusive, matching the hole model's addressing) — which is what
-- distinguishes two goals sharing a line, whose scopes can differ (probed:
-- @(\ m -> {!!}) {!!}@ binds @m@ in the first hole only).  With a line
-- alone, the earliest point on that line wins, which the tool descriptions
-- state.
pointContaining :: Int -> Maybe Int -> [IPoint] -> Maybe IPoint
pointContaining ln mCol ps = listToMaybe
  [ p | p <- ps, Just r <- [ipRange p], contains r ]
  where
    contains r = case mCol of
      Nothing  -> irLine r <= ln && ln <= irEndLine r
      Just col ->
        (irLine r, irCol r) <= (ln, col) && (ln, col) < (irEndLine r, irEndCol r)

-- Field helpers over Aeson objects.

textField :: Text -> KM.KeyMap Value -> Maybe Text
textField k o = case KM.lookup (Key.fromText k) o of
  Just (String t) -> Just t
  _               -> Nothing

intField :: Text -> KM.KeyMap Value -> Maybe Int
intField k o = case KM.lookup (Key.fromText k) o of
  Just (Number n) -> Just (round n)
  _               -> Nothing

-- | rangeField: the first range of an object carrying a @range@ array of
-- @{start: {line, col, …}, end: {line, col, …}}@ segments.
rangeField :: KM.KeyMap Value -> Maybe IRange
rangeField o = case KM.lookup "range" o of
  Just (Array a) -> listToMaybe (mapMaybe segFrom (V.toList a))
  _              -> Nothing
  where
    segFrom (Object s) =
      case (KM.lookup "start" s, KM.lookup "end" s) of
        (Just (Object st), Just (Object en)) ->
          IRange <$> intField "line" st <*> intField "col" st
                 <*> intField "line" en <*> intField "col" en
        _ -> Nothing
    segFrom _ = Nothing


-- ---------------------------------------------------------------------------
-- IOTCM construction
-- ---------------------------------------------------------------------------

-- | hsShow: a Text as a Haskell string literal — the escaping the IOTCM
-- parser requires (§ 2.3 of the design document; probed: an unescaped @\\x@
-- rejects the whole line, and 'show'-style decimal escapes carry Unicode).
hsShow :: Text -> Text
hsShow = T.pack . show . T.unpack

-- | hsShowList: a flag list as a Haskell @[String]@ literal.
hsShowList :: [String] -> Text
hsShowList = T.pack . show

-- | iotcmLine: one full command line.  Highlighting level @None@ silences the
-- per-token payloads the lane has no use for.
iotcmLine :: FilePath -> Text -> Text
iotcmLine file cmd =
  "IOTCM " <> hsShow (T.pack file) <> " None Direct (" <> cmd <> ")"

-- | cmdLoad: load a file with the resolved project flags as its per-load
-- argv.  An empty argv loses the library context (probed: a LibraryError
-- naming the wrong registry), so callers pass the same effective flag list
-- the batch lane would run @agda@ with.
cmdLoad :: FilePath -> [String] -> Text
cmdLoad file argv =
  "Cmd_load " <> hsShow (T.pack file) <> " " <> hsShowList argv

cmdInferToplevel :: Text -> Text
cmdInferToplevel expr = "Cmd_infer_toplevel Normalised " <> hsShow expr

cmdInferAtGoal :: Int -> Text -> Text
cmdInferAtGoal gid expr =
  "Cmd_infer Normalised " <> T.pack (show gid) <> " noRange " <> hsShow expr

cmdComputeToplevel :: Text -> Text
cmdComputeToplevel expr = "Cmd_compute_toplevel DefaultCompute " <> hsShow expr

cmdComputeAtGoal :: Int -> Text -> Text
cmdComputeAtGoal gid expr =
  "Cmd_compute DefaultCompute " <> T.pack (show gid) <> " noRange "
  <> hsShow expr

cmdWhyInScopeToplevel :: Text -> Text
cmdWhyInScopeToplevel name = "Cmd_why_in_scope_toplevel " <> hsShow name

cmdWhyInScopeAtGoal :: Int -> Text -> Text
cmdWhyInScopeAtGoal gid name =
  "Cmd_why_in_scope " <> T.pack (show gid) <> " noRange " <> hsShow name

cmdModuleContentsToplevel :: Text -> Text
cmdModuleContentsToplevel m =
  "Cmd_show_module_contents_toplevel Simplified " <> hsShow m

cmdGoalTypeContext :: Int -> Text
cmdGoalTypeContext gid =
  "Cmd_goal_type_context Normalised " <> T.pack (show gid) <> " noRange \"\""

-- | cmdShowVersion: the sentinel.  State-free, fast, and its response —
-- @DisplayInfo@/@Version@ — occurs nowhere else, so it delimits the previous
-- command's output exactly (§ 2.1 of the design document).
cmdShowVersion :: Text
cmdShowVersion = "Cmd_show_version"


-- ---------------------------------------------------------------------------
-- Lanes and their registry
-- ---------------------------------------------------------------------------

-- | One live child process and its bookkeeping.
data Lane = Lane
  { laneRoot    :: FilePath
  , laneProc    :: ProcessHandle
  , lanePgid    :: Maybe Pid
  , laneIn      :: Handle
  , laneOut     :: Handle
  , laneErrTail :: IORef [Text]          -- ^ Last stderr lines, newest first.
  , laneLoad    :: IORef (Maybe LoadState)
  , laneVersion :: IORef (Maybe Text)    -- ^ From the most recent sentinel.
  , laneLastUse :: IORef Word            -- ^ Monotonic seconds, for the reaper.
  }

-- | What the lane last loaded, and what came of it.
data LoadState = LoadState
  { lsPath    :: FilePath
  , lsStamp   :: Maybe FileStamp
  , lsFlags   :: [String]
  , lsOutcome :: Either Text LoadedInfo  -- ^ Left: the load error's message.
  }

-- | The (mtime, size) stamp that gates re-loading.  Equality is the whole
-- interface; a stamp that could not be read is 'Nothing' at the use site and
-- never equal, so doubt re-loads.
data FileStamp = FileStamp UTCTime Integer
  deriving (Eq, Show)

-- | LoadedInfo: what a successful load leaves behind — the interaction
-- points and each visible goal's type.
data LoadedInfo = LoadedInfo
  { liPoints :: [IPoint]
  , liGoals  :: [LaneGoal]
  } deriving (Eq, Show)

-- | The per-root slot.  Holding the 'MVar' is holding the lane: requests,
-- the reaper, and shutdown all take it, so the child is never spoken to
-- concurrently.  @Nothing@ means no child is alive for this root.
type LaneSlot = MVar (Maybe Lane)

-- | InteractionLanes: the registry — one slot per resolved project root —
-- plus the idle reaper's thread and the shutdown latch.  The latch is read
-- and written only under the 'ilSlots' lock, which is what orders every
-- request against 'shutdownLanes': a request that saw the registry open got
-- its slot into the map shutdown will drain, and one that arrives later is
-- refused before it can spawn anything.
data InteractionLanes = InteractionLanes
  { ilSlots  :: MVar (Map FilePath LaneSlot)
  , ilReaper :: ThreadId
  , ilClosed :: IORef Bool
  }

-- | laneIdleSeconds: how long a lane may sit unused before the reaper closes
-- it.  A reaped lane costs its next caller one load (seconds); an idle one
-- holds a whole library's typechecking state resident, so the bound leans
-- toward reaping.  Fifteen minutes comfortably outlives an agent's
-- edit-question-edit cadence within one task.
laneIdleSeconds :: Word
laneIdleSeconds = 900

-- | newInteractionLanes: an empty registry with its reaper running.
newInteractionLanes :: IO InteractionLanes
newInteractionLanes = do
  slots  <- newMVar Map.empty
  reaper <- forkIO (reapLoop slots)
  closed <- newIORef False
  pure (InteractionLanes slots reaper closed)
  where
    -- Synchronous failures must not kill the reaper, but the asynchronous
    -- 'ThreadKilled' from 'shutdownLanes' must — a blanket handler here would
    -- swallow it whenever the kill lands mid-sweep and leave the loop
    -- running forever (a Copilot review catch on PR 107).
    reapLoop slots = forever $ do
      threadDelay 60_000_000
      sweep slots `catch` \(e :: SomeException) ->
        case fromException e of
          Just (a :: AsyncException) -> throwIO a
          Nothing                    -> pure ()
    sweep slots = do
      m   <- readMVar slots
      now <- monotonicSeconds
      mapM_ (reapSlot now) (Map.elems m)
    -- Busy lanes (slot taken) are skipped, never waited on: the reaper must
    -- not queue behind a long request only to kill the lane that just
    -- finished serving it.  Once taken, the slot is restored on EVERY exit —
    -- an asynchronous kill landing between the take and the put would
    -- otherwise leave the slot empty, and every later request on that root
    -- would block forever on it.
    reapSlot now slot = do
      taken <- tryTakeMVar slot
      case taken of
        Nothing   -> pure ()
        Just held -> (decide held >>= putMVar slot)
                       `onException` putMVar slot held
      where
        decide Nothing = pure Nothing
        decide (Just lane) = do
          lastUse <- readIORef (laneLastUse lane)
          if now >= lastUse && now - lastUse >= laneIdleSeconds
            then stopLane lane >> pure Nothing
            else pure (Just lane)

-- | shutdownLanes: latch the registry closed, stop the reaper, and stop
-- every lane — waiting for a slot an in-flight request still holds rather
-- than skipping it, or that request would restore a live child into a
-- detached slot nobody will ever look at again (a Copilot round-3 catch).
-- The wait is bounded in practice: the latch (set under the registry lock)
-- refuses new requests, and the holder finishes within its own @--timeout@.
-- In the shipped serial server no request can be in flight here at all, so
-- the take never blocks; the wait is for embeddings that cancel a server
-- while another thread is mid-request.  Harmless against lanes already dead,
-- and idempotent.
shutdownLanes :: InteractionLanes -> IO ()
shutdownLanes il = do
  killThread (ilReaper il)
  m <- modifyMVar (ilSlots il) $ \m -> do
    writeIORef (ilClosed il) True
    pure (Map.empty, m)
  mapM_ closeSlot (Map.elems m)
  where
    closeSlot slot = do
      held <- takeMVar slot
      case held of
        Just lane -> stopLane lane >> putMVar slot Nothing
        Nothing   -> putMVar slot Nothing

-- | stopLane: close stdin — Agda exits cleanly on EOF (probed: rc 0) — then
-- make sure with the ladder.  'escalateAndReap' begins with SIGINT and always
-- reaps, so a child that exited moments ago costs nothing further, and one
-- that ignored the EOF cannot outlive the call.
--
-- For a child that is known dead but died an unknown time ago, use
-- 'closeLaneHandles' instead: the ladder probes and signals the raw pgid,
-- which may by then name an unrelated, recycled process group.
stopLane :: Lane -> IO ()
stopLane lane = do
  ignoringIOErrors (hClose (laneIn lane))
  escalateAndReap (laneProc lane) (lanePgid lane)
  ignoringIOErrors (hClose (laneOut lane))

-- | closeLaneHandles: release a dead lane's pipe handles, no signals.
--
-- The one caller is the revival path, where 'getProcessExitCode' has already
-- reaped the child — some time ago, possibly long ago.  Sending the ladder
-- there would be worse than the descriptor leak it fixes: 'groupAlive'
-- probes @kill(-pgid, 0)@, and a long-dead child's pgid can have been
-- recycled by an unrelated process group, which the ladder would then
-- SIGTERM.  (An interaction-mode agda spawns no descendants that could
-- legitimately outlive it — it never invokes GHC — so there is nothing for
-- the ladder to catch here anyway.)  The stderr drainer closes its own
-- handle at EOF.
closeLaneHandles :: Lane -> IO ()
closeLaneHandles lane = do
  ignoringIOErrors (hClose (laneIn lane))
  ignoringIOErrors (hClose (laneOut lane))

monotonicSeconds :: IO Word
monotonicSeconds = do
  ns <- getMonotonicTimeNSec
  pure (fromIntegral (ns `div` 1_000_000_000))

-- | ignoringIOErrors: best-effort cleanup — exactly 'IOException's, which is
-- what the name says.  A blanket @SomeException@ here would also swallow the
-- asynchronous cancellation a shutting-down server delivers, and cleanup
-- that eats its caller's kill leaves the server running (the round-2 Copilot
-- family on PR 107).
ignoringIOErrors :: IO () -> IO ()
ignoringIOErrors act = act `catch` \(_ :: IOException) -> pure ()

-- | trySynchronous: 'try' that lets asynchronous exceptions fly.  For the
-- spawn path: a 'ThreadKilled' landing during 'createProcess' is the
-- server's shutdown, not a spawn failure to classify.
trySynchronous :: IO a -> IO (Either SomeException a)
trySynchronous act = try act >>= either sift (pure . Right)
  where
    sift e = case fromException e of
      Just (a :: AsyncException) -> throwIO a
      Nothing                    -> pure (Left e)


-- ---------------------------------------------------------------------------
-- Failures
-- ---------------------------------------------------------------------------

-- | LaneEvent: what class of thing went wrong with the lane itself.  A load
-- or query whose /Agda answer/ is an error is not a 'LaneFailure' — the lane
-- is healthy and the error is the answer; these events are about the process.
data LaneEvent
  = LaneSpawnFailure   -- ^ The child could not be started.
  | LaneTimeout        -- ^ The request hit the bound; the child was killed.
  | LaneCrash          -- ^ The child exited or closed its pipes mid-request.
  | LaneShutdown       -- ^ The registry is latched closed; nothing was run.
  deriving (Eq, Show)

-- | LaneFailure: a structured lane-level failure.  The tool layer serializes
-- this into the response (with the command and project echo attached) rather
-- than letting it surface as an opaque internal error.
data LaneFailure = LaneFailure
  { lfEvent      :: LaneEvent
  , lfMessage    :: Text
  , lfStderrTail :: [Text]   -- ^ Newest first, bounded.
  , lfSent       :: [Text]   -- ^ The IOTCM lines the failing request had
                             --   attempted, oldest first — so a spawn-phase
                             --   failure still echoes its wire trail.
  } deriving (Eq, Show)


-- ---------------------------------------------------------------------------
-- The request handle
-- ---------------------------------------------------------------------------

-- | LaneHandle: one request's view of one lane, valid inside 'withLane'.
--
-- Carries the deadline shared by everything the request does, the record of
-- every IOTCM line sent (for the response echo), and the doom flag that
-- tells 'withLane' to kill the lane instead of returning it to the slot.
data LaneHandle = LaneHandle
  { lhLane     :: Lane
  , lhDeadline :: Deadline
  , lhSent     :: IORef [Text]
  , lhSpawned  :: Bool
  , lhDoomed   :: IORef Bool
  }

-- | A deadline in monotonic nanoseconds.
newtype Deadline = Deadline Integer

-- | newDeadline: now plus the configured bound.  A missing or non-positive
-- bound reads as "no limit", the batch lane's convention.
newDeadline :: Maybe Int -> IO Deadline
newDeadline mSecs = do
  ns <- getMonotonicTimeNSec
  let bound = case mSecs of
        Just s | s > 0 -> fromIntegral s * 1_000_000_000
        _              -> 10 * 365 * 86_400 * 1_000_000_000
  pure (Deadline (fromIntegral ns + bound))

remainingMicros :: Deadline -> IO Int
remainingMicros (Deadline dl) = do
  ns <- getMonotonicTimeNSec
  let left = (dl - fromIntegral ns) `div` 1000
  pure (fromIntegral (max 0 (min left (fromIntegral (maxBound :: Int)))))

-- | Echo accessors for the tool layer.
laneAgdaVersion :: LaneHandle -> IO (Maybe Text)
laneAgdaVersion = readIORef . laneVersion . lhLane

laneSentLines :: LaneHandle -> IO [Text]
laneSentLines lh = reverse <$> readIORef (lhSent lh)

laneWasSpawned :: LaneHandle -> Bool
laneWasSpawned = lhSpawned

lanePidOf :: LaneHandle -> IO (Maybe Int)
lanePidOf lh = pure (fromIntegral <$> lanePgid (lhLane lh))

-- | withLane: run a request body against the lane for one root, spawning the
-- child if none is alive, serialized against every other request for the
-- same root.
--
-- Lifecycle, all on this seam: a child that died while idle is detected
-- ('getProcessExitCode') and replaced before the body runs; a body that
-- doomed its lane (timeout, crash — the doom flag is set by 'runCmdOn') leaves
-- a killed process and an empty slot; a body that threw kills the lane —
-- the wire may hold another request's half-collected responses, which no
-- future request may inherit — and re-throws, with 'modifyMVar' restoring
-- the now-dead lane to the slot, where the next request's liveness probe
-- replaces it.  A healthy lane returns to the slot with its last-use stamp
-- refreshed.
withLane
  :: InteractionLanes
  -> AgdaConfig
  -> FilePath   -- ^ The resolved project root — the lane's registry key
                --   (the child itself inherits the server's cwd).
  -> (LaneHandle -> IO a)
  -> IO (Either LaneFailure a)
withLane il cfg root body = do
  -- One deadline for the whole request — spawn flush, load, and query share
  -- its remaining budget, so a first request is bounded by @--timeout@ once,
  -- not once per phase (a Copilot review catch on PR 107).
  deadline <- newDeadline (agdaTimeout cfg)
  -- The shutdown latch is read under the registry lock, so a request either
  -- got its slot into the map 'shutdownLanes' will drain, or is refused here
  -- before it can spawn anything (a Copilot round-3 catch).
  mSlot <- modifyMVar (ilSlots il) $ \m -> do
    closed <- readIORef (ilClosed il)
    if closed then pure (m, Nothing) else
      case Map.lookup root m of
        Just s  -> pure (m, Just s)
        Nothing -> do
          s <- newMVar Nothing
          pure (Map.insert root s m, Just s)
  case mSlot of
    Nothing -> pure . Left $ LaneFailure
      { lfEvent      = LaneShutdown
      , lfMessage    = "the server is shutting down; no interaction lane will be started"
      , lfStderrTail = []
      , lfSent       = []
      }
    Just slot -> modifyMVar slot $ \held -> do
      -- Re-check the latch now that this slot is held: between the registry
      -- access above and here, a whole shutdown can have run and drained
      -- this very slot, and spawning after that would leak a child nothing
      -- drains again.  The two checks close the window from both sides —
      -- either this request sees the latch, or shutdown's blocking drain
      -- waits for it and stops whatever it restores.
      closed <- readIORef (ilClosed il)
      revived <- if closed
        then pure (Left LaneFailure
          { lfEvent      = LaneShutdown
          , lfMessage    = "the server is shutting down; no interaction lane will be started"
          , lfStderrTail = []
          , lfSent       = []
          })
        else reviveOrSpawn deadline held
      case revived of
        Left failure -> pure (held, Left failure)
        Right (lane, flushSent, spawned) -> do
          -- A spawning call's echo starts with the startup flush it already
          -- sent (newest first, as the handle stores them); a reviving or
          -- reusing call starts empty.
          sent   <- newIORef (reverse flushSent)
          doomed <- newIORef False
          let lh = LaneHandle lane deadline sent spawned doomed
          outcome <- try (body lh)
          case outcome of
            Left (e :: SomeException) -> do
              stopLane lane
              throwIO e
            Right a -> do
              isDoomed <- readIORef doomed
              if isDoomed
                then do
                  stopLane lane
                  pure (Nothing, Right a)
                else do
                  monotonicSeconds >>= writeIORef (laneLastUse lane)
                  pure (Just lane, Right a)
  where
    reviveOrSpawn deadline (Just lane) = do
      gone <- getProcessExitCode (laneProc lane)
      case gone of
        Nothing -> pure (Right (lane, [], False))
        Just _  -> do
          -- Dead while idle: release its handles (no ladder — the child died
          -- an unknown time ago, see 'closeLaneHandles') and start afresh.
          closeLaneHandles lane
          spawnFresh deadline
    reviveOrSpawn deadline Nothing = spawnFresh deadline

    spawnFresh deadline =
      fmap (\(l, flushSent) -> (l, flushSent, True))
        <$> spawnLane cfg root deadline

-- | spawnLane: start @agda --interaction-json@, wire up the stderr drainer,
-- and flush the startup noise with one sentinel so no command's response
-- collection can misread it (§ 2.2 of the design document).  Project flags do
-- not ride the process argv — they ride each @Cmd_load@ — so one child serves
-- every file under its root.
--
-- The child runs in the SERVER'S working directory, exactly as the batch
-- lane's one-shot @agda@ does ('AgdaMCP.Agda.runAgda' passes no cwd): the
-- server's @--agda-flags@ may name paths relative to that directory (the
-- shipped @--library-file=agda/libraries@ is exactly that), and the two lanes
-- must resolve one file against one tree.  The root parameter keys the lane's
-- registry slot and bookkeeping; it is not a chdir.
spawnLane
  :: AgdaConfig -> FilePath -> Deadline
  -> IO (Either LaneFailure (Lane, [Text]))
spawnLane cfg root deadline = do
  started <- trySynchronous $ createProcess (proc (agdaBin cfg) ["--interaction-json"])
    { std_in  = CreatePipe
    , std_out = CreatePipe
    , std_err = CreatePipe
      -- Its own process group, exactly as the batch lane spawns agda, so the
      -- timeout ladder can reach any descendant.
    , create_group = True
    }
  case started of
    Left (e :: SomeException) -> pure . Left $ LaneFailure
      { lfEvent      = LaneSpawnFailure
      , lfMessage    = "could not start " <> T.pack (agdaBin cfg)
                       <> " --interaction-json in " <> T.pack root
                       <> ": " <> T.pack (show e)
      , lfStderrTail = []
      , lfSent       = []
      }
    -- From here to the registry the child is owned by nobody: the setup runs
    -- under 'mask' and the (interruptible) flush under 'onException'-cleanup,
    -- so an exception at any point — asynchronous cancellation included —
    -- stops the child instead of leaking a process no registry knows about
    -- (a Copilot round-3 catch).  Asyncs still propagate; they are deferred
    -- only across the non-blocking setup below.
    Right (Just hIn, Just hOut, Just hErr, ph) -> mask $ \restore -> do
      hSetBinaryMode hOut True
      errTail <- newIORef []
      _ <- forkIO (drainStderr hErr errTail)
      pgid    <- getPid ph
      loadRef <- newIORef Nothing
      verRef  <- newIORef Nothing
      useRef  <- newIORef =<< monotonicSeconds
      let lane = Lane
            { laneRoot    = root
            , laneProc    = ph
            , lanePgid    = pgid
            , laneIn      = hIn
            , laneOut     = hOut
            , laneErrTail = errTail
            , laneLoad    = loadRef
            , laneVersion = verRef
            , laneLastUse = useRef
            }
      -- Flush startup noise on the requesting call's own deadline — the
      -- flush is part of that request's budget, not a bound of its own.  A
      -- child too broken to answer the first sentinel is reported as spawn
      -- failure, since no request was under way.
      sent     <- newIORef []
      doomed   <- newIORef False
      let lh = LaneHandle lane deadline sent False doomed
      flushed <- restore (runCmdOn lh Nothing) `onException` stopLane lane
      flushSent <- laneSentLines lh
      case flushed of
        Right _ -> pure (Right (lane, flushSent))
        Left lf -> do
          stopLane lane
          pure . Left $ lf { lfEvent = LaneSpawnFailure }
    Right _ -> pure . Left $ LaneFailure
      { lfEvent      = LaneSpawnFailure
      , lfMessage    = "could not open the interaction child's pipes"
      , lfStderrTail = []
      , lfSent       = []
      }

-- | drainStderr: keep the last lines of the child's stderr for crash
-- reports.  Interaction mode says little there, but what it says on the way
-- down is exactly what a 'LaneCrash' needs to carry.
drainStderr :: Handle -> IORef [Text] -> IO ()
drainStderr h ref = do
  loop `catch` \(_ :: IOException) -> pure ()
  ignoringIOErrors (hClose h)
  where
    keep = 40
    loop = do
      raw <- BS8.hGetLine h
      let line = TE.decodeUtf8With lenientDecode raw
      atomicModifyIORef' ref (\ls -> (take keep (line : ls), ()))
      loop


-- ---------------------------------------------------------------------------
-- Sending commands and collecting their responses
-- ---------------------------------------------------------------------------

-- | runCmdOn: send one command (or none, to flush) followed by the sentinel,
-- and collect every response up to the sentinel's.
--
-- Both phases run under the request's deadline: the send too, because a
-- child that stopped reading stdin leaves a large-enough write blocked in
-- the pipe forever, which on a serial server is a wedge no later bound can
-- catch (a Copilot review catch on PR 107).  The 'try' inside the 'timeout'
-- is 'IOException'-only, for the same reason as 'readResponseLine': a
-- blanket handler there would swallow the timeout's own asynchronous
-- exception and misreport it as a crash.  The echo records the lines as
-- attempted whatever became of the write.
--
-- On timeout or EOF the lane is doomed: its process group is killed by the
-- issue-#77 ladder here and now (so nothing runs on unattended), and the doom
-- flag tells 'withLane' not to return it to the slot.
runCmdOn :: LaneHandle -> Maybe (FilePath, Text) -> IO (Either LaneFailure [IResponse])
runCmdOn lh mCmd = do
  let lane = lhLane lh
      lines' = [iotcmLine f c | Just (f, c) <- [mCmd]]
               <> [iotcmLine (laneRoot lane) cmdShowVersion]
  left <- remainingMicros (lhDeadline lh)
  sendOutcome <- timeout left
    (try (mapM_ (sendLine lane) lines') :: IO (Either IOException ()))
  atomicModifyIORef' (lhSent lh) (\ls -> (reverse lines' <> ls, ()))
  case sendOutcome of
    Nothing -> doomWith lh LaneTimeout $
      "the interaction child stopped reading input"
      <> maybe "" (\(_, c) -> " while being sent " <> c) mCmd
    Just (Left e) -> doomWith lh LaneCrash $
      "the interaction child refused input: " <> T.pack (show e)
    Just (Right ()) -> collect []
  where
    collect acc = do
      r <- readResponseLine lh
      case r of
        Left end -> case end of
          ReadTimedOut -> doomWith lh LaneTimeout $
            "agda interaction command timed out"
            <> maybe "" (\(_, c) -> " running " <> c) mCmd
          ReadEOF -> doomWith lh LaneCrash
            "the interaction child closed its output mid-command"
        Right resp -> case resp of
          IDisplayInfo "Version" (Object io) -> do
            case textField "version" io of
              Just v  -> writeIORef (laneVersion (lhLane lh)) (Just v)
              Nothing -> pure ()
            pure (Right (reverse acc))
          _ -> collect (resp : acc)

    sendLine lane t = do
      hPutStrLn (laneIn lane) (T.unpack t)
      hFlush (laneIn lane)

-- | doomWith: kill the lane, mark it doomed, and shape the failure.
doomWith :: LaneHandle -> LaneEvent -> Text -> IO (Either LaneFailure a)
doomWith lh event msg = do
  writeIORef (lhDoomed lh) True
  stopLane (lhLane lh)
  errs <- readIORef (laneErrTail (lhLane lh))
  sent <- laneSentLines lh
  pure . Left $ LaneFailure
    { lfEvent      = event
    , lfMessage    = msg
    , lfStderrTail = take 10 errs
    , lfSent       = sent
    }

data ReadEnd = ReadTimedOut | ReadEOF

-- | readResponseLine: one classified line from the child, under the
-- request's deadline.  Bytes are decoded as UTF-8 leniently, the same
-- reasoning as the batch drainers: Agda's output routinely carries the
-- goal's Unicode, and the handle's locale must not get a vote.
--
-- The inner 'try' catches 'IOException' only, and deliberately: it sits
-- inside 'timeout', and a @SomeException@ handler there would swallow the
-- timeout's own asynchronous exception, misreporting every hung read as a
-- crash (caught by the tier-3 fake-binary tests).  An EOF or broken pipe is
-- an 'IOException'; the timeout signal is not.
readResponseLine :: LaneHandle -> IO (Either ReadEnd IResponse)
readResponseLine lh = loop
  where
    loop = do
      left <- remainingMicros (lhDeadline lh)
      if left <= 0 then pure (Left ReadTimedOut) else do
        got <- timeout left
          (try (BS8.hGetLine (laneOut (lhLane lh)))
             :: IO (Either IOException BS8.ByteString))
        case got of
          Nothing -> pure (Left ReadTimedOut)
          Just (Left _)    -> pure (Left ReadEOF)
          Just (Right raw) ->
            case parseResponseLine (TE.decodeUtf8With lenientDecode raw) of
              Nothing   -> loop
              Just resp -> pure (Right resp)


-- ---------------------------------------------------------------------------
-- Loading files
-- ---------------------------------------------------------------------------

-- | LoadAction: what 'ensureLoaded' did, and why — echoed in every response
-- so a client can attribute the call's latency.
data LoadAction
  = LoadReused    -- ^ Same file, same stamp, same flags, last load succeeded.
  | LoadFirst     -- ^ The lane had loaded nothing yet.
  | LoadSwitch    -- ^ The lane held a different file.
  | LoadChanged   -- ^ The file's (mtime, size) stamp or flags changed.
  | LoadRetry     -- ^ The previous load of this file failed.
  | LoadForced    -- ^ The client passed @reload: true@ — the escape hatch
                  --   for a changed dependency, which no stamp on the
                  --   queried file can see.
  deriving (Eq, Show)

-- | LoadReport: the outcome of 'ensureLoaded'.
data LoadReport = LoadReport
  { lrAction            :: LoadAction
  , lrOutcome           :: Either Text LoadedInfo
                           -- ^ Left: the load failed, and this is Agda's
                           -- message.  The lane itself is healthy.
  , lrCheckedFromSource :: Bool
                           -- ^ Did this call re-typecheck the file from
                           -- source (a @Checking@ progress line naming it)?
                           -- False for 'LoadReused'.
  , lrElapsedMs         :: Int
  } deriving (Eq, Show)

-- | ensureLoaded: make the lane's state be about this file, re-loading only
-- on evidence (§ 3 of the design document): first sight, a path switch, a
-- changed stamp, changed flags, a failed previous load, or the client's own
-- @reload: true@ (evidence the stamp cannot carry — a changed dependency).
-- The flags are the effective flag list the batch lane would run @agda@
-- with, and they ride the @Cmd_load@ as its per-load argv.
ensureLoaded
  :: LaneHandle
  -> Bool       -- ^ Force a fresh load regardless of the stamp.
  -> FilePath   -- ^ Absolute path of the file queried.
  -> [String]   -- ^ Effective flags (server's + project's + file dir).
  -> IO (Either LaneFailure LoadReport)
ensureLoaded lh force path flags = do
  start  <- getMonotonicTimeNSec
  stamp  <- stampOf path
  known  <- readIORef (laneLoad (lhLane lh))
  let decision = case known of
        _ | force -> Just LoadForced
        Nothing -> Just LoadFirst
        Just ls
          | not (equalFilePath (lsPath ls) path) -> Just LoadSwitch
          | lsFlags ls /= flags                  -> Just LoadChanged
          | lsStamp ls /= stamp || stamp == Nothing -> Just LoadChanged
          | Left _ <- lsOutcome ls               -> Just LoadRetry
          | otherwise                            -> Nothing
  case (decision, known) of
    (Nothing, Just ls) -> do
      end <- getMonotonicTimeNSec
      pure . Right $ LoadReport
        { lrAction            = LoadReused
        , lrOutcome           = lsOutcome ls
        , lrCheckedFromSource = False
        , lrElapsedMs         = elapsedMsBetween start end
        }
    (mAction, _) -> do
      let action = fromMaybe LoadFirst mAction
      collected <- runCmdOn lh (Just (path, cmdLoad path flags))
      case collected of
        Left lf -> pure (Left lf)
        Right rs -> do
          let outcome = classifyLoad path rs
              checked = any (checkingNames path) rs
          writeIORef (laneLoad (lhLane lh)) . Just $ LoadState
            { lsPath    = path
            , lsStamp   = stamp
            , lsFlags   = flags
            , lsOutcome = outcome
            }
          end <- getMonotonicTimeNSec
          pure . Right $ LoadReport
            { lrAction            = action
            , lrOutcome           = outcome
            , lrCheckedFromSource = checked
            , lrElapsedMs         = elapsedMsBetween start end
            }
  where
    checkingNames p (IRunningInfo msg) =
      any (equalFilePath p . snd) (mapMaybe parseCheckingLine (T.lines msg))
    checkingNames _ _ = False

-- | classifyLoad: a load is successful exactly when it announced interaction
-- points (§ 2.4); otherwise the first error message is the outcome, and a
-- load that produced neither is reported as such rather than guessed at.
classifyLoad :: FilePath -> [IResponse] -> Either Text LoadedInfo
classifyLoad path rs = case interactionPointsOf rs of
  Just ps -> Right (LoadedInfo ps (goalsOf rs))
  Nothing -> Left $ case mapMaybe errorMessageOf rs of
    (msg : _) -> msg
    []        -> "agda reported neither interaction points nor an error while loading "
                 <> T.pack path

stampOf :: FilePath -> IO (Maybe FileStamp)
stampOf path = do
  r <- try $ FileStamp <$> getModificationTime path <*> getFileSize path
  pure $ case r of
    Left (_ :: IOException) -> Nothing
    Right s                 -> Just s

elapsedMsBetween :: Word64 -> Word64 -> Int
elapsedMsBetween start end =
  fromIntegral ((end - start) `div` 1_000_000)


-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

-- | runQuery: one knowledge command against the lane's current state.
-- Callers go through 'ensureLoaded' first; the file argument is the one the
-- IOTCM names, which must be the loaded file — a mismatch would trigger
-- Agda's implicit re-load with an argv the lane did not choose (§ 2.6 of the
-- design document).
runQuery :: LaneHandle -> FilePath -> Text -> IO (Either LaneFailure [IResponse])
runQuery lh path cmd = runCmdOn lh (Just (path, cmd))


-- ---------------------------------------------------------------------------
-- Provenance prose
-- ---------------------------------------------------------------------------

-- | SrcLoc: a parsed @/path/File.agda:14.1-13@ (same-line) or
-- @/path:9.6-10.2@ (multi-line) location from Agda's provenance prose.
data SrcLoc = SrcLoc
  { slFile    :: FilePath
  , slLine    :: Int
  , slCol     :: Int
  , slEndLine :: Int
  , slEndCol  :: Int
  } deriving (Eq, Show)

-- | ProvenanceStep: one @- … at …@ step of a WhyInScope chain: the phrase
-- (@its definition@, @the opening of M@, @the application of M@) and the
-- location when the prose carried one (steps into other modules' scope
-- information print a bare @at@ — observed on the re-export fixture).
data ProvenanceStep = ProvenanceStep
  { psStep     :: Text
  , psLocation :: Maybe SrcLoc
  } deriving (Eq, Show)

-- | ScopeCandidate: one @*@ bullet of a WhyInScope answer.
data ScopeCandidate = ScopeCandidate
  { scDescription :: Text            -- ^ E.g. @a defined name M.N.amb@.
  , scQualified   :: Maybe Text      -- ^ The fully qualified name, when the
                                     --   description's last word is one.
  , scChain       :: [ProvenanceStep]
  , scDefinition  :: Maybe SrcLoc    -- ^ The @its definition at@ / @bound at@
                                     --   location, when present.
  } deriving (Eq, Show)

-- | parseSrcLoc: one location.  The file is everything up to the /last/
-- colon; the range is @L.C@, @L.C-C'@ (same line), or @L.C-L'.C'@.
parseSrcLoc :: Text -> Maybe SrcLoc
parseSrcLoc t = do
  let s = T.strip t
      (pre, rangeT) = T.breakOnEnd ":" s
  file <- T.stripSuffix ":" pre
  if T.null file then Nothing else do
    (l, c, el, ec) <- parseRange rangeT
    pure (SrcLoc (T.unpack file) l c el ec)
  where
    parseRange r = case T.splitOn "-" r of
      [startT] -> do
        (l, c) <- parsePoint startT
        pure (l, c, l, c)
      [startT, endT] -> do
        (l, c) <- parsePoint startT
        case parsePoint endT of
          Just (el, ec) -> pure (l, c, el, ec)
          Nothing       -> do
            ec <- readIntT endT
            pure (l, c, l, ec)
      _ -> Nothing
    parsePoint p = case T.splitOn "." p of
      [lT, cT] -> (,) <$> readIntT lT <*> readIntT cT
      _        -> Nothing
    readIntT x = case reads (T.unpack (T.strip x)) of
      [(n, "")] -> Just n
      _         -> Nothing

-- | parseWhyInScope: the WhyInScope message into candidates.
--
-- @Nothing@ means the message said @… is not in scope.@; @Just []@ would
-- mean a message this parser did not understand at all, which callers treat
-- the same way but can report differently.  The grammar, as observed:
--
-- >  <name> is in scope as
-- >    * a defined name M.N.x brought into scope by
-- >      - the opening of N at /path:9.6-13
-- >      - its definition at /path:4.3-6
-- >    * a variable bound at /path:4.3-4
--
-- A line more indented than a bullet or step that does not itself start one
-- is a continuation of the previous line (Agda wraps long output), joined
-- with a space before parsing.
parseWhyInScope :: Text -> Maybe [ScopeCandidate]
parseWhyInScope msg
  | "is not in scope." `T.isInfixOf` msg = Nothing
  | otherwise =
      let (done, mCur) = foldl consume ([], Nothing) (joined (T.lines msg))
      in Just (done <> maybe [] (: []) mCur)
  where
    -- Join wrapped continuations into their bullet or step line first.
    joined = foldl step []
      where
        step acc ln
          | T.null (T.strip ln)                      = acc
          | isBullet ln || isStep ln || null acc     = acc <> [T.strip ln]
          | otherwise = init acc <> [last acc <> " " <> T.strip ln]
    isBullet ln = "* " `T.isPrefixOf` T.stripStart ln
    isStep   ln = "- " `T.isPrefixOf` T.stripStart ln

    -- Top to bottom: a bullet opens a candidate, a step extends the open one.
    consume (done, mCur) ln
      | Just body <- T.stripPrefix "* " ln =
          (done <> maybe [] (: []) mCur, Just (bulletFrom body))
      | Just body <- T.stripPrefix "- " ln =
          (done, attach (stepFrom body) <$> mCur)
      | otherwise = (done, mCur)

    attach st c = c
      { scChain      = scChain c <> [st]
      , scDefinition = case scDefinition c of
          Just loc -> Just loc
          Nothing  -> definitionOf st
      }

    bulletFrom body =
      case T.stripSuffix " brought into scope by" body of
        Just described -> ScopeCandidate
          { scDescription = described
          , scQualified   = lastWord described
          , scChain       = []
          , scDefinition  = Nothing
          }
        Nothing ->
          -- A one-line bullet: @a variable bound at <loc>@ and kin.
          let (desc, locT) = T.breakOn " bound at " body
          in case parseSrcLoc (T.drop (T.length (" bound at " :: Text)) locT) of
               Just loc -> ScopeCandidate
                 { scDescription = T.strip desc
                 , scQualified   = Nothing
                 , scChain       = [ProvenanceStep "bound" (Just loc)]
                 , scDefinition  = Just loc
                 }
               Nothing -> ScopeCandidate
                 { scDescription = body
                 , scQualified   = lastWord body
                 , scChain       = []
                 , scDefinition  = Nothing
                 }

    stepFrom body =
      let (phraseT, locT) = T.breakOnEnd " at " body
      in case parseSrcLoc locT of
           Just loc -> ProvenanceStep
             (T.strip (fromMaybe phraseT (T.stripSuffix " at " phraseT)))
             (Just loc)
           Nothing ->
             ProvenanceStep (T.strip (fromMaybe body (T.stripSuffix " at" body)))
                            Nothing

    definitionOf st
      | "its definition" `T.isPrefixOf` psStep st = psLocation st
      | otherwise                                 = Nothing

    lastWord t = case T.words t of
      [] -> Nothing
      ws -> Just (last ws)

-- | parseAmbiguousName: the candidates of an @[AmbiguousName]@ error —
-- @Ambiguous name x. It could refer to any one of@ followed by
-- @<qualified> bound at@ entries whose location may sit on the same or the
-- following line.  This is the § 2.6 recovery path for names the toplevel
-- scope holds ambiguously.
parseAmbiguousName :: Text -> [(Text, Maybe SrcLoc)]
parseAmbiguousName msg
  | not ("could refer to any one of" `T.isInfixOf` msg) = []
  | otherwise = walk (drop 1 (dropWhile (not . marker) (T.lines msg)))
  where
    marker ln = "could refer to any one of" `T.isInfixOf` ln
    walk [] = []
    walk (ln : rest)
      | Just name <- T.stripSuffix " bound at" (T.strip ln) =
          case rest of
            (locLn : rest')
              | Just loc <- parseSrcLoc locLn -> (name, Just loc) : walk rest'
            _ -> (name, Nothing) : walk rest
      | Just (name, locT) <- breakBoundAt (T.strip ln) =
          (name, parseSrcLoc locT) : walk rest
      | otherwise = walk rest
    breakBoundAt ln =
      let (pre, post) = T.breakOn " bound at " ln
      in if T.null post
           then Nothing
           else Just (T.strip pre, T.drop (T.length (" bound at " :: Text)) post)

-- | parseDidYouMean: the quoted suggestions of a @did you mean 'A' or 'B'?@
-- aside in a NotInScope error.
parseDidYouMean :: Text -> [Text]
parseDidYouMean msg = case T.breakOn "did you mean" msg of
  (_, rest) | T.null rest -> []
  (_, rest) -> quoted (T.takeWhile (/= ')') rest)
  where
    quoted t = case T.breakOn "'" t of
      (_, rest) | T.null rest -> []
      (_, rest) ->
        let (name, rest') = T.breakOn "'" (T.drop 1 rest)
        in if T.null rest' then [] else name : quoted (T.drop 1 rest')

-- | errorCodeOf: Agda's own bracketed tag — @error: [AmbiguousName]@ →
-- @AmbiguousName@ — when the message carries one.
errorCodeOf :: Text -> Maybe Text
errorCodeOf msg = case T.breakOn "error: [" msg of
  (_, rest) | T.null rest -> Nothing
  (_, rest) ->
    let tag = T.takeWhile (/= ']') (T.drop (T.length ("error: [" :: Text)) rest)
    in if T.null tag then Nothing else Just tag
