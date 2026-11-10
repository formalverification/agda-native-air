-- | AgdaStamp.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/AgdaStamp.hs
--
-- Description:
--   The stamp of the Agda that a spawn of @--agda-bin@ would start (issue
--   #347).  The interaction lane takes one before it spawns a child, keeps it
--   with the lane, and takes another before it reuses the lane; when the two
--   differ the lane is restarted instead of answering from an Agda the server
--   would no longer start.  The batch tools start a new Agda for every call
--   and need no stamp; their peek at a warm lane ('peekLoadedGoals') compares
--   one, since it reads what an older Agda loaded.
--
--   How this fits: 'AgdaMCP.Interaction' owns the lanes and calls
--   'agdaStampForReuse' and 'agdaStampForSpawn'; 'AgdaMCP.Types.AgdaStamp' is
--   the record (and its echo, @lane.agdaStamp@ on a verbose answer).
--
-- Design notes (each measured or probed, 2026-11-08):
--
--   * The stamp has three parts, for the three ways a registration's Agda
--     changes under a living lane (the setups of
--     docs/agda-mcp/registering-a-project.md):
--
--     - A pin (a gc-root symlink) rebuilt, or any symlink re-pointed: the
--       real path of @--agda-bin@, every symlink followed, changes.
--     - A dev shell's per-checkout wrapper (agda-algebras' @.agda/bin/agda@)
--       rewritten to name another store path: the wrapper's bytes change.
--       The bytes, not the metadata: the shell rewrites the wrapper on every
--       entry (@cat >@), so its modification time changes when nothing else
--       does (three entries in a row, measured: one sha256, three mtimes).
--       A stamp of size and mtime would restart every lane at every
--       @nix develop@.  So a file up to 'smallFileLimit' is fingerprinted
--       (FNV-1a, as the lane's file stamp is); a larger file is an Agda
--       binary, whose real path already names its store path, and its size
--       and mtime catch the rare binary rebuilt in place.
--     - A launcher whose own path and bytes never change but whose choice
--       does (@scripts/agda-for-flake.sh@, keyed by the checkout's lock and
--       other non-Agda files): only the launcher can say, so an optional
--       identity command (@--agda-identity-command@, run with no shell in the
--       server's working directory, where the launcher runs too) prints a
--       name for the Agda it would start, and its output joins the stamp.
--
--   * Cost.  The first two parts are a path resolution, a stat, and the read
--     of at most 64 KiB: 18 to 45 microseconds per lane call (2,000 stamps
--     each of this repository's flake wrapper, agda-algebras' wrapper, and
--     agda-for-flake.sh, the largest at 12 KiB).  The identity command is a
--     process: 15 ms for the launcher's @--print-key@ on
--     formal-ledger-specifications (median of 30), and a second for a flake
--     outside git (its key is a @nix eval@).  So its output is cached for
--     'agdaIdentityTtl' seconds (default 2), measured from the run.  The
--     bound on staleness is the time-to-live; the bound on cost is one run
--     per time-to-live.  An agent's lane calls arrive a model turn apart (a
--     few seconds), so for an agent nearly every call runs it and a lock
--     moved between two calls is always seen; a scripted client (the
--     proof-search loop) that calls many times a second pays once per two
--     seconds.  A spawn always takes a fresh run (it is paying seconds for
--     the spawn anyway), so a lane's stamp is never older than the lane.
--
--   * A failed identity command is part of the stamp, as text that names the
--     failure, never an error: a launcher that cannot say which Agda it would
--     start (no flake, no lock) cannot start one either, so the lane is
--     restarted and the spawn reports the launcher's own refusal.
--
--   * Order.  A spawn's stamp is taken BEFORE the child starts.  A change
--     between the stamp and the spawn then leaves a stamp older than the
--     child, and the next call restarts the lane once more than needed; the
--     reverse order could record a stamp newer than the child and keep a
--     stale lane forever.

{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module AgdaMCP.AgdaStamp
  ( -- * The stamp
    AgdaStamp (..)
  , binaryStampOf
  , smallFileLimit
    -- * The identity command and its cache
  , IdentityCache
  , newIdentityCache
  , agdaStampForReuse
  , agdaStampForSpawn
  , identityTimeoutSeconds
    -- * The fingerprint (shared with the lane's file stamp)
  , fnv1a
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar, newMVar)
import Control.Exception (IOException, try)
import Data.Bits (xor)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import Numeric (showHex)
import System.Directory
  (canonicalizePath, findExecutable, getFileSize, getModificationTime)
import System.FilePath (isPathSeparator)
import System.Posix.Files (getFileStatus, isRegularFile)

import AgdaMCP.Agda (AgdaConfig (..), AgdaResult (..), runCommand)
import AgdaMCP.Types (AgdaStamp (..))


-- ---------------------------------------------------------------------------
-- The path and contents parts
-- ---------------------------------------------------------------------------

-- | smallFileLimit: files up to this size are fingerprinted by their bytes.
-- A wrapper script is a few hundred bytes (agda-algebras': 396;
-- agda-for-flake.sh: 11 KiB); an Agda binary is tens of megabytes.
smallFileLimit :: Integer
smallFileLimit = 64 * 1024

-- | binaryStampOf: the path and contents parts of the stamp of @--agda-bin@.
--
-- A name without a path separator is looked up on @PATH@, as the spawn's
-- @execvp@ does; a relative path resolves against the server's working
-- directory, as the spawn's does.  Every failure is a value: a stamp that
-- names why it could not read the file stays equal to itself while nothing
-- changes, and differs from the stamp of a file that appears.
--
-- Only a regular file is read.  A FIFO or a device is size 0, so it would be
-- fingerprinted, and reading one can block for as long as a writer holds it
-- open (or, for @/dev/zero@, never end), under the slot's lock with no
-- deadline over it (a Copilot catch on PR 349).  Such a path cannot be
-- executed anyway; its stamp says what it is, and the spawn reports the
-- failure.
binaryStampOf :: FilePath -> IO (Text, Text)
binaryStampOf bin = do
  located <- if any isPathSeparator bin
               then pure (Just bin)
               else findExecutable bin
  case located of
    Nothing   -> pure ("not found on PATH: " <> T.pack bin, "none")
    Just path -> do
      real <- either (\(_ :: IOException) -> path) id <$> try (canonicalizePath path)
      contents <- contentsOf real
      pure (T.pack real, contents)
  where
    contentsOf real = do
      status <- try (getFileStatus real)
      case status of
        Left (_ :: IOException) -> pure "unreadable"
        Right st
          | isRegularFile st -> regularContents real
          | otherwise        -> pure "not a regular file"

    regularContents real = do
      sized <- try (getFileSize real)
      case sized of
        Left (_ :: IOException) -> pure "unreadable"
        Right size
          | size <= smallFileLimit -> do
              bytes <- try (BS.readFile real)
              pure $ case bytes of
                Left (_ :: IOException) -> "unreadable"
                Right bs -> "fnv1a " <> T.pack (showHex (fnv1a bs) "")
          | otherwise -> do
              mtime <- try (getModificationTime real)
              pure $ case mtime of
                Left (_ :: IOException) -> "size " <> T.pack (show size)
                Right t -> "size " <> T.pack (show size) <> ", modified " <> T.pack (show t)

-- | fnv1a: the 64-bit FNV-1a fingerprint of a byte string.  Not
-- cryptographic and not meant to be: it distinguishes edits, not
-- adversaries, and it costs no dependency.
fnv1a :: BS.ByteString -> Word64
fnv1a = BS.foldl' step 0xcbf29ce484222325
  where
    step h b = (h `xor` fromIntegral b) * 0x100000001b3


-- ---------------------------------------------------------------------------
-- The identity command
-- ---------------------------------------------------------------------------

-- | IdentityCache: the last run of the identity command, shared by every lane
-- of one registry (the command names the Agda the server would start, which
-- is one Agda whatever the root: every lane's child runs in the server's
-- working directory).  Keyed by the command, so a registry handed two
-- configurations (the test suite does) never answers one with the other's
-- output.  The 'MVar' serializes runs.
newtype IdentityCache = IdentityCache (MVar (Maybe IdentityRun))

data IdentityRun = IdentityRun
  { irCommand :: [String]
  , irAt      :: Word64   -- ^ Monotonic nanoseconds when the run began.
  , irOutput  :: Text
  }

newIdentityCache :: IO IdentityCache
newIdentityCache = IdentityCache <$> newMVar Nothing

-- | identityTimeoutSeconds: the bound on one identity run (or the server's
-- @--timeout@, when that is smaller).  The launcher's key takes 15 ms, or a
-- second outside git; a command that takes longer than this is broken, and
-- its timeout becomes the stamp's text like any other failure.
identityTimeoutSeconds :: Int
identityTimeoutSeconds = 30

-- | agdaStampForReuse: the stamp to compare with a living lane's, the
-- identity part no older than the configured time-to-live.
agdaStampForReuse :: IdentityCache -> AgdaConfig -> IO AgdaStamp
agdaStampForReuse cache cfg = do
  now <- getMonotonicTimeNSec
  let ttlNs = fromIntegral (max 0 (agdaIdentityTtl cfg)) * 1_000_000_000 :: Word64
      -- A time-to-live of 0 accepts no earlier run: the run must begin now.
      oldest | ttlNs == 0  = now
             | now > ttlNs = now - ttlNs
             | otherwise   = 0
  stampAsOf cache cfg oldest

-- | agdaStampForSpawn: the stamp to keep with a lane about to be spawned,
-- the identity part from a run that began no earlier than the given moment
-- (the request's start), so a comparison that just ran the command is not
-- run twice and a lane's stamp is never older than its request.
agdaStampForSpawn :: IdentityCache -> AgdaConfig -> Word64 -> IO AgdaStamp
agdaStampForSpawn = stampAsOf

stampAsOf :: IdentityCache -> AgdaConfig -> Word64 -> IO AgdaStamp
stampAsOf cache cfg oldest = do
  (path, contents) <- binaryStampOf (agdaBin cfg)
  identity <- case agdaIdentityCommand cfg of
    Just cmd@(_ : _) -> Just <$> identityAsOf cache cfg cmd oldest
    _                -> pure Nothing
  pure AgdaStamp { asPath = path, asContents = contents, asIdentity = identity }

-- | identityAsOf: the command's output from a run that began at or after
-- @oldest@, running it if the cached run is older or was of another command.
identityAsOf :: IdentityCache -> AgdaConfig -> [String] -> Word64 -> IO Text
identityAsOf (IdentityCache ref) cfg cmd oldest = modifyMVar ref $ \cached ->
  case cached of
    Just run | irCommand run == cmd, irAt run >= oldest -> pure (cached, irOutput run)
    _ -> do
      at  <- getMonotonicTimeNSec
      out <- runIdentity cfg cmd
      pure (Just (IdentityRun cmd at out), out)

-- | runIdentity: one bounded run, through the batch lane's 'runCommand' (its
-- process group, drainers, and kill ladder), in the server's working
-- directory.  A cancellation (an asynchronous exception) is not a failure:
-- 'runCommand' rethrows it, and 'identityAsOf''s 'modifyMVar' then leaves
-- the cache as it was, so no stamp is made of it.  Standard output, trimmed, is the identity; anything else is a
-- failure named by how it failed, without the varying stderr, so a command
-- that keeps failing the same way keeps the same stamp.
runIdentity :: AgdaConfig -> [String] -> IO Text
runIdentity _   []           = pure ""
runIdentity cfg (bin : args) = do
  let bound = case agdaTimeout cfg of
        Just s | s > 0 -> min s identityTimeoutSeconds
        _              -> identityTimeoutSeconds
  r <- runCommand cfg { agdaTimeout = Just bound } bin args Nothing
  pure $ case () of
    _ | arTimedOut r       -> "failed: timed out after " <> T.pack (show bound) <> " s"
      | arExitCode r == 0  -> T.strip (arStdout r)
      | arExitCode r == -1 -> "failed: could not run " <> T.pack bin
      | otherwise          -> "failed: exit " <> T.pack (show (arExitCode r))
