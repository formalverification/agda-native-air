-- | Gate.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Gate.hs
--
-- Description:
--   Deciding which command /is/ a project's acceptance gate (issue #78).
--
--   @check_project@ exists to run the gate a human would run, so the first
--   question it has to answer honestly is which command that is.  This module
--   answers it, and refuses rather than guessing when it cannot:
--
--   1. An explicit @target@ names a @make@ target.  The nearest Makefile
--      declaring it — searching upward from the anchor directory to the
--      repository boundary — is the gate, run in that Makefile's own directory.
--      If no Makefile up the tree declares that target, the call fails; falling
--      back to some other command would run something the caller did not ask
--      for.
--   2. With no @target@, an operator-configured command (@--check-command@)
--      wins if there is one.  It is run directly, never through a shell, which
--      is not an implementation detail: no shell means no wrapper, and no
--      wrapper means nothing between @make@'s exit status and this server's
--      report of it.  The trap § 3.5 of the feedback document describes — a
--      wrapper ending in @echo@, so the shell exits 0 whatever @make@ did —
--      cannot be introduced by us.  (A wrapper the /operator/ configures can
--      still lie, which is what 'AgdaMCP.Tools.CheckProject' detects.)
--   3. Otherwise, discovery: the nearest Makefile declaring @check@, else
--      @agda@ on the project's @Everything@ module.
--   4. Nothing found is an error naming every directory that was searched and
--      what to configure — never a silent no-op reported as a pass.
--
--   The upward walk stops at a repository boundary (a @.git@ file or directory,
--   so a git worktree counts), exactly as 'AgdaMCP.Project.findNearestAgdaLib'
--   does: a Makefile above the checkout belongs to some other project, and
--   running its @check@ target would answer a question nobody asked.
--
--   Makefile parsing is deliberately small: a target is declared if the file
--   has a rule line for it.  Included makefiles are not followed, so a target
--   defined only in an include is not discovered — the failure message says so,
--   and @--check-command@ is the escape hatch.  The alternative, running @make@
--   speculatively to ask, evaluates the makefile (@$(shell …)@ and all) just to
--   answer a question the caller can settle by naming the command.  In each
--   directory the file consulted is the one @make@ itself would read (the first
--   of @GNUmakefile@, @makefile@, @Makefile@), so the makefile the response
--   names is always the makefile the gate ran.

