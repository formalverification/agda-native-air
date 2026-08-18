-- | Path.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Path.hs
--
-- Description:
--   Turning a path the client sent into a file this server can read — and
--   failing by name when it cannot (issue #101).
--
--   Every file-taking tool starts here, before 'AgdaMCP.Project' decides which
--   library tree the file belongs to and long before Agda is started.  The two
--   questions are deliberately separate and deliberately in this order: there
--   is no tree to resolve for a file that is not there, and "that file does not
--   exist" is the root cause a caller needs, not "that library is registered
--   elsewhere" said about a path naming nothing.
--
--   The rule this module publishes, and the reasoning behind it:
--
--   * A relative path is resolved against __the server's own working
--     directory__, and against nothing else.  The server is a separate process
--     from the client; @scripts\/run-server.sh@ deliberately @cd@s to the
--     agda-native-air checkout before exec (issue #76's stray-directory fix),
--     so its working directory is normally /not/ the client's project.  This is
--     the only resolution the server can perform honestly: it is never told
--     where the client stands.
--   * Which is why the resolution must now be /checked/.  A relative path that
--     resolves to a file that is really there was meant for this tree — that is
--     the in-repo client, whose working directory is the server's, and whose
--     repo-root-relative paths have always worked.  A relative path that
--     resolves to nothing is issue #101's field failure, and it is refused with
--     a 'AgdaMCP.Types.PathFailure' naming the path as resolved, the working
--     directory it was resolved against, the rule, and the fix.
--   * The alternative — guessing: trying the relative path under each library
--     root in the registry and taking a unique hit — was considered and
--     rejected.  It would have made the field call succeed, but it reintroduces
--     precisely the hazard issue #76 refuses: a green answer about a tree the
--     caller never named.  A registry pointing at a stale worktree would make
--     that guess wrong /and/ silent, since the file's own @*.agda-lib@ would
--     agree with the registry and the mismatch check would not fire.  This
--     codebase prefers a loud refusal to a clever guess.
--   * The protocol-correct third option is MCP @roots\/list@: Claude Code
--     advertises @capabilities.roots.listChanged@ in its @initialize@ request,
--     so a server may ask the client where it stands.  That needs a
--     bidirectional transport — the loop in 'AgdaMCP.Server' reads a request
--     and answers it, with no correlation table for server-initiated requests —
--     plus capability negotiation and @notifications\/roots\/list_changed@
--     handling.  That is a transport change rather than a bug fix, and it would
--     not remove the need for any of the above: a root still has to be checked,
--     and a missing file still has to fail by name.  Left as a follow-up.
--
--   The second defect is here too.  'BS.readFile' throws an 'IOException' on a
--   file that is missing, unreadable, or vanishes between the check and the
--   read; unguarded in a tool handler, that escaped to the client as a bare
--   @-32603 Internal error@ — the message that ended the only adoption attempt
--   the issue-#83 field test observed.  'withSourceFile' is the single place
--   the read happens, so no handler can forget the guard.

{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module AgdaMCP.Path
  ( -- * The one entry point for the file-taking tools
    withSourceFile
    -- * Resolution on its own (exposed for @check_project@ and for testing)
  , resolveRequestedFile
  , resolveRequestedAnchor
    -- * Decoding
  , decodeError
  ) where

import Control.Exception (IOException, try)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (UnicodeException)

import System.Directory
  ( doesDirectoryExist, doesFileExist, getCurrentDirectory, makeAbsolute )
import System.FilePath (isAbsolute, takeDirectory)

import AgdaMCP.Types
  ( PathFailure (..), PathProblem (..), ToolFailure (..) )


-- ---------------------------------------------------------------------------
-- The entry point
-- ---------------------------------------------------------------------------

-- | withSourceFile: resolve the client's @filePath@, read the file, and run the
-- tool body on it — or fail loudly, by name, having run nothing.
--
-- The body receives three things, in the order the handlers want them: the
-- resolved absolute path (what every downstream step addresses the file by),
-- the raw bytes (what @get_goal@ and @fill_hole@ restore the file from, byte
-- for byte, after patching it), and the decoded source.
--
-- Reading once and handing over both forms is not an optimization but a
-- correctness point: an earlier version read the file twice, once as bytes to
-- restore and once as 'Data.Text.IO.readFile' to work on, which decoded through
-- the process locale.  Decoding here, explicitly as UTF-8, makes the answer
-- independent of the environment the server happened to be launched in.
withSourceFile
  :: FilePath
     -- ^ The path exactly as the client sent it.
  -> (FilePath -> BS.ByteString -> Text -> IO (Either ToolFailure a))
     -- ^ Body: resolved path, raw bytes, decoded source.
  -> IO (Either ToolFailure a)
withSourceFile requested body = do
  resolved <- resolveFile "filePath" requested
  case resolved of
    Left failure -> pure (Left (FailPath failure))
    Right rp     -> do
      bytes <- readGuarded rp
      case bytes of
        Left failure -> pure (Left (FailPath failure))
        Right raw    -> case TE.decodeUtf8' raw of
          -- A decode failure stays prose, exactly as it was before issue #101.
          -- It is a fact about the file's contents rather than about which file
          -- was meant, so it does not belong in the path payload — and Agda
          -- source is required to be UTF-8, so this is close to unreachable.
          Left err  -> pure (Left (FailMessage (decodeError (rpAbsolute rp) err)))
          Right src -> body (rpAbsolute rp) raw src


-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

-- | ResolvedPath: a requested path, absolutised, with everything a failure
-- about it would have to name.
--
-- Internal: the provenance is carried alongside the answer so that a failure
-- discovered /after/ resolution — a read that is refused, say — can still
-- report which path the client sent and what it became, without the caller
-- having to thread those through by hand.
data ResolvedPath = ResolvedPath
  { rpParameter :: Text     -- ^ The argument that carried it.
  , rpRequested :: FilePath -- ^ Exactly what the client sent.
  , rpAbsolute  :: FilePath -- ^ What this server resolved it to.
  , rpRelative  :: Bool     -- ^ True when the client sent a relative path.
  , rpServerCwd :: FilePath -- ^ The directory relative paths resolve against.
  }

-- | resolveRequestedFile: absolutise a client path and require it to name a
-- readable-looking regular file.
--
-- The @Left@ is the whole explanation; see 'AgdaMCP.Types.pathFailureMessage'.
resolveRequestedFile :: Text -> FilePath -> IO (Either PathFailure FilePath)
resolveRequestedFile param requested =
  fmap (fmap rpAbsolute) (resolveFile param requested)

-- | resolveRequestedAnchor: the same resolution for a path that may name
-- either a file or the directory holding it, answering with the directory.
--
-- What @check_project@ needs: its subject is a project, and a caller who passes
-- the file they happen to be editing means the project around it.  A path that
-- names nothing is refused rather than silently anchored at its parent, which
-- would run a real gate over a project the caller did not name and report a
-- pass about it.
resolveRequestedAnchor :: Text -> FilePath -> IO (Either PathFailure FilePath)
resolveRequestedAnchor param requested = do
  rp    <- describe param requested
  isDir <- doesDirectoryExist (rpAbsolute rp)
  if isDir
    then pure (Right (rpAbsolute rp))
    else do
      isFile <- doesFileExist (rpAbsolute rp)
      pure $ if isFile
        then Right (takeDirectory (rpAbsolute rp))
        else Left (failureOf rp PathMissing)

-- | resolveFile: 'resolveRequestedFile', keeping the provenance record.
resolveFile :: Text -> FilePath -> IO (Either PathFailure ResolvedPath)
resolveFile param requested = do
  rp     <- describe param requested
  isFile <- doesFileExist (rpAbsolute rp)
  if isFile
    then pure (Right rp)
    else do
      -- A directory is reported as such rather than as "does not exist":
      -- something /is/ there, and telling a caller who passed their project
      -- root that the path is missing would send them looking for the wrong
      -- mistake.
      isDir <- doesDirectoryExist (rpAbsolute rp)
      pure (Left (failureOf rp (if isDir then PathNotAFile else PathMissing)))

-- | describe: what the client asked for, stated in the terms a failure needs.
describe :: Text -> FilePath -> IO ResolvedPath
describe param requested = do
  cwd  <- getCurrentDirectory
  -- 'makeAbsolute' is the resolution issue #101 is about: for a relative path
  -- it prepends the *server's* working directory, which is 'cwd' above — the
  -- directory named in every failure this module produces, so that the answer
  -- to "where did you look?" is never left implicit again.
  abs' <- makeAbsolute requested
  pure ResolvedPath
    { rpParameter = param
    , rpRequested = requested
    , rpAbsolute  = abs'
      -- Asked of the path as sent, not of the result: 'makeAbsolute' also
      -- normalises, so the answer must be taken before it runs.
    , rpRelative  = not (isAbsolute requested)
    , rpServerCwd = cwd
    }

-- | failureOf: the structured refusal for a resolved path and one problem.
failureOf :: ResolvedPath -> PathProblem -> PathFailure
failureOf rp problem = PathFailure
  { pfParameter = rpParameter rp
  , pfRequested = rpRequested rp
  , pfResolved  = rpAbsolute rp
  , pfRelative  = rpRelative rp
  , pfServerCwd = rpServerCwd rp
  , pfProblem   = problem
  }


-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

-- | readGuarded: read the resolved file, turning an 'IOException' into a
-- structured failure instead of letting it escape the tool call.
--
-- 'resolveFile' has already established that a file was there, so this fires
-- for the cases existence cannot rule out: a file we may not open, a file
-- removed in the moment between the check and the read, a device that refused.
-- Whatever the cause, the client learns the path and the syscall's own words
-- rather than @-32603 Internal error@.
readGuarded :: ResolvedPath -> IO (Either PathFailure BS.ByteString)
readGuarded rp = do
  attempt <- try (BS.readFile (rpAbsolute rp))
  pure $ case attempt of
    Right bytes         -> Right bytes
    Left (e :: IOException) ->
      Left (failureOf rp (PathUnreadable (T.pack (show e))))

-- | decodeError: a structured error for a file whose bytes are not valid UTF-8.
--
-- Agda source is required to be UTF-8, so this should not arise in practice,
-- but returning a 'Left' is friendlier than letting a 'UnicodeException' escape
-- the tool call.
decodeError :: FilePath -> UnicodeException -> Text
decodeError path err =
  "Could not decode " <> T.pack path <> " as UTF-8 (Agda source must be UTF-8): "
  <> T.pack (show err)
