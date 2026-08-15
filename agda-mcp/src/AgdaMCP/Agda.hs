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
--   'interruptProcessGroupOf' (SIGINT to the whole group, so any descendant
--   dies too), then 'terminateProcess', then reap with 'waitForProcess' — so no
--   zombie and no orphan survives the call.  A timeout is reported as a /value/
--   ('arTimedOut'), never an exception, which is what lets the in-place tools'
--   'Control.Exception.bracket_' restore run on the timeout path exactly as it
--   does on the success path.

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
    -- * Agda subprocess (IO)
  , runAgda
  , AgdaResult (..)
  , timeoutMessage
  ) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar
  (MVar, newEmptyMVar, putMVar, readMVar, takeMVar, tryPutMVar)
import Control.Exception (SomeException, bracket, catch, try)
import Control.Monad (void)
import qualified Data.ByteString as BS
import Data.Text.IO as TIO
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import GHC.Clock (getMonotonicTimeNSec)
import System.Exit (ExitCode (..))
import System.IO (Handle, hClose, hSetBinaryMode, stderr)
import System.Process
  ( CreateProcess (..), ProcessHandle, StdStream (..)
  , createProcess, interruptProcessGroupOf, proc
  , terminateProcess, waitForProcess
  )

import AgdaMCP.Types (CtxEntry (..))


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

-- | The result of running Agda on a file.
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
runAgda cfg path = do
  let args = agdaFlags cfg <> [path]
  start   <- getMonotonicTimeNSec
  outcome <- try (runAgdaProcess cfg args)
  end     <- getMonotonicTimeNSec
  let elapsed = fromIntegral ((end - start) `div` 1_000_000)
  pure $ case outcome of
    Left (err :: SomeException) -> AgdaResult
      { arExitCode  = -1
      , arStdout    = ""
      , arStderr    = "agda-mcp: failed to run agda: " <> T.pack (show err)
      , arTimedOut  = False
      , arElapsedMs = elapsed
      }
    Right (mExit, out, err) -> AgdaResult
      { arExitCode  = maybe (-1) exitCodeToInt mExit
      , arStdout    = out
      , arStderr    = err
      , arTimedOut  = isNothing' mExit
      , arElapsedMs = elapsed
      }
  where
    isNothing' Nothing = True
    isNothing' _       = False

exitCodeToInt :: ExitCode -> Int
exitCodeToInt ExitSuccess     = 0
exitCodeToInt (ExitFailure n) = n

-- | runAgdaProcess: spawn @agda@, drain both streams, race against the timeout.
--
-- Returns @(Just exitCode, stdout, stderr)@ on a completed run and
-- @(Nothing, …)@ when the timeout fired and the process group was killed.
-- Throws only if the process could not be created at all; 'runAgda' catches
-- that and maps it to exit code -1.
runAgdaProcess
  :: AgdaConfig -> [String] -> IO (Maybe ExitCode, Text, Text)
runAgdaProcess cfg args =
  bracket (createProcess spec) cleanup $ \handles ->
    case handles of
      (mIn, Just hOut, Just hErr, ph) -> do
        -- Agda reads nothing from stdin in batch mode; close our end at once so
        -- it sees EOF rather than blocking if it ever tries.
        maybe (pure ()) (ignoringIOErrors . hClose) mIn
        outVar <- drainAsync hOut
        errVar <- drainAsync hErr
        raceProcess cfg ph outVar errVar
      -- createProcess with CreatePipe on both streams always yields both
      -- handles; this branch exists only to keep the match total.
      _ -> pure (Just (ExitFailure (-1)), "", "agda-mcp: could not open agda's output pipes")
  where
    spec = (proc (agdaBin cfg) args)
      { std_in  = CreatePipe
      , std_out = CreatePipe
      , std_err = CreatePipe
        -- Its own process group, so 'interruptProcessGroupOf' reaches any
        -- descendant agda spawned rather than just agda itself.
      , create_group = True
      }

    -- Deliberately not 'System.Process.cleanupProcess': that closes the stdout
    -- and stderr handles, and closing a handle another thread is mid-read on
    -- blocks on the handle lock — precisely the hang this whole change exists to
    -- remove.  The drainer threads own those two handles and close them
    -- themselves ('BS.hGetContents' closes at EOF), so all this needs to do is
    -- guarantee the child is signalled and reaped on every exit path, including
    -- an async exception mid-run.
    cleanup (mIn, _, _, ph) = do
      maybe (pure ()) (ignoringIOErrors . hClose) mIn
      ignoringIOErrors (interruptProcessGroupOf ph)
      ignoringIOErrors (terminateProcess ph)
      void (forkIO (void (waitForProcess ph)))

-- | raceProcess: wait for the process, or for the timeout, whichever comes first.
raceProcess
  :: AgdaConfig -> ProcessHandle -> MVar Text -> MVar Text
  -> IO (Maybe ExitCode, Text, Text)
raceProcess cfg ph outVar errVar = do
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
      -- Timed out.  SIGINT the group first (agda unwinds and may print), then
      -- SIGTERM as a backstop, then let 'waiter' reap it.
      ignoringIOErrors (interruptProcessGroupOf ph)
      threadDelay interruptGraceMicros
      ignoringIOErrors (terminateProcess ph)
      -- Wait for the reap rather than killing 'waiter': a thread blocked in
      -- 'waitForProcess' sits in a foreign call, so 'killThread' on it could
      -- block indefinitely.  Letting it complete is what leaves no zombie.
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

-- | How long to wait for the killed process to be reaped.
reapGraceMicros :: Int
reapGraceMicros = 5_000_000

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


-- | checkedFromSourceOf: did Agda re-typecheck the module from source, or did it
-- reuse an already-built interface?
--
-- A coarse but reliable cache signal, and the one an agent actually needs: it
-- explains why the same call took 200 ms once and three minutes the time before.
-- Agda announces the two cases distinctly — @Checking M (…/M.agda).@ when it
-- typechecks source, @Loading M (…/M.agdai).@ when it reads an interface — so we
-- report 'True' exactly when a @Checking@ line is present.  Absence of any such
-- line (a run that failed before it got that far, or a timeout killed early)
-- reports 'False': this is a hint, not a verdict, and the conservative reading is
-- "no evidence of a source re-check".
checkedFromSourceOf :: Text -> Bool
checkedFromSourceOf out =
  any (T.isPrefixOf "Checking " . T.stripStart) (T.lines out)
