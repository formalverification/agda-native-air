-- | Agda.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Agda.hs
--
-- Description:
--   Agda subprocess interaction layer.
--
--   This module provides pure and IO functions for:
--   1. Parsing AGDADOJANG marker output from Agda's stderr.
--   2. Running the Agda binary to typecheck a file.
--   3. Reading Agda's own progress lines — @Checking M (path).@ — for the two
--      facts they carry: whether the module was re-checked from source, and
--      what Agda calls it (issues #77, #78, #100).  Anything a run of Agda can
--      be asked is asked here, rather than re-derived from the source text.
--
--   Hole enumeration and splicing live in AgdaMCP.Holes (issues #71/#73).
--
--   It is a Haskell port of the essential logic in legacy Python tools:
--     agda-dojang/python/tools/agent_bridge.py
--     agda-dojang/python/tools/report_parser.py
--
--   The functions here call the @agda@ binary as a subprocess.  The long-term
--   plan is to replace this with Agda-as-a-library calls once the Haskell
--   interface to AgdaDojang matures.
--
--   Design note (timeout enforcement, issue #77):
--   'runAgda' is built on 'createProcess' rather than 'readProcessWithExitCode'
--   because the latter cannot be timed out cleanly: 'System.Timeout.timeout'
--   kills the /waiting/ thread, not the subprocess, leaving a runaway @agda@
--   behind.  Instead we spawn @agda@ in its own process group
--   (@create_group = True@), drain its stdout and stderr concurrently on
--   dedicated threads, and race the process against a timer.  On expiry we
--   escalate group-wide — SIGINT (so agda unwinds and may still print), then
--   SIGTERM, then SIGKILL, each rung taken while the process group still has
--   members — and reap with 'waitForProcess', so no zombie and no orphan
--   survives the call.  A timeout is reported as a /value/
--   ('arTimedOut'), never an exception, which is what lets the in-place tools'
--   'Control.Exception.bracket_' restore run on the timeout path exactly as it
--   does on the success path.
--
--   Design note (one runner, two callers, issue #78):
--   'runAgda' is a thin wrapper over 'runCommand', which runs /any/ binary under
--   the same bound, the same concurrent drainers, and the same kill ladder.  The
--   whole-project gate (@check_project@) is the second caller: it runs @make@ or
--   a configured command rather than @agda@, and it is precisely where long runs
--   live, so it needs the bound more than the per-file tools do.  Running it
--   through this machinery also means the gate is spawned into its own process
--   group, so a timeout takes down the whole build tree — @make@ and every
--   @agda@ under it — rather than leaving a 20-minute typecheck running
--   unattended.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData        #-}

module AgdaMCP.Agda
  ( -- * Configuration
    AgdaConfig (..)
  , defaultConfig
  , defaultTimeoutSeconds
    -- * Debug output
  , debugLog
    -- * Marker parsing (pure)
  , parseGoalContext
  , checkedFromSourceOf
  , progressModules
  , parseCheckingLine
  , agdaModuleNameOf
    -- * Agda subprocess (IO)
  , runAgda
  , runCommand
  , AgdaResult (..)
  , timeoutMessage
  ) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar
  (MVar, newEmptyMVar, putMVar, readMVar, takeMVar, tryPutMVar)
import Control.Exception (SomeException, bracket, catch, try)
import Control.Monad (void, when)
import qualified Data.ByteString as BS
import Data.Maybe (listToMaybe)
import Data.Text.IO as TIO
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import GHC.Clock (getMonotonicTimeNSec)
import System.Directory (findExecutable, getCurrentDirectory)
import System.Exit (ExitCode (..))
import System.FilePath (equalFilePath)
import System.IO (Handle, hClose, hSetBinaryMode, stderr)
import System.Posix.Signals
  (Signal, killProcess, nullSignal, signalProcessGroup, softwareTermination)
import System.Process
  ( CreateProcess (..), Pid, ProcessHandle, StdStream (..)
  , createProcess, getPid, interruptProcessGroupOf, proc
  , terminateProcess, waitForProcess
  )

import AgdaMCP.Types (CommandEcho (..), CtxEntry (..))


-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- | Configuration for invoking the Agda binary.
data AgdaConfig = AgdaConfig
  { agdaBin       :: FilePath     -- ^ Path to the agda binary.
  , agdaFlags     :: [String]     -- ^ Extra flags (e.g. @["-i", "agda", "--library-file=..."]@).
  , agdaTimeout   :: Maybe Int    -- ^ Wall-clock timeout in seconds for one @agda@
                                  --   invocation.  @Nothing@ — or any non-positive
                                  --   number, the usual "unlimited" spelling — means
                                  --   no bound is enforced.
  , reportExpr    :: Text         -- ^ Reporting expression to inject (default: "reportGoalCtx").
  , agdaVerbose   :: Bool         -- ^ Emit debug output to stderr.
  } deriving (Eq, Show)

-- | defaultTimeoutSeconds: the default per-invocation wall-clock bound.
--
-- Every tool call is a /cold/ @agda@ subprocess, so the first call against a
-- large library pays for building its @.agdai@ interfaces — minutes, not
-- seconds, for something the size of agda-algebras.  Before issue #77 the bound
-- was inert, so its value did not matter; now that it is enforced, a small
-- default would abort exactly the legitimate cold call a user is most likely to
-- make first.  300 s leaves room for that interface build while still bounding a
-- genuinely hung typechecker.  Callers that know their library is warm can lower
-- it with @--timeout@; callers building a very large library from scratch should
-- raise it (the field-test configuration uses 600).
defaultTimeoutSeconds :: Int
defaultTimeoutSeconds = 300

-- | Sensible defaults; the caller should override @agdaFlags@ for their project.
defaultConfig :: AgdaConfig
defaultConfig = AgdaConfig
  { agdaBin     = "agda"
  , agdaFlags   = []
  , agdaTimeout = Just defaultTimeoutSeconds
  , reportExpr  = "reportGoalCtx"
  , agdaVerbose = False
  }

-- | Emit a debug message to stderr, gated by 'agdaVerbose'.
debugLog :: AgdaConfig -> Text -> IO ()
debugLog cfg msg
  | agdaVerbose cfg = TIO.hPutStrLn stderr msg
  | otherwise       = pure ()


-- ---------------------------------------------------------------------------
-- Marker parsing (pure)
--
-- Parses the AGDADOJANG_REQ_BEGIN / END block from Agda's stderr.
-- Matches the line protocol emitted by agda-dojang/agda/AgdaDojang/Debug.agda
-- ---------------------------------------------------------------------------

reqBegin, reqEnd, goalPrefix, ctxPrefix :: Text
reqBegin   = "AGDADOJANG_REQ_BEGIN"
reqEnd     = "AGDADOJANG_REQ_END"
goalPrefix = "AGDADOJANG_GOAL: "
ctxPrefix  = "AGDADOJANG_CTX:"

-- | Parse the (goal, context) from Agda stderr output containing markers.
--
-- Returns @Nothing@ if the markers are not found.
parseGoalContext :: Text -> Maybe (Text, [CtxEntry])
parseGoalContext output = do
  block <- lastSplitOn reqBegin output >>= fstSplitOn reqEnd . snd
  -- Note: foldl' is re-exported from Prelude in GHC 9.10+ (base 4.20+).
  -- If building with GHC 9.8.x, add: import Data.List (foldl')
  let (goal, ctx) = foldl' accumulate ("", []) (T.lines block)
  if T.null goal then Nothing else Just (normaliseWs goal, reverse ctx)
  where
    accumulate :: (Text, [CtxEntry]) -> Text -> (Text, [CtxEntry])
    accumulate (goal, ctx) raw
      -- Goal line: starts with the prefix → begin/replace goal text.
      | T.isPrefixOf goalPrefix (T.strip raw) =
          (T.strip raw & T.drop (T.length goalPrefix) & T.strip, ctx)
      -- Context line: parse it.
      | Just entry <- parseCtxLine raw =
          (goal, entry : ctx)
      -- Marker line: skip.
      | isMarkerLine (T.strip raw) =
          (goal, ctx)
      -- Continuation line: append to goal (if we have one).
      | not (T.null goal) && not (T.null (T.strip raw)) =
          (goal <> " " <> T.strip raw, ctx)
      | otherwise =
          (goal, ctx)

    isMarkerLine s =
      s == "AGDADOJANG_CTX_BEGIN" || s == "AGDADOJANG_CTX_END"
      || T.isPrefixOf reqBegin s || T.isPrefixOf reqEnd s

    -- flip-style helper since we don't have (&) in all base versions
    (&) :: a -> (a -> b) -> b
    x & f = f x
    infixl 1 &


-- | Parse one AGDADOJANG_CTX:<i>:<vis>:<name>: <type> line.
parseCtxLine :: Text -> Maybe CtxEntry
parseCtxLine raw =
  let s = T.strip raw
  in case T.stripPrefix ctxPrefix s of
    Nothing   -> Nothing
    Just rest ->
      -- rest looks like "0:visible:x: A"
      case T.splitOn ":" rest of
        (idxT : visT : nameT : typeParts) ->
          let idx  = readMaybeInt (T.strip idxT)
              vis  = T.strip visT
              name = T.strip nameT
              typ  = normaliseWs . T.strip . T.intercalate ":" $ typeParts
          in  Just CtxEntry
                { ctxName       = name
                , ctxType       = typ
                , ctxVisibility = Just vis
                , ctxIndex      = idx
                }
        _ -> Nothing

-- | Collapse runs of whitespace into single spaces.
normaliseWs :: Text -> Text
normaliseWs = T.unwords . T.words

readMaybeInt :: Text -> Maybe Int
readMaybeInt t = case reads (T.unpack t) of
  [(n, "")] -> Just n
  _         -> Nothing

-- Split helpers (Text doesn't have a convenient lastSplitOn).
lastSplitOn :: Text -> Text -> Maybe (Text, Text)
lastSplitOn needle haystack =
  let parts = T.splitOn needle haystack
  in  if length parts < 2
        then Nothing
        else Just ( T.intercalate needle (init parts)
                  , last parts
                  )

fstSplitOn :: Text -> Text -> Maybe Text
fstSplitOn needle haystack =
  case T.splitOn needle haystack of
    (x : _ : _) -> Just x
    _            -> Nothing


-- ---------------------------------------------------------------------------
-- Agda subprocess (IO)
-- ---------------------------------------------------------------------------

-- | The result of one bounded subprocess: @agda@ on a file, or the
-- whole-project gate 'runCommand' runs for @check_project@ (issue #78).
data AgdaResult = AgdaResult
  { arExitCode  :: Int       -- ^ Process exit code (0 = success, -1 = could not run agda).
  , arStdout    :: Text      -- ^ Captured stdout.
  , arStderr    :: Text      -- ^ Captured stderr.
  , arTimedOut  :: Bool      -- ^ True iff the run hit 'agdaTimeout' and was killed.
                             --   An explicit flag rather than a magic exit code: a
                             --   killed process reports whatever signal took it down
                             --   (-2 for SIGINT, -15 for SIGTERM), which is not
                             --   distinguishable from an ordinary failure.
  , arElapsedMs :: Int       -- ^ Wall-clock duration of the subprocess, in
                             --   milliseconds, from a monotonic clock.
  , arCommand   :: CommandEcho
                             -- ^ The invocation this result came from: binary,
                             --   argument vector, and working directory.  Built
                             --   from the very arguments handed to
                             --   'createProcess', so the echo in a response
                             --   cannot drift from what ran (issue #72).
  } deriving (Eq, Show)

-- | Run the Agda binary on the given file path.
--
-- Captures stdout and stderr separately, since Agda emits most diagnostics on
-- stderr, and bounds the run by 'agdaTimeout' (see the module header for why
-- this cannot be done with 'System.Timeout.timeout' over
-- 'System.Process.readProcessWithExitCode').  Whatever the child managed to
-- write before being killed is still returned, so a timeout that happens to
-- follow real diagnostics does not discard them.
--
-- Failure to /start/ @agda@ at all (missing binary, permission denied) is
-- reported as exit code @-1@ with the exception text on stderr, preserving the
-- pre-existing contract that 'AgdaMCP.Tools.ProofState' reads as @FillCrash@.
runAgda :: AgdaConfig -> FilePath -> IO AgdaResult
runAgda cfg path = runCommand cfg (agdaBin cfg) (agdaFlags cfg <> [path]) Nothing

-- | runCommand: run an arbitrary command under the bound, the drainers, and the
-- kill ladder 'runAgda' uses.
--
-- The generalization issue #78 needs: the whole-project gate is @make@ or an
-- operator-configured command, not @agda@, and it must be bounded and reaped
-- exactly as carefully — more so, since it is the call that legitimately runs
-- for tens of minutes.  Only 'agdaTimeout' and 'agdaVerbose' are read from the
-- config here; the argument vector is passed through verbatim, so a caller that
-- has already assembled its flags is not handed a second copy of them.
--
-- @mCwd@ is the working directory to run in, or 'Nothing' to inherit the
-- server's.  It is not cosmetic: @make@ must run in its Makefile's directory,
-- while an @agda@ invocation whose flags are relative to the server's cwd (the
-- shipped @--library-file=agda/libraries@ is exactly that) must not be moved
-- out from under them.  Whichever it is, the resolved directory is what the
-- 'CommandEcho' reports.
runCommand :: AgdaConfig -> FilePath -> [String] -> Maybe FilePath -> IO AgdaResult
runCommand cfg bin args mCwd = do
  echo    <- commandEchoFor bin args mCwd
  start   <- getMonotonicTimeNSec
  outcome <- try (runProcessBounded cfg bin args mCwd)
  end     <- getMonotonicTimeNSec
  let elapsed = fromIntegral ((end - start) `div` 1_000_000)
  pure $ case outcome of
    Left (err :: SomeException) -> AgdaResult
      { arExitCode  = -1
      , arStdout    = ""
      , arStderr    = "agda-mcp: failed to run " <> T.pack bin <> ": " <> T.pack (show err)
      , arTimedOut  = False
      , arElapsedMs = elapsed
      , arCommand   = echo
      }
    Right (mExit, out, err) -> AgdaResult
      { arExitCode  = maybe (-1) exitCodeToInt mExit
      , arStdout    = out
      , arStderr    = err
      , arTimedOut  = isNothing' mExit
      , arElapsedMs = elapsed
      , arCommand   = echo
      }
  where
    isNothing' Nothing = True
    isNothing' _       = False

-- | commandEchoFor: the 'CommandEcho' for an invocation about to be made.
--
-- Built before the run and from the same @args@ list 'runProcessBounded' passes
-- to 'createProcess', so the echo is the invocation rather than a description of
-- it.  The binary is reported as its resolved absolute path when the configured
-- name is on @PATH@ — inside a Nix shell that name is a wrapper script which
-- supplies flags of its own, and an agent comparing the echo against its own
-- @agda@ needs to know it is looking at the same one.  Resolution is for the
-- report only: 'runProcessBounded' still spawns the name it was given, so no
-- behaviour rides on it, and a name that cannot be resolved is echoed as
-- configured.
commandEchoFor :: FilePath -> [String] -> Maybe FilePath -> IO CommandEcho
commandEchoFor bin args mCwd = do
  mResolved <- findExecutable bin
    `catch` \(_ :: SomeException) -> pure Nothing
  inherited <- getCurrentDirectory `catch` \(_ :: SomeException) -> pure "."
  pure CommandEcho
    { ceBinary = maybe bin id mResolved
    , ceArgs   = args
    , ceCwd    = maybe inherited id mCwd
    }

exitCodeToInt :: ExitCode -> Int
exitCodeToInt ExitSuccess     = 0
exitCodeToInt (ExitFailure n) = n

-- | runProcessBounded: spawn the command, drain both streams, race against the
-- timeout.
--
-- Returns @(Just exitCode, stdout, stderr)@ on a completed run and
-- @(Nothing, …)@ when the timeout fired and the process group was killed.
-- Throws only if the process could not be created at all; 'runCommand' catches
-- that and maps it to exit code -1.
runProcessBounded
  :: AgdaConfig -> FilePath -> [String] -> Maybe FilePath
  -> IO (Maybe ExitCode, Text, Text)
runProcessBounded cfg bin args mCwd =
  bracket acquire cleanup $ \(handles, mPgid) ->
    case handles of
      (mIn, Just hOut, Just hErr, ph) -> do
        -- Agda reads nothing from stdin in batch mode, and neither should a
        -- project gate; close our end at once so the child sees EOF rather than
        -- blocking if it ever tries.
        maybe (pure ()) (ignoringIOErrors . hClose) mIn
        outVar <- drainAsync hOut
        errVar <- drainAsync hErr
        raceProcess cfg ph mPgid outVar errVar
      -- createProcess with CreatePipe on both streams always yields both
      -- handles; this branch exists only to keep the match total.
      _ -> pure (Just (ExitFailure (-1)), "", "agda-mcp: could not open the command's output pipes")
  where
    spec = (proc bin args)
      { std_in  = CreatePipe
      , std_out = CreatePipe
      , std_err = CreatePipe
      , cwd     = mCwd
        -- Its own process group, so group-wide signals reach any descendant the
        -- command spawned rather than just the command itself — @agda@'s own
        -- children, or every @agda@ a @make@ gate started.
      , create_group = True
      }

    -- The child's pgid is captured here, before any thread can 'waitForProcess'
    -- it: 'getPid' reads Nothing once the leader has been reaped, and the
    -- timeout ladder must still be able to reach *descendants* after the leader
    -- itself has fallen (a leader dying to SIGINT while a SIGINT-ignoring
    -- descendant survives is exactly the case the orphan test pins).
    -- @create_group = True@ makes the child a group leader, so pid = pgid.
    acquire = do
      handles@(_, _, _, ph) <- createProcess spec
      mPgid <- getPid ph
      pure (handles, mPgid)

    -- Deliberately not 'System.Process.cleanupProcess': that closes the stdout
    -- and stderr handles, and closing a handle another thread is mid-read on
    -- blocks on the handle lock — precisely the hang this whole change exists to
    -- remove.  The drainer threads own those two handles and close them
    -- themselves ('BS.hGetContents' closes at EOF), so all this needs to do is
    -- guarantee the child is signalled and reaped on every exit path, including
    -- an async exception mid-run.
    cleanup ((mIn, _, _, ph), mPgid) = do
      maybe (pure ()) (ignoringIOErrors . hClose) mIn
      ignoringIOErrors (interruptProcessGroupOf ph)
      signalGroupVia mPgid softwareTermination
      ignoringIOErrors (terminateProcess ph)
      -- Reap on a detached thread (a blocked 'waitForProcess' sits in a foreign
      -- call, so doing it inline could stall an async-exception unwind), and
      -- escalate to a group SIGKILL if anything ignores the SIGTERM above.
      -- After the normal paths the group is already gone and the leader reaped,
      -- so every step here is a no-op.
      void . forkIO $ do
        _ <- forkIO $ do
          threadDelay termGraceMicros
          alive <- groupAlive mPgid
          when alive (signalGroupVia mPgid killProcess)
        void (waitForProcess ph)

-- | raceProcess: wait for the process, or for the timeout, whichever comes first.
raceProcess
  :: AgdaConfig -> ProcessHandle -> Maybe Pid -> MVar Text -> MVar Text
  -> IO (Maybe ExitCode, Text, Text)
raceProcess cfg ph mPgid outVar errVar = do
  -- 'exitVar' is the reaped exit status; 'raceVar' is the first-past-the-post
  -- signal, holding @Just ec@ if agda finished and @Nothing@ if the timer won.
  exitVar <- newEmptyMVar
  raceVar <- newEmptyMVar
  _       <- forkIO $ do
    ec <- waitForProcess ph
    putMVar exitVar ec
    void (tryPutMVar raceVar (Just ec))
  timer <- case boundedTimeout cfg of
    Nothing   -> pure Nothing
    Just secs -> fmap Just . forkIO $ do
      threadDelay (secs * 1_000_000)
      void (tryPutMVar raceVar Nothing)
  outcome <- takeMVar raceVar
  maybe (pure ()) killThread timer
  case outcome of
    Just ec -> do
      -- agda exited on its own, so both pipes are at EOF and the drainers are
      -- about to finish.  The bound is a pure backstop against a descendant that
      -- outlived agda and still holds a write end: everything agda itself wrote
      -- is already buffered and reads in milliseconds, so it can never truncate
      -- real output — but without it, such a descendant would hang the tool call
      -- forever, which is the failure mode this change exists to remove.
      out <- takeMVarWithin postExitDrainMicros outVar
      err <- takeMVarWithin postExitDrainMicros errVar
      pure (Just ec, orEmpty out, orEmpty err)
    Nothing -> do
      -- Timed out.  Escalate group-wide — SIGINT first (agda unwinds and may
      -- still print), then SIGTERM, then SIGKILL — advancing a rung while the
      -- process GROUP still has members, not merely while the leader remains
      -- unreaped.  The distinction is load-bearing twice over: a descendant
      -- can ignore SIGINT while the leader falls to it (POSIX starts the
      -- background children of non-interactive shells with SIGINT ignored, so
      -- the orphan fixture builds exactly this), and a ladder keyed on the
      -- leader would then stop with the descendant still running; conversely a
      -- leader that ignored SIGTERM must not stall the ladder short of
      -- SIGKILL.  SIGKILL can be neither caught nor ignored, so past the last
      -- rung only a kernel-stuck process can survive the bounded waits.  The
      -- final reap goes through 'exitVar' rather than killing 'waiter': a
      -- thread blocked in 'waitForProcess' sits in a foreign call, so
      -- 'killThread' on it could block indefinitely.  Letting it complete is
      -- what leaves no zombie.
      ignoringIOErrors (interruptProcessGroupOf ph)
      intGone <- waitGroupGone mPgid exitVar interruptGraceMicros
      termGone <-
        if intGone then pure True
        else do
          signalGroupVia mPgid softwareTermination
          -- Belt and braces: reach the leader through the handle too, in case
          -- the pgid was unavailable at spawn time.
          ignoringIOErrors (terminateProcess ph)
          waitGroupGone mPgid exitVar termGraceMicros
      when (not termGone) $ do
        signalGroupVia mPgid killProcess
        void (waitGroupGone mPgid exitVar reapGraceMicros)
      -- Reap the leader (bounded, so an unreapable process cannot hang the
      -- call); with the group gone this returns immediately.
      _ <- takeMVarWithin reapGraceMicros exitVar
      out <- takeMVarWithin drainGraceMicros outVar
      err <- takeMVarWithin drainGraceMicros errVar
      pure (Nothing, orEmpty out, orEmpty err)
  where
    orEmpty = maybe "" id

-- | boundedTimeout: the effective bound, treating a non-positive number the way
-- command-line tools conventionally do — as "no limit" — rather than as an
-- instant abort.
boundedTimeout :: AgdaConfig -> Maybe Int
boundedTimeout cfg = case agdaTimeout cfg of
  Just secs | secs > 0 -> Just secs
  _                    -> Nothing

-- | How long SIGINT gets to work before SIGTERM follows.
interruptGraceMicros :: Int
interruptGraceMicros = 250_000

-- | How long SIGTERM gets to work before SIGKILL follows.
termGraceMicros :: Int
termGraceMicros = 2_000_000

-- | How long to wait for the SIGKILLed process to be reaped.
reapGraceMicros :: Int
reapGraceMicros = 5_000_000

-- | signalGroupVia: send @sig@ to the child's whole process group, best-effort,
-- through the pgid captured at spawn time.  A group that has since emptied
-- makes 'signalProcessGroup' fail with ESRCH, which 'ignoringIOErrors'
-- swallows; a group that emptied *and* had its pgid recycled between the probe
-- and the signal is the standard, vanishingly-narrow @killpg@ race every
-- timeout implementation accepts (the kernel does not reuse a pgid while the
-- group still has members).
signalGroupVia :: Maybe Pid -> Signal -> IO ()
signalGroupVia mPgid sig = case mPgid of
  Just pgid -> ignoringIOErrors (signalProcessGroup sig pgid)
  Nothing   -> pure ()

-- | groupAlive: does the child's process group still have members?  Probed
-- with the null signal (@kill(-pgid, 0)@), which delivers nothing but reports
-- ESRCH on an empty group.  Without a pgid the probe cannot be asked, and
-- "assume dead" is the reading that keeps the caller from signalling blindly.
groupAlive :: Maybe Pid -> IO Bool
groupAlive Nothing     = pure False
groupAlive (Just pgid) =
  (signalProcessGroup nullSignal pgid >> pure True)
    `catch` \(_ :: SomeException) -> pure False

-- | waitGroupGone: wait (bounded) for the child's process group to empty;
-- True iff it did.  This polls, which the module otherwise avoids on latency
-- grounds — but it runs only on the timeout path, never on a healthy call,
-- and group death has no blocking primitive to wait on the way a single
-- process does.  Without a pgid it falls back to the leader's reap, the best
-- signal still available.
waitGroupGone :: Maybe Pid -> MVar ExitCode -> Int -> IO Bool
waitGroupGone Nothing exitVar budget = do
  r <- takeMVarWithin budget exitVar
  pure (case r of Just _ -> True; Nothing -> False)
waitGroupGone mPgid _ budget = go budget
  where
    stepMicros = 50_000
    go b = do
      alive <- groupAlive mPgid
      if not alive
        then pure True
        else if b <= 0
          then pure False
          else do
            threadDelay (min stepMicros b)
            go (b - stepMicros)

-- | How long to wait for a stream drainer to reach EOF after the kill.
drainGraceMicros :: Int
drainGraceMicros = 2_000_000

-- | How long to wait for the drainers after agda exited of its own accord.
-- Generous, because giving up here /would/ lose real diagnostics; it exists only
-- so that a descendant holding a pipe open cannot hang the call forever.
postExitDrainMicros :: Int
postExitDrainMicros = 60_000_000

-- | drainAsync: read a handle to EOF on its own thread, so neither stream can
-- fill its pipe buffer and deadlock the other (the classic reason to drain
-- concurrently rather than sequentially).
--
-- Bytes are decoded as UTF-8 leniently rather than through the handle's locale
-- encoding: Agda's output is UTF-8 and routinely carries the goal's Unicode
-- (@≡@, @→@, @⊤@), which a @C@-locale handle would mangle or reject.
drainAsync :: Handle -> IO (MVar Text)
drainAsync h = do
  var <- newEmptyMVar
  _   <- forkIO $ do
    r <- try (hSetBinaryMode h True >> BS.hGetContents h)
    putMVar var $ case r of
      Left (_ :: SomeException) -> ""
      Right bytes               -> TE.decodeUtf8With lenientDecode bytes
  pure var

-- | takeMVarWithin: read an 'MVar', giving up after a deadline.
--
-- Blocking rather than polling, so the overwhelmingly common case — the value is
-- already there, or lands a scheduler tick later — costs nothing; a poll loop
-- would tax every single agda call with its interval.  The deadline exists only
-- so that a stuck producer cannot hang the whole tool call.
--
-- 'readMVar' rather than 'takeMVar': if the reader thread wins the value but
-- loses the race to the timer, the value stays in the 'MVar' rather than being
-- silently swallowed.
takeMVarWithin :: forall a. Int -> MVar a -> IO (Maybe a)
takeMVarWithin micros var = do
  gate   <- newEmptyMVar
  reader <- forkIO $ do
    x <- readMVar var
    void (tryPutMVar gate (Just x))
  timer  <- forkIO $ do
    threadDelay micros
    void (tryPutMVar gate Nothing)
  result <- takeMVar gate
  -- Both are blocked on interruptible operations ('readMVar' / 'threadDelay'),
  -- so neither killThread can stall.
  killThread timer
  killThread reader
  pure result

-- | ignoringIOErrors: best-effort signalling.  A process that has already exited
-- makes 'terminateProcess' / 'interruptProcessGroupOf' fail, which is not an
-- error we need to surface.
ignoringIOErrors :: IO () -> IO ()
ignoringIOErrors act = act `catch` \(_ :: SomeException) -> pure ()

-- | timeoutMessage: the human-readable explanation attached to a timed-out tool
-- response.  Names the bound that was hit and what to do about it, since the
-- overwhelmingly likely cause is a cold interface build rather than a real hang.
timeoutMessage :: AgdaConfig -> Text
timeoutMessage cfg =
  "agda timed out after " <> T.pack (show secs) <> "s"
  <> " (raise --timeout if this is a cold first check that must build .agdai"
  <> " interfaces for a large library)"
  where
    secs = maybe defaultTimeoutSeconds id (boundedTimeout cfg)


-- ---------------------------------------------------------------------------
-- Agda's progress lines: was it re-checked, and which module is it?
-- ---------------------------------------------------------------------------

-- | checkedFromSourceOf: did Agda re-typecheck the module from source, or did it
-- reuse an already-built interface?
--
-- A coarse but reliable cache signal, and the one an agent actually needs: it
-- explains why the same call took 200 ms once and three minutes the time before.
-- The evidence, in order of authority (Agda 2.8.0 at default verbosity):
--
--   * A @Checking M (…/M.agda).@ line is printed the moment Agda starts
--     re-typechecking a module from source — including runs that then fail or
--     are killed mid-check — and reads as @Just True@.
--   * A run that /completed successfully/ without one reads as @Just False@:
--     a warm @agda@ exits 0 printing nothing at all, so silent success is
--     itself the interface-reuse signature.
--   * A @Loading M (…/M.agdai).@ line (emitted only at raised verbosity) is
--     direct evidence of an interface read, so it also reads as @Just False@
--     when no source re-check was observed.
--   * Anything else — a run that failed or timed out before producing any
--     evidence — is @Nothing@, and the response omits the field.  Defaulting
--     to a Bool here would misread a startup failure or an early-killed cold
--     call as a warm one.
checkedFromSourceOf :: AgdaResult -> Maybe Bool
checkedFromSourceOf r
  | sawPrefix "Checking " = Just True
  | completedOk           = Just False
  | sawPrefix "Loading "  = Just False
  | otherwise             = Nothing
  where
    combined    = arStdout r <> "\n" <> arStderr r
    sawPrefix p = any (T.isPrefixOf p . T.stripStart) (T.lines combined)
    completedOk = not (arTimedOut r) && arExitCode r == 0


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

-- | agdaModuleNameOf: the module name /Agda/ resolved for a file, read from its
-- own progress line rather than from the file's text.
--
-- This is the authoritative answer to "what module is this?", and the one to
-- prefer: Agda derives it from where the file sits on the include path, so it is
-- the name an @import@ must use and the name Agda's own messages print —
-- @Proofs.Use@ for a hierarchical module, @AnonModule@ for a file whose header
-- reads @module _ where@, and never a name that merely /looks/ like a header
-- somewhere in the source (issue #100).
--
-- It is a 'Maybe' because Agda does not always say.  A warm run prints nothing
-- at all; a run that dies before type-checking starts — a parse error, a header
-- that does not match its file name, a timeout — never reaches the line; and a
-- client that puts @--trace-imports=0@ in its flags silences the line outright
-- (measured: levels 1 and up print it, 0 prints nothing).
-- The caller falls back to the name the source /declares/, which is exactly the
-- answer those cases call for: what the file claims to be is the diagnosis when
-- Agda will not accept the claim.  A run may also announce several modules (its
-- dependencies), so the answer is the line naming /this/ file rather than the
-- first line seen.
agdaModuleNameOf :: FilePath -> AgdaResult -> Maybe Text
agdaModuleNameOf path r =
  listToMaybe
    [ name
    | (name, announced) <- progressModules (arStdout r <> "\n" <> arStderr r)
    , equalFilePath announced path
    ]