{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module AgdaMCP.Gate
  ( -- * Configuration
    GateConfig (..)
  , defaultGateConfig
  , defaultCheckTimeoutSeconds
  , checkTimeoutOf
  , configuredCommand
    -- * Resolution (IO)
  , GatePlan (..)
  , resolveGate
    -- * Makefile parsing (pure; exposed for testing)
  , defaultCheckTarget
  , makefileTargets
  , makefileDeclares
  , makefileNames
    -- * Discovery (IO; exposed for testing)
  , findMakefileGate
  , firstMakefileIn
  , findEverythingModule
  , everythingNames
  ) where

import Control.Exception (SomeException, try)
import Data.List (nub)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import System.Directory (doesDirectoryExist, doesFileExist, makeAbsolute)
import System.FilePath (takeDirectory, (</>))

import AgdaMCP.Agda (AgdaConfig (..))
import AgdaMCP.Project (libraryIncludeDirs, projectExtraFlags)
import AgdaMCP.Types
  ( Gate (..), GateSource (..), ProjectContext (..) )


-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- | GateConfig: the server-level configuration of the project gate.
--
-- Both fields come from command-line flags, so an operator whose gate this
-- module cannot discover — a @just@ recipe, a script, a @nix develop --command@
-- wrapper — can simply name it.
data GateConfig = GateConfig
  { gcCommand :: Maybe [String]
    -- ^ @--check-command@, as an argument vector (the flag's value is split on
    --   whitespace).  Run directly, with no shell, so it cannot contain a
    --   pipeline, a redirect, or a @&&@, and nothing this server puts around the
    --   gate can mask its exit code.  A wrapper /script/ named here can still
    --   lie about its own, which is what
    --   'AgdaMCP.Tools.CheckProject' detects and reports as @maskedFailure@.
  , gcTimeout :: Maybe Int
    -- ^ @--check-timeout@, in seconds.  'Nothing', or any non-positive number,
    --   means no bound — the usual command-line spelling of "unlimited", and
    --   the same one @--timeout 0@ already uses.
  } deriving (Eq, Show)

-- | defaultCheckTimeoutSeconds: the default bound on a whole-project gate.
--
-- Sized from the case that motivated the tool: the field session's gate was a
-- @make check@ over a generated @Everything.agda@ of some 300 modules, taking
-- 10–20 minutes.  The per-call @--timeout@ default (300 s) is right for one
-- file and badly wrong for that, so the project gate gets its own bound with
-- its own default — half an hour, which covers the observed case with room for
-- a colder machine, while still ending a gate that has genuinely hung.
defaultCheckTimeoutSeconds :: Int
defaultCheckTimeoutSeconds = 1800

-- | The default gate configuration: nothing configured, the default bound.
defaultGateConfig :: GateConfig
defaultGateConfig = GateConfig
  { gcCommand = Nothing
  , gcTimeout = Just defaultCheckTimeoutSeconds
  }

-- | checkTimeoutOf: the effective bound, or 'Nothing' when unbounded.
checkTimeoutOf :: GateConfig -> Maybe Int
checkTimeoutOf gc = case gcTimeout gc of
  Just secs | secs > 0 -> Just secs
  _                    -> Nothing

-- | configuredCommand: the operator's gate as (binary, arguments), or 'Nothing'
-- when none was configured.  An empty or whitespace-only @--check-command@ is
-- treated as none rather than as a command with no name.
configuredCommand :: GateConfig -> Maybe (FilePath, [String])
configuredCommand gc = case gcCommand gc of
  Just (bin : args) | not (null bin) -> Just (bin, args)
  _                                  -> Nothing

-- | The target discovery looks for when the caller names none.
defaultCheckTarget :: Text
defaultCheckTarget = "check"


-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

-- | GatePlan: a resolved gate — what to run, where, and the 'Gate' echo saying
-- why that command was chosen.
--
-- 'gpCwd' is 'Nothing' when the command must run in the server's own working
-- directory.  That is not a default so much as a requirement for the
-- @Everything@ gate: the server's Agda flags are the ones it was started with,
-- and the shipped configuration spells them relative to the repository root
-- (@--library-file=agda/libraries@), so moving that invocation elsewhere would
-- silently change which libraries file @agda@ reads.  A @make@ gate, by
-- contrast, must run in its Makefile's directory, which is what a human does.
data GatePlan = GatePlan
  { gpBinary :: FilePath
  , gpArgs   :: [String]
  , gpCwd    :: Maybe FilePath
  , gpGate   :: Gate
  } deriving (Eq, Show)

-- | resolveGate: decide the gate for one project, or say why there is none.
--
-- @Left@ is a message for the caller: it names every directory searched and the
-- two ways to fix it, because "no gate found" is otherwise indistinguishable
-- from "your project is fine".
resolveGate
  :: GateConfig
  -> AgdaConfig
  -> ProjectContext
  -> FilePath        -- ^ The anchor directory discovery starts from.
  -> Maybe Text      -- ^ The requested @make@ target, if any.
  -> IO (Either Text GatePlan)
resolveGate gcfg cfg pc anchor mTarget = case mTarget of
  -- An explicitly named target is a request, not a hint: if no Makefile in the
  -- tree declares it, say so rather than running something else.
  Just target -> do
    found <- findMakefileGate target anchor
    pure $ case found of
      Right (makefile, dir) -> Right (makePlan target makefile dir)
      Left searched         -> Left (noSuchTargetMessage target anchor searched)
  Nothing -> case configuredCommand gcfg of
    Just (bin, args) -> pure (Right (configuredPlan bin args))
    Nothing          -> do
      found <- findMakefileGate defaultCheckTarget anchor
      case found of
        Right (makefile, dir) -> pure (Right (makePlan defaultCheckTarget makefile dir))
        Left searched         -> do
          mEntry <- findEverythingModule entryDirs
          pure $ case mEntry of
            Just entry -> Right (everythingPlan entry)
            Nothing    -> Left (noGateMessage anchor searched entryDirs)
  where
    baseGate = Gate
      { gateSource       = GateFromServerConfig
      , gateTarget       = Nothing
      , gateMakefile     = Nothing
      , gateEntry        = Nothing
      , gateSearchedFrom = anchor
      }

    configuredPlan bin args = GatePlan
      { gpBinary = bin
      , gpArgs   = args
        -- The operator's gate runs where the caller anchored the project, which
        -- is the server's own working directory unless a projectPath said
        -- otherwise.
      , gpCwd    = Just anchor
      , gpGate   = baseGate
      }

    makePlan target makefile dir = GatePlan
      { gpBinary = "make"
      , gpArgs   = [T.unpack target]
      , gpCwd    = Just dir
      , gpGate   = baseGate
          { gateSource   = GateFromMakefile
          , gateTarget   = Just target
          , gateMakefile = Just makefile
          }
      }

    -- The same flag assembly the per-file tools use ('withProject'): the
    -- server's own flags, whatever root resolution implies, and the entry
    -- module's own directory — so an Everything gate is exactly the check_file
    -- of that module, and its command echo can be compared against one.
    everythingPlan entry = GatePlan
      { gpBinary = agdaBin cfg
      , gpArgs   = agdaFlags cfg
                     <> projectExtraFlags pc
                     <> ["-i", takeDirectory entry, entry]
      , gpCwd    = Nothing
      , gpGate   = baseGate
          { gateSource = GateFromEverything
          , gateEntry  = Just entry
          }
      }

    -- Where an Everything module could live: the library's own include
    -- directories first (that is where Agda would look for it), then the
    -- resolved root, then the anchor.
    entryDirs = nub $
      maybe [] libraryIncludeDirs (pcLibrary pc) <> [pcRoot pc, anchor]


-- ---------------------------------------------------------------------------
-- Failure messages
-- ---------------------------------------------------------------------------

-- | noSuchTargetMessage: the caller named a target no Makefile declares.
noSuchTargetMessage :: Text -> FilePath -> [FilePath] -> Text
noSuchTargetMessage target anchor searched = T.concat
  [ "agda-mcp: no Makefile declaring target '", target, "' was found for "
  , T.pack anchor, ".\n"
  , "  searched, up to the repository boundary: ", listOf searched, "\n"
  , includeCaveat
  , "  Fix: name a target one of those Makefiles declares, or start the server"
  , " with --check-command \"<the command your project's gate is>\"."
  ]

-- | noGateMessage: discovery found neither a @check@ target nor an @Everything@
-- module.
noGateMessage :: FilePath -> [FilePath] -> [FilePath] -> Text
noGateMessage anchor searched entryDirs = T.concat
  [ "agda-mcp: no project gate found for ", T.pack anchor, ".\n"
  , "  no Makefile declaring the '", defaultCheckTarget, "' target in: "
  , listOf searched, "\n"
  , "  no Everything module (", T.intercalate ", " (map T.pack everythingNames)
  , ") in: ", listOf entryDirs, "\n"
  , includeCaveat
  , "  Fix: pass target=<name> if this project's gate is a differently-named"
  , " make target, or start the server with --check-command \"<the command your"
  , " project's gate is>\" (it is run directly, without a shell)."
  ]

-- | The one discovery limitation worth stating in both messages.
includeCaveat :: Text
includeCaveat =
  "  (Discovery reads each Makefile's own rule lines; a target defined only in"
  <> " an included file is not found.)\n"

listOf :: [FilePath] -> Text
listOf [] = "(nowhere)"
listOf ps = T.intercalate ", " (map T.pack ps)


-- ---------------------------------------------------------------------------
-- Makefile discovery
-- ---------------------------------------------------------------------------

-- | The makefile names GNU make itself tries, in its own precedence order.
makefileNames :: [FilePath]
makefileNames = ["GNUmakefile", "makefile", "Makefile"]

-- | findMakefileGate: the nearest makefile declaring @target@, walking up from
-- a directory to the repository boundary.
--
-- @Right (makefile, dir)@ is the file and the directory @make@ should run in.
-- @Left dirs@ lists every directory that was examined, so the failure message
-- can show its work.
--
-- In each directory only the makefile @make@ /would read/ is consulted — the
-- first of @GNUmakefile@, @makefile@, @Makefile@ that exists, which is make's
-- own precedence rule.  Reading past it to a lower-precedence file that happens
-- to declare the target would let the echo name a file the gate never ran, and
-- the run would then fail with make's "No rule to make target" for a target we
-- had just said existed.
findMakefileGate :: Text -> FilePath -> IO (Either [FilePath] (FilePath, FilePath))
findMakefileGate target dir0 = makeAbsolute dir0 >>= go []
  where
    go seen dir = do
      isDir <- doesDirectoryExist dir
      if not isDir
        then pure (Left (reverse seen))
        else do
          hit <- declaringMakefileIn dir
          case hit of
            Just makefile -> pure (Right (makefile, dir))
            Nothing       -> do
              atBoundary <- isRepoRoot dir
              let up   = takeDirectory dir
                  seen' = dir : seen
              if atBoundary || up == dir
                then pure (Left (reverse seen'))
                else go seen' up

    declaringMakefileIn dir = do
      mMakefile <- firstMakefileIn dir
      case mMakefile of
        Nothing   -> pure Nothing
        Just path -> do
          mTxt <- readTextMaybe path
          pure $ case mTxt of
            Just txt | makefileDeclares target txt -> Just path
            _                                      -> Nothing

    isRepoRoot dir = do
      f <- doesFileExist (dir </> ".git")
      d <- doesDirectoryExist (dir </> ".git")
      pure (f || d)

-- | firstMakefileIn: the makefile @make@ would read in a directory, or
-- 'Nothing' if it has none.
firstMakefileIn :: FilePath -> IO (Maybe FilePath)
firstMakefileIn dir = go makefileNames
  where
    go []           = pure Nothing
    go (name : rest) = do
      let path = dir </> name
      exists <- doesFileExist path
      if exists then pure (Just path) else go rest

-- | makefileDeclares: does this makefile have a rule for @target@?
makefileDeclares :: Text -> Text -> Bool
makefileDeclares target txt = target `elem` makefileTargets txt

-- | makefileTargets: the targets a makefile's own rule lines declare.
--
-- A rule line is one that is not a recipe (recipes begin with a tab), not a
-- comment, and whose first @:@ does not begin an assignment — @VAR := x@,
-- @VAR ::= x@, and @VAR :::= x@ all being assignments, while @target:: dep@ is
-- a (double-colon) rule.  A line whose left-hand side contains @=@ is an
-- assignment too, which is what keeps @VAR = a:b@ from declaring a target named
-- @VAR@.
--
-- Everything else on the left of the @:@ is a target name, since a rule may
-- declare several (@check test: deps@).  Names are returned verbatim, so
-- @.PHONY@ and pattern rules appear as themselves and simply never match the
-- name being looked up.
makefileTargets :: Text -> [Text]
makefileTargets = concatMap targetsOfLine . T.lines
  where
    targetsOfLine ln
      | T.null ln                          = []
      | T.head ln == '\t'                  = []
      | "#" `T.isPrefixOf` T.stripStart ln = []
      | T.null after                       = []
      | T.any (== '=') names               = []
      | isAssignment                       = []
      | otherwise                          = T.words names
      where
        (names, after) = T.breakOn ":" ln
        -- Past the first colon: an @=@ (after any further colons) means this is
        -- one of make's assignment operators, not a rule.
        isAssignment = "=" `T.isPrefixOf` T.dropWhile (== ':') (T.drop 1 after)


-- ---------------------------------------------------------------------------
-- Everything-module discovery
-- ---------------------------------------------------------------------------

-- | The names an @Everything@ module can have: plain Agda plus every literate
-- flavour Agda 2.8 accepts, since a literate library generates a literate
-- barrel module.
everythingNames :: [FilePath]
everythingNames =
  [ "Everything" <> ext
  | ext <- [ ".agda", ".lagda", ".lagda.md", ".lagda.tex", ".lagda.rst"
           , ".lagda.org", ".lagda.typ", ".lagda.tree" ]
  ]

-- | findEverythingModule: the first @Everything@ module among the candidate
-- directories, in the order given.
findEverythingModule :: [FilePath] -> IO (Maybe FilePath)
findEverythingModule dirs = go [d </> n | d <- dirs, n <- everythingNames]
  where
    go []             = pure Nothing
    go (path : rest)  = do
      exists <- doesFileExist path
      if exists then Just <$> makeAbsolute path else go rest


-- ---------------------------------------------------------------------------
-- IO helpers
-- ---------------------------------------------------------------------------

-- | readTextMaybe: read a makefile, or 'Nothing' if anything goes wrong.  A
-- directory we may not read is ordinary on an upward walk and must not take the
-- tool call down with it.
readTextMaybe :: FilePath -> IO (Maybe Text)
readTextMaybe p = do
  r <- try (TIO.readFile p) :: IO (Either SomeException Text)
  pure (either (const Nothing) Just r)
