-- | Project.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Project.hs
--
-- Description:
--   Project-root resolution and library-context transparency (issue #76).
--
--   This module answers, for one requested file, the question every response
--   must now be able to state: /which tree did you check?/  It does so the way
--   Agda itself decides a module's identity — from the file's position relative
--   to a library root — rather than from an environment variable fixed when the
--   server started.
--
--   The resolution, in order:
--
--   1. Walk up from the file's directory to the nearest @*.agda-lib@, stopping
--      at a repository boundary (a directory holding @.git@) so the search
--      cannot wander into an unrelated checkout above the project.  A hit gives
--      the effective root, the library's name, and its @include:@ directories.
--   2. Read the libraries registry the server will actually use — the
--      @--library-file@ from its flags, else @$AGDA_DIR/libraries@, else
--      @~/.agda/libraries@ — and parse the @*.agda-lib@ files it names.
--   3. Compare.  If the registry gives the file's library name a /different/
--      root, refuse the call: see 'AgdaMCP.Types.ProjectMismatch'.  If it gives
--      that name the same root, nothing needs adding — the server's @-l@ flags
--      already reach it.  If the registry has never heard of the library, add
--      its own @include:@ directories with @-i@ so the file resolves in its own
--      tree.
--   4. With no @*.agda-lib@ above the file at all, fall back to the
--      server-start configuration and say so ('RootFromServerConfig'); the
--      file's own directory is the effective root, which is what the tools'
--      existing @-i \<dir-of-file\>@ already provides.
--
--   Why refusing matters.  The field configuration in
--   @agda-mcp/examples/agda-algebras.mcp.json@ binds a worktree through an
--   environment variable read by the flake's shellHook, which rewrites a
--   checkout-wide @agda/libraries@ on shell entry.  That file is shared,
--   mutable, process-global state: a second shell entry elsewhere silently
--   repoints it.  Without step 3, pointing the client at a file in worktree B
--   while the registry still names worktree A resolves B's imports against A
--   and reports success — a wrong answer rather than an error, which § 3.6 of
--   @docs/feedback/flrp-agda-mcp-improvements.md@ calls the worst outcome an
--   agent client can be handed.
--
--   Everything here is best-effort about /parsing/ and strict about
--   /disagreement/: an unreadable registry contributes no entries, so nothing
--   is claimed about libraries we could not read, and dropping an entry can
--   lose a warning but can never invent one.  A registry we did read that
--   contradicts the file, by contrast, is an error rather than a warning.

{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module AgdaMCP.Project
  ( -- * Resolution (IO)
    resolveProject
  , projectExtraFlags
  , withEffectiveFlags
    -- * Flag inspection (pure; exposed for testing)
  , librariesFileFlagOf
  , includePathsOf
  , selectedLibrariesOf
    -- * @*.agda-lib@ and registry parsing (pure; exposed for testing)
  , parseLibrariesFile
  , libraryNameOf
  , libraryIncludesOf
  , libraryIncludeDirs
    -- * Filesystem walk (IO; exposed for testing)
  , findNearestAgdaLib
  ) where

import Control.Exception (SomeException, try)
import Data.Char (isSpace)
import Data.List (isPrefixOf, isSuffixOf, nub, sort)
import Data.Maybe (catMaybes, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import System.Directory
  ( canonicalizePath, doesDirectoryExist, doesFileExist, getHomeDirectory
  , listDirectory, makeAbsolute
  )
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))

import AgdaMCP.Agda (AgdaConfig (..))
import AgdaMCP.Types
  ( LibraryEntry (..), ProjectContext (..), ProjectMismatch (..)
  , RootSource (..)
  )


-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

-- | resolveProject: decide, and report, the library context for one file.
--
-- @Left@ is the loud failure of issue #76 — the file belongs to a different
-- checkout of a library this server has registered elsewhere — and it is
-- returned /before/ Agda is started, so no wrong-tree typecheck ever happens.
-- @Right@ carries the context to echo in the response.
--
-- The path argument is expected to be absolute (the tools call
-- 'System.Directory.makeAbsolute' first); it is absolutised again here so the
-- function is safe to call directly.
resolveProject :: AgdaConfig -> FilePath -> IO (Either ProjectMismatch ProjectContext)
resolveProject cfg path = do
  absPath    <- makeAbsolute path
  mRegistry  <- resolveLibrariesFile (librariesFileFlagOf (agdaFlags cfg))
  registered <- maybe (pure []) readRegistry mRegistry
  mOwn       <- findNearestAgdaLib (takeDirectory absPath)
  let base = ProjectContext
        { pcRootSource    = RootFromServerConfig
        , pcRoot          = takeDirectory absPath
        , pcLibrary       = Nothing
        , pcLibrariesFile = mRegistry
        , pcRegistered    = registered
        , pcSelected      = selectedLibrariesOf (agdaFlags cfg)
        , pcIncludePaths  = includePathsOf (agdaFlags cfg)
        }
  case mOwn of
    -- No library above the file: the server-start configuration is the whole
    -- context there is, and saying so is more useful than inventing a root.
    Nothing  -> pure (Right base)
    Just own -> do
      ownRoot <- canonicalize (leRoot own)
      -- Only entries claiming the *same library name* can contradict this file;
      -- a differently-named library elsewhere is not a conflict, it is simply
      -- another library.
      sameName <- mapM (\e -> (,) e <$> canonicalize (leRoot e))
                       [e | e <- registered, leName e == leName own]
      let resolved = base { pcRootSource = RootFromAgdaLib
                          , pcRoot       = leRoot own
                          , pcLibrary    = Just own
                          }
      pure $ case sameName of
        -- Unknown to the registry: nothing can contradict the file's own tree.
        [] -> Right resolved
        es@((clash, _) : _)
          -- Registered, and one of the registered roots is this very tree.
          | any ((== ownRoot) . snd) es -> Right resolved
          -- Registered under this name, but only in some other tree.
          | otherwise -> Left ProjectMismatch
              { pmFilePath       = absPath
              , pmLibraryName    = leName own
              , pmFileRoot       = leRoot own
              , pmRegisteredRoot = leRoot clash
              , pmLibrariesFile  = maybe (leLibFile clash) id mRegistry
              }
  where
    -- A path that cannot be canonicalized (a dangling symlink, a permission
    -- wall) falls back to itself: comparing the literal paths is better than
    -- aborting the whole call over a resolution the comparison may not need.
    canonicalize p = either (const p) id
      <$> (try (canonicalizePath p) :: IO (Either SomeException FilePath))


-- | projectExtraFlags: the Agda flags this resolution implies, on top of the
-- server's own.
--
-- Empty in the common cases — a file inside the library the server was already
-- started for needs nothing added.  It is non-empty exactly when the file's
-- library is real but not already reachable:
--
--   * registered in the libraries file but not selected by a @-l@ flag — name
--     it with @--library@, which also pulls in its @depend:@ libraries;
--   * not in the registry at all — put its own @include:@ directories on the
--     include path with @-i@, so its hierarchical modules resolve against
--     /its/ root rather than against whatever the server was started with.
--
-- Both are additive: they extend the include path and never redirect it, so a
-- call that worked before resolution still runs the same way.
projectExtraFlags :: ProjectContext -> [String]
projectExtraFlags pc = case pcLibrary pc of
  Nothing  -> []
  Just own
    | leName own `elem` pcSelected pc                  -> []
    | any ((== leName own) . leName) (pcRegistered pc) ->
        ["--library", T.unpack (leName own)]
    | otherwise -> concat [ ["-i", inc] | inc <- libraryIncludeDirs own ]

-- | withEffectiveFlags: restate a context's selected libraries and include
-- paths in terms of the flags the call will actually run with.
--
-- 'resolveProject' can only describe the flags it was /given/, but the caller
-- then extends them — with 'projectExtraFlags', and with the requested file's
-- own directory.  Reporting the pre-extension view would make the @project@
-- block describe a context that is not the one Agda saw, which is precisely
-- the transparency the block exists to provide; a client reading @project@
-- rather than parsing @command.args@ would be misled.  Applying this at the
-- point where the final flag list is assembled keeps the two in step by
-- construction.
withEffectiveFlags :: [String] -> ProjectContext -> ProjectContext
withEffectiveFlags flags pc = pc
  { pcSelected     = selectedLibrariesOf flags
  , pcIncludePaths = includePathsOf flags
  }

-- | libraryIncludeDirs: a library's @include:@ directories, resolved against
-- its root.  A library declaring no @include:@ includes its own root, which is
-- what Agda does.
libraryIncludeDirs :: LibraryEntry -> [FilePath]
libraryIncludeDirs e = case leIncludes e of
  [] -> [leRoot e]
  is -> [leRoot e </> i | i <- is]


-- ---------------------------------------------------------------------------
-- Finding the file's own library
-- ---------------------------------------------------------------------------

-- | findNearestAgdaLib: walk up from a directory to the nearest @*.agda-lib@.
--
-- Stops at the first directory holding one, at a repository boundary (a @.git@
-- file or directory — a git worktree's @.git@ is a file, so both count), or at
-- the filesystem root.  The repository boundary is what keeps a file in a
-- library-less checkout from being attributed to some unrelated @*.agda-lib@
-- sitting further up the user's home directory.
--
-- When a directory holds several @*.agda-lib@ files the first in sorted order
-- wins, matching the arbitrary-but-deterministic choice the flake's shellHook
-- makes with @find … | head -1@.
findNearestAgdaLib :: FilePath -> IO (Maybe LibraryEntry)
findNearestAgdaLib dir0 = makeAbsolute dir0 >>= go
  where
    go dir = do
      isDir <- doesDirectoryExist dir
      if not isDir then pure Nothing else do
        entries <- either (const []) id
          <$> (try (listDirectory dir) :: IO (Either SomeException [FilePath]))
        case sort (filter (".agda-lib" `isSuffixOf`) entries) of
          (lib : _) -> readLibraryEntry (dir </> lib)
          []        -> do
            atBoundary <- isRepoRoot dir
            let up = takeDirectory dir
            if atBoundary || up == dir then pure Nothing else go up

    isRepoRoot dir = do
      f <- doesFileExist (dir </> ".git")
      d <- doesDirectoryExist (dir </> ".git")
      pure (f || d)

-- | readLibraryEntry: read a @*.agda-lib@ file into a 'LibraryEntry'.
--
-- A library whose file we cannot read, or that declares no @name:@, is treated
-- as absent rather than as a nameless entry: an unnamed root cannot take part
-- in the name comparison the mismatch check is built on, so claiming one would
-- only add noise to the echo.
readLibraryEntry :: FilePath -> IO (Maybe LibraryEntry)
readLibraryEntry libFile = do
  mTxt <- readTextMaybe libFile
  pure $ do
    txt  <- mTxt
    name <- libraryNameOf txt
    pure LibraryEntry
      { leName     = name
      , leRoot     = takeDirectory libFile
      , leLibFile  = libFile
      , leIncludes = libraryIncludesOf txt
      }


-- ---------------------------------------------------------------------------
-- The libraries registry
-- ---------------------------------------------------------------------------

-- | resolveLibrariesFile: which libraries registry will @agda@ actually read?
--
-- The explicit @--library-file@ from the server's flags wins, exactly as it
-- does for Agda.  Failing that, Agda looks in its application directory, which
-- is @$AGDA_DIR@ when set and @~/.agda@ otherwise — and @$AGDA_DIR@ is set by
-- this repository's flake shellHook, so naming it here is not hypothetical.
-- A path that does not exist is reported as no registry at all rather than as
-- an empty one, since the two lead to different advice.
resolveLibrariesFile :: Maybe FilePath -> IO (Maybe FilePath)
resolveLibrariesFile (Just explicit) = do
  abs'   <- makeAbsolute explicit
  exists <- doesFileExist abs'
  pure (if exists then Just abs' else Nothing)
resolveLibrariesFile Nothing = do
  mAgdaDir <- lookupEnv "AGDA_DIR"
  mHome    <- either (const Nothing) Just
    <$> (try getHomeDirectory :: IO (Either SomeException FilePath))
  firstExisting [d </> "libraries" | d <- catMaybes [mAgdaDir, (</> ".agda") <$> mHome]]
  where
    firstExisting []       = pure Nothing
    firstExisting (c : cs) = do
      ok <- doesFileExist c
      if ok then Just <$> makeAbsolute c else firstExisting cs

-- | readRegistry: parse a libraries file into the entries it declares.
readRegistry :: FilePath -> IO [LibraryEntry]
readRegistry libsFile = do
  mTxt <- readTextMaybe libsFile
  case mTxt of
    Nothing  -> pure []
    Just txt -> catMaybes <$> mapM readLibraryEntry
                                  (parseLibrariesFile (takeDirectory libsFile) txt)


-- ---------------------------------------------------------------------------
-- Pure parsing
-- ---------------------------------------------------------------------------

-- | parseLibrariesFile: the @*.agda-lib@ paths a libraries file names.
--
-- One path per line; blank lines and @--@ comments are ignored, and a relative
-- path is taken relative to the libraries file's own directory (Agda's rule).
-- Leading and trailing whitespace is stripped, which matters because the file
-- is commonly generated from a shell heredoc.
parseLibrariesFile :: FilePath -> Text -> [FilePath]
parseLibrariesFile baseDir =
  map absolutise . filter (not . null) . map (T.unpack . T.strip . stripComment) . T.lines
  where
    absolutise p
      | "/" `isPrefixOf` p = p
      | otherwise          = baseDir </> p

-- | libraryNameOf: the @name:@ field of a @*.agda-lib@ file.
libraryNameOf :: Text -> Maybe Text
libraryNameOf =
  fmap (T.takeWhile (not . isSpace)) . listToMaybe . filter (not . T.null) . fieldValues "name"

-- | libraryIncludesOf: the @include:@ directories of a @*.agda-lib@ file.
--
-- Agda allows the field to span continuation lines and to list several
-- whitespace-separated directories; both are flattened here.  Directory names
-- containing spaces are not supported, matching Agda's own documented
-- limitation.
libraryIncludesOf :: Text -> [FilePath]
libraryIncludesOf txt =
  nub [T.unpack w | v <- fieldValues "include" txt, w <- T.words v]

-- | fieldValues: the value of every @\<field\>:@ line, joined with the
-- continuation lines that follow it.
--
-- A @*.agda-lib@ file is a sequence of @field: value@ lines in which an
-- indented following line continues the previous field.  Comments are stripped
-- first, so a comment line ends a continuation run rather than extending it.
fieldValues :: Text -> Text -> [Text]
fieldValues field = go . map stripComment . T.lines
  where
    prefix = field <> ":"

    go [] = []
    go (l : ls)
      | Just rest <- T.stripPrefix prefix (T.stripStart l) =
          let (cont, ls') = span isContinuation ls
          in  T.strip (T.unwords (rest : map T.strip cont)) : go ls'
      | otherwise = go ls

    isContinuation l = not (T.null (T.strip l)) && isSpace (T.head l)

-- | stripComment: drop an Agda @--@ comment from a library or libraries line.
--
-- The @--@ must start the line or follow whitespace, so a path or directory
-- name that happens to contain a double hyphen (@…/my--lib/…@) is not
-- truncated into a different path — the failure mode a naive
-- @breakOn "--"@ would introduce into exactly the path comparison this module
-- exists to get right.
stripComment :: Text -> Text
stripComment l = case T.breakOn "--" l of
  (before, rest)
    | T.null rest                                  -> l
    | T.null before                                -> ""
    | isSpace (T.last before)                      -> before
    | otherwise -> before <> "--" <> stripComment (T.drop 2 rest)

-- | librariesFileFlagOf: the @--library-file@ the server was started with, in
-- either spelling Agda accepts (@--library-file=PATH@ and @--library-file PATH@).
-- The last occurrence wins, as it does for Agda's own option parser — which
-- matters because the Nix @agda@ wrapper supplies one of its own ahead of the
-- caller's flags.
librariesFileFlagOf :: [String] -> Maybe FilePath
librariesFileFlagOf = lastMaybe . go
  where
    go [] = []
    go (a : rest)
      | Just p <- stripPrefix' "--library-file=" a = p : go rest
      | a == "--library-file", (p : rest') <- rest = p : go rest'
      | otherwise                                  = go rest
    lastMaybe xs = if null xs then Nothing else Just (last xs)

-- | includePathsOf: the include directories the server was started with
-- (@-i DIR@, @-iDIR@, @--include-path=DIR@, @--include-path DIR@).
includePathsOf :: [String] -> [FilePath]
includePathsOf = go
  where
    go [] = []
    go (a : rest)
      | a == "-i", (p : rest') <- rest              = p : go rest'
      | Just p <- stripPrefix' "-i" a, not (null p) = p : go rest
      | Just p <- stripPrefix' "--include-path=" a  = p : go rest
      | a == "--include-path", (p : rest') <- rest  = p : go rest'
      | otherwise                                   = go rest

-- | selectedLibrariesOf: the library names the server was started with
-- (@-l NAME@, @-lNAME@, @--library=NAME@, @--library NAME@).
selectedLibrariesOf :: [String] -> [Text]
selectedLibrariesOf = map T.pack . go
  where
    go [] = []
    go (a : rest)
      | a == "-l", (n : rest') <- rest              = n : go rest'
      | Just n <- stripPrefix' "-l" a, not (null n) = n : go rest
      | Just n <- stripPrefix' "--library=" a       = n : go rest
      | a == "--library", (n : rest') <- rest       = n : go rest'
      | otherwise                                   = go rest

stripPrefix' :: String -> String -> Maybe String
stripPrefix' p s
  | p `isPrefixOf` s = Just (drop (length p) s)
  | otherwise        = Nothing


-- ---------------------------------------------------------------------------
-- IO helpers
-- ---------------------------------------------------------------------------

-- | readTextMaybe: read a small text file, or 'Nothing' if anything goes wrong.
--
-- Used for @*.agda-lib@ and libraries files, which are a few lines each; a
-- missing or unreadable one is ordinary (the registry may name a library that
-- has since been deleted) and must not take the tool call down with it.
readTextMaybe :: FilePath -> IO (Maybe Text)
readTextMaybe p = do
  r <- try (TIO.readFile p) :: IO (Either SomeException Text)
  pure (either (const Nothing) Just r)
