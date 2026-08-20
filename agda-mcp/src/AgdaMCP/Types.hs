-- | Types.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Types.hs
--
-- Description:
--   Shared types for the agda-mcp MCP server.
--
--   This module defines the JSON schema contract for tool requests and responses.
--   Every type has a hand-written Aeson instance to ensure the wire format is
--   stable across code changes (no Generic-derived surprises).
--
--   Schema version: agda-mcp/v0
--
--   All proof-state responses carry @elapsedMs@ (wall-clock time in the Agda
--   subprocess) and @checkedFromSource@ (whether Agda re-typechecked the module
--   or reused its @.agdai@ interface), so an agent can tell a cold first call
--   from a warm one.  Timeouts are reported per tool: @fill_hole@ as
--   @status: "timeout"@, @check_file@ / @get_diagnostics@ as @success: false@
--   with a @timedOut@ flag and an explanatory diagnostic.  These fields are
--   additive — every pre-existing key keeps its name, type, and meaning — so the
--   schema version is unchanged (issue #77).
--
--   'Diagnostic' carries the structured shape of issue #74: a machine-readable
--   @code@, the source @file@ and @range@, the bounded full message body, and an
--   @involved@ payload naming the expected/actual types, candidate names, or
--   metas the diagnostic is about.  @line@ and @col@ are retained as aliases of
--   the range start, so this too is additive.
--
--   All proof-state responses additionally carry the /response echo/ (issues
--   #72 and #76) — three keys that say what was run, what the answer means, and
--   which tree it was run against:
--
--   * @verdict@ ('Verdict') — the @agda@ command this call is equivalent to,
--     a sentence stating what a green result means, and the exit code the
--     verdict was derived from.  Success is read off that exit code, never off
--     the prose of Agda's messages, so a change in Agda's message format can
--     never silently turn a red build green.
--   * @command@ ('CommandEcho') — the resolved command line: binary, argument
--     vector, and working directory.
--   * @project@ ('ProjectContext') — the library context that was in effect:
--     the resolved root, where it came from, the file's own @*.agda-lib@, the
--     libraries registry consulted, and what that registry declares.
--
--   The echo is what lets a client confirm "this equals my @agda \<file\>@ gate"
--   and "this checked /my/ worktree" without reading Haskell.  It is additive
--   like the issue-#77 fields before it — every pre-existing key keeps its name,
--   type, and meaning, and the new /failure/ shapes ('FailProject', and
--   'FailPath' from issue #101) are new kinds rather than changed ones — so the
--   schema version is unchanged.
--
--   'CheckProjectResult' (issue #78) is the whole-project gate's response.  It
--   carries the same @verdict@ / @command@ / @project@ echo as the per-file
--   tools, plus what only a project run has to say: which gate was chosen and
--   why ('Gate'), how far it got ('cprModulesChecked'), and whether its exit
--   code was masked by a wrapper ('cprMaskedFailure').  It is a new response
--   type rather than a change to an existing one, so the schema version is
--   again unchanged.
--
--   These types correspond 1-to-1 with the policy contract defined in
--   agda-dojang/python/tools/policy_contract.py, ensuring interoperability
--   between the Haskell MCP server and the Python evaluator/policy backends.
--
--   @get_goal@ and @fill_hole@ address a hole by a 'AgdaMCP.Holes.HoleRef' —
--   either a @(line, column)@ position in the file as written or the older
--   0-based @holeIndex@ (issue #79).  The two are parsed into one field, so a
--   request carries exactly one address and no handler has to decide which of a
--   disagreeing pair was meant.  @fill_hole@ and @check_file@ answer with the
--   full hole list ('HoleInfo'), the same shape @get_diagnostics@ already
--   returned, so a client re-anchors on positions without a second call.  Both
--   are additive: @holeIndex@ still parses and every pre-existing key keeps its
--   name, type, and meaning, so the schema version is unchanged.
--
--   The corpus types track the agda-strux JSONL schema (v0.01) documented in
--   docs/representation.md.  They are used by the search tools (M1-3).

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module AgdaMCP.Types
  ( -- * Context entries
    CtxEntry (..)
    -- * Tool parameters (inbound)
  , GetGoalParams (..)
  , FillHoleParams (..)
  , CheckFileParams (..)
  , GetDiagnosticsParams (..)
  , CheckProjectParams (..)
  , parseHoleRef
    -- * Response echo (issues #72, #76)
  , CommandEcho (..)
  , commandLine
  , Verdict (..)
  , RootSource (..)
  , LibraryEntry (..)
  , ProjectContext (..)
  , ProjectMismatch (..)
  , mismatchMessage
    -- * Requested-path failures (issue #101)
  , PathProblem (..)
  , PathFailure (..)
  , pathFailureMessage
    -- * Tool results (outbound)
  , ToolFailure (..)
  , TimeoutFailure (..)
  , GoalInfo (..)
  , HoleInfo (..)
  , FillResult (..)
  , FillStatus (..)
  , Diagnostic (..)
  , DiagSeverity (..)
  , DiagRange (..)
  , Involved (..)
  , noInvolved
  , hasInvolved
  , plainDiagnostic
  , FileCheckResult (..)
  , DiagnosticsResult (..)
    -- * The whole-project gate (issue #78)
  , GateSource (..)
  , Gate (..)
  , CheckProjectResult (..)
    -- * Hole location
  , HoleLocation (..)
    -- * Corpus types (agda-strux JSONL schema)
  , CorpusEntry (..)
  , CorpusIndex (..)
    -- * Tool parameters (inbound) — search
  , SearchByNameParams (..)
  , SearchByTypeParams (..)
  , GetDependenciesParams (..)
    -- * Tool results (outbound) — search
  , SearchResult (..)
  , DependenciesResult (..)
    -- * Tool parameters (inbound) — live queries (issue #75)
  , TypeOfParams (..)
  , NormalizeParams (..)
  , ResolveNameParams (..)
  , DefinitionOfParams (..)
  , ExportsOfParams (..)
    -- * Tool results (outbound) — live queries (issue #75)
  , LaneEcho (..)
  , LiveMeta (..)
  , LiveError (..)
  , DefSite (..)
  , ProvenanceEcho (..)
  , NameCandidate (..)
  , ExportEntry (..)
  , TypeOfResult (..)
  , NormalizeResult (..)
  , ResolveNameResult (..)
  , DefinitionOfResult (..)
  , ExportsOfResult (..)
  , InteractionFailure (..)
  ) where

import Data.Aeson
  ( FromJSON (..), ToJSON (..), Value (..), (.:), (.:?), (.!=), (.=)
  , object, withObject, withText
  )
import Data.Aeson.Types (Object, Pair, Parser)
import Data.Map.Strict (Map)
import Data.Text (Text)
import qualified Data.Text as T

import AgdaMCP.Holes (HoleRef (..))


-- ═══════════════════════════════════════════════════════════════════════════
-- Hole location
-- ═══════════════════════════════════════════════════════════════════════════

-- | Identifies a hole in a source file.
data HoleLocation = HoleLocation
  { holePath  :: FilePath   -- ^ Absolute or repo-relative path to the Agda file.
  , holeIndex :: Int        -- ^ 0-based index of the hole, in source order (any hole syntax: @{!!}@, @{! … !}@, @?@).
  } deriving (Eq, Show)

instance FromJSON HoleLocation where
  parseJSON = withObject "HoleLocation" $ \o ->
    HoleLocation <$> o .: "filePath" <*> o .: "holeIndex"

instance ToJSON HoleLocation where
  toJSON h = object ["filePath" .= holePath h, "holeIndex" .= holeIndex h]


-- ═══════════════════════════════════════════════════════════════════════════
-- Context entry (matches agda-dojang's AGDADOJANG_CTX line protocol)
-- ═══════════════════════════════════════════════════════════════════════════

-- | A single binder in the local context of a hole.
data CtxEntry = CtxEntry
  { ctxName       :: Text         -- ^ Binder name (e.g. "x").
  , ctxType       :: Text         -- ^ Pretty-printed type (e.g. "A").
  , ctxVisibility :: Maybe Text   -- ^ "visible" | "hidden" | "instance" (optional).
  , ctxIndex      :: Maybe Int    -- ^ De Bruijn index (optional).
  } deriving (Eq, Show)

instance FromJSON CtxEntry where
  parseJSON = withObject "CtxEntry" $ \o ->
    CtxEntry <$> o .:  "name"
             <*> o .:  "type"
             <*> o .:? "visibility"
             <*> o .:? "index"

instance ToJSON CtxEntry where
  toJSON e = object $
    [ "name" .= ctxName e
    , "type" .= ctxType e
    ] <> maybe [] (\v -> ["visibility" .= v]) (ctxVisibility e)
      <> maybe [] (\i -> ["index" .= i])      (ctxIndex e)


-- ═══════════════════════════════════════════════════════════════════════════
-- Tool parameters (inbound from agent)
-- ═══════════════════════════════════════════════════════════════════════════

-- | parseHoleRef: read the hole address out of a tool call's arguments
-- (issue #79).
--
-- The wire spelling is two alternatives — @line@ + @column@ (the position, the
-- handle to prefer) or @holeIndex@ (source-order, shift-prone, kept for
-- backward compatibility) — parsed into the one 'HoleRef' the handlers take.
-- @col@ is accepted in place of @column@ because that is how the hole listings
-- spell it, so a hole entry can be passed back without renaming a key.
--
-- The accepted shapes are exactly three: @holeIndex@, @line@ + @column@, and
-- @line@ + @col@.  They are the alternatives the tools' input schema advertises
-- as its @oneOf@ (see 'AgdaMCP.Server.addressAlternatives'), so a client that
-- validates its arguments and a client that just sends them get the same answer
-- about what is a legal request.
--
-- Every other combination is a parse failure naming the fix, because each one is
-- a client that does not know which hole it is asking about:
--
-- * an index /and/ a position — they can disagree, and picking one silently is
--   exactly the wrong-hole answer this addressing model exists to prevent;
-- * both @column@ and @col@ — one hole, one spelling, for the same reason;
-- * a lone @line@ or a lone column — half a position is not a position;
-- * /neither/ — there is nothing to address.
parseHoleRef :: Object -> Parser HoleRef
parseHoleRef o = do
  mIndex  <- o .:? "holeIndex"
  mLine   <- o .:? "line"
  mCol    <- o .:? "column"
  mColAlt <- o .:? "col"
  mColumn <- case (mCol, mColAlt) of
    (Just _, Just _) -> fail
      "column and col are two spellings of one thing; give one of them"
    _ -> pure (maybe mColAlt Just mCol)
  case (mIndex, mLine, mColumn) of
    (Nothing, Just ln, Just c) -> pure (ByPosition ln c)
    (Just i,  Nothing, Nothing) -> pure (ByIndex i)
    (Just _,  _, _) -> fail
      "give either (line, column) or holeIndex, not both: they can disagree, \
      \and guessing which one you meant is how a call fills the wrong hole"
    (Nothing, Just _, Nothing) -> fail
      "line was given without column; a position needs both"
    (Nothing, Nothing, Just _) -> fail
      "column was given without line; a position needs both"
    (Nothing, Nothing, Nothing) -> fail
      "no hole address: pass (line, column) — the handle to prefer, as reported \
      \by get_diagnostics.holes, check_file.holes, and every fill_hole response \
      \— or the older 0-based holeIndex"

-- | Parameters for the @get_goal@ tool.
data GetGoalParams = GetGoalParams
  { ggFilePath :: FilePath
  , ggHole     :: HoleRef     -- ^ Which hole, by position or by index (#79).
  } deriving (Eq, Show)

instance FromJSON GetGoalParams where
  parseJSON = withObject "GetGoalParams" $ \o ->
    GetGoalParams <$> o .: "filePath" <*> parseHoleRef o

-- | Parameters for the @fill_hole@ tool.
data FillHoleParams = FillHoleParams
  { fhFilePath  :: FilePath
  , fhHole      :: HoleRef    -- ^ Which hole, by position or by index (#79).
  , fhCandidate :: Text       -- ^ The candidate proof term to try.
  } deriving (Eq, Show)

instance FromJSON FillHoleParams where
  parseJSON = withObject "FillHoleParams" $ \o ->
    FillHoleParams <$> o .: "filePath" <*> parseHoleRef o <*> o .: "candidate"

-- | Parameters for the @check_file@ tool.
--
-- 'cfMaxDiagnostics' caps how many diagnostics the response carries; the total
-- found is always reported alongside, so a truncated list is never mistaken for
-- a short one.  @Nothing@ means the server default
-- ('AgdaMCP.Diagnostics.defaultMaxDiagnostics'); a non-positive number means
-- "no cap", the same spelling @--timeout 0@ uses (issue #74).
data CheckFileParams = CheckFileParams
  { cfFilePath       :: FilePath
  , cfMaxDiagnostics :: Maybe Int
  } deriving (Eq, Show)

instance FromJSON CheckFileParams where
  parseJSON = withObject "CheckFileParams" $ \o ->
    CheckFileParams <$> o .: "filePath" <*> o .:? "maxDiagnostics"

-- | Parameters for the @get_diagnostics@ tool.  'gdMaxDiagnostics' is the cap
-- described at 'CheckFileParams'.
data GetDiagnosticsParams = GetDiagnosticsParams
  { gdFilePath       :: FilePath
  , gdMaxDiagnostics :: Maybe Int
  } deriving (Eq, Show)

instance FromJSON GetDiagnosticsParams where
  parseJSON = withObject "GetDiagnosticsParams" $ \o ->
    GetDiagnosticsParams <$> o .: "filePath" <*> o .:? "maxDiagnostics"

-- | Parameters for the @check_project@ tool (issue #78).
--
-- Every field is optional, because the honest default is discoverable: the
-- project is the one the server is standing in, and its gate is the @check@
-- target of the nearest Makefile (or the @Everything@ module, or whatever the
-- operator configured with @--check-command@).  'cppMaxDiagnostics' is the cap
-- described at 'CheckFileParams'.
data CheckProjectParams = CheckProjectParams
  { cppTarget         :: Maybe Text     -- ^ A @make@ target to run instead of @check@.
  , cppProjectPath    :: Maybe FilePath -- ^ A file or directory anchoring the project
                                        --   (default: the server's working directory).
  , cppMaxDiagnostics :: Maybe Int      -- ^ Cap on the diagnostics returned.
  } deriving (Eq, Show)

instance FromJSON CheckProjectParams where
  parseJSON = withObject "CheckProjectParams" $ \o ->
    CheckProjectParams
      <$> o .:? "target"
      <*> o .:? "projectPath"
      <*> o .:? "maxDiagnostics"


-- ═══════════════════════════════════════════════════════════════════════════
-- § Response echo — what was run, what it means, and against which tree
--
-- Issues #72 (explicit batch verdict and command echo) and #76 (project-root
-- resolution and environment transparency).  These three records appear in
-- every proof-state response, success or failure.
-- ═══════════════════════════════════════════════════════════════════════════

-- | CommandEcho: the @agda@ invocation this call actually made.
--
-- Built from the argument vector handed to 'System.Process.createProcess', not
-- reconstructed afterwards, so it cannot drift from what ran.  @ceBinary@ is the
-- resolved absolute path when the configured name was found on @PATH@, and the
-- configured name otherwise; /which/ agda ran is a real question inside a Nix
-- shell, where the binary on @PATH@ is a wrapper that itself supplies flags.
data CommandEcho = CommandEcho
  { ceBinary :: FilePath    -- ^ The agda binary, resolved against @PATH@ where possible.
  , ceArgs   :: [String]    -- ^ The full argument vector, ending in the file path.
  , ceCwd    :: FilePath    -- ^ Working directory of the agda subprocess.
  } deriving (Eq, Show)

instance ToJSON CommandEcho where
  toJSON c = object
    [ "binary" .= ceBinary c
    , "args"   .= ceArgs c
    , "cwd"    .= ceCwd c
    ]

-- | commandLine: a 'CommandEcho' rendered as a copy-pasteable shell command.
--
-- Quoting is minimal and conservative: an argument is wrapped in single quotes
-- (with embedded quotes escaped) exactly when it contains a character a shell
-- would treat specially.  The result is meant to be /run/ by a human checking
-- the server against their own gate, so being over-cautious costs nothing and
-- being under-cautious would hand them a command that does something else.
commandLine :: CommandEcho -> Text
commandLine c = T.unwords (map (shellQuote . T.pack) (ceBinary c : ceArgs c))
  where
    shellQuote t
      | T.null t                = "''"
      | T.any needsQuoting t    = "'" <> T.replace "'" "'\\''" t <> "'"
      | otherwise               = t
    needsQuoting ch = ch `elem` (" \t\n'\"\\$`*?[]{}()<>|&;#~!" :: String)

-- | Verdict: what a green result from this call means, stated explicitly.
--
-- The field the whole of issue #72 is about.  An agent that reads only the
-- response — never this source — must be able to answer "does green here mean
-- my build passes?", and 'vEquivalentTo' answers it by naming the exact command
-- the verdict is equivalent to.  'vExitCode' is that command's own exit status:
-- @success@ is derived from it, never from parsing Agda's prose, so a change in
-- Agda's message wording cannot turn a failing build green.
data Verdict = Verdict
  { vEquivalentTo :: Text   -- ^ The @agda@ command this call is equivalent to.
                            --   Serialized behind an @equivalent-to:@ prefix,
                            --   which is what the response actually shows.
  , vMeaning      :: Text   -- ^ One sentence: what the tool's verdict field means.
  , vExitCode     :: Int    -- ^ The command's own exit code, when it produced one.
                            --   @-1@ stands for a run that produced none: the binary
                            --   could not be started, or the run was killed at the
                            --   @--timeout@ / @--check-timeout@ bound.  The response's
                            --   @timedOut@ flag distinguishes those two, and a start
                            --   failure additionally says so in its output.  A killed
                            --   process's real status is the signal that took it down —
                            --   indistinguishable from an ordinary failure — which is why
                            --   issue #77 reports the fact as a flag rather than as a
                            --   magic exit code.
  } deriving (Eq, Show)

instance ToJSON Verdict where
  toJSON v = object
    [ "equivalentTo" .= ("equivalent-to: " <> vEquivalentTo v)
    , "meaning"      .= vMeaning v
    , "exitCode"     .= vExitCode v
    ]

-- | RootSource: where the effective library context came from.
--
-- @nearest-agda-lib@ means the file's own tree decided it — the server walked
-- up from the requested path to the nearest @*.agda-lib@.  @server-config@
-- means no such file exists above the requested path, so the flags fixed at
-- server start (plus the file's own directory) are all the context there is.
data RootSource = RootFromAgdaLib | RootFromServerConfig
  deriving (Eq, Show)

instance ToJSON RootSource where
  toJSON RootFromAgdaLib      = String "nearest-agda-lib"
  toJSON RootFromServerConfig = String "server-config"

-- | LibraryEntry: one Agda library, as named by its @*.agda-lib@ file.
--
-- 'leIncludes' holds the library's @include:@ directories verbatim — relative
-- to 'leRoot', as the file writes them — because that, not the root alone, is
-- what actually lands on Agda's include path.
data LibraryEntry = LibraryEntry
  { leName     :: Text       -- ^ The library's @name:@ field.
  , leRoot     :: FilePath   -- ^ Directory containing the @*.agda-lib@ file.
  , leLibFile  :: FilePath   -- ^ Path of the @*.agda-lib@ file itself.
  , leIncludes :: [FilePath] -- ^ Its @include:@ directories, relative to 'leRoot'.
  } deriving (Eq, Show)

instance ToJSON LibraryEntry where
  toJSON e = object
    [ "name"     .= leName e
    , "root"     .= leRoot e
    , "libFile"  .= leLibFile e
    , "includes" .= leIncludes e
    ]

-- | ProjectContext: the library context a call was answered in — the @project@
-- key of every proof-state response.
--
-- This is the "which tree did you check?" answer that issue #76 exists to make
-- unmissable.  The registry ('pcLibrariesFile' and 'pcRegistered') is read
-- fresh on every call rather than snapshotted at startup, because it is shared
-- mutable state: the flake's shellHook rewrites the checkout-wide
-- @agda/libraries@ on every shell entry, so the file a long-running server
-- started with is not necessarily the file its next call will use.  Reporting
-- what @agda@ will actually read is the only honest option.
data ProjectContext = ProjectContext
  { pcRootSource    :: RootSource         -- ^ How 'pcRoot' was decided.
  , pcRoot          :: FilePath           -- ^ The effective root: the library's, or the file's directory.
  , pcLibrary       :: Maybe LibraryEntry -- ^ The file's own library, when it has one.
  , pcLibrariesFile :: Maybe FilePath     -- ^ The libraries registry that was configured
                                          --   or found — echoed whether or not it exists,
                                          --   so it never contradicts the @--library-file@
                                          --   in 'CommandEcho'.
  , pcLibrariesFileMissing :: Bool        -- ^ True when 'pcLibrariesFile' names a file that
                                          --   is not there.  Then 'pcRegistered' is empty
                                          --   not because the registry is empty but because
                                          --   it could not be read — and with nothing to
                                          --   contradict, wrong-tree detection cannot fire.
  , pcRegistered    :: [LibraryEntry]     -- ^ What that registry declares.
  , pcSelected      :: [Text]             -- ^ Library names Agda was given (@-l@), as
                                          --   finally assembled: the server's, plus
                                          --   anything resolution added.
  , pcIncludePaths  :: [FilePath]         -- ^ Include directories Agda was given (@-i@),
                                          --   likewise final — so these two always agree
                                          --   with 'CommandEcho' rather than describing a
                                          --   context Agda never saw.
  } deriving (Eq, Show)

instance ToJSON ProjectContext where
  toJSON p = object $
    [ "rootSource"          .= pcRootSource p
    , "root"                .= pcRoot p
    , "registeredLibraries" .= pcRegistered p
    , "selectedLibraries"   .= pcSelected p
    , "includePaths"        .= pcIncludePaths p
    ] <> maybe [] (\l -> ["library"       .= l]) (pcLibrary p)
      <> maybe [] (\f -> ["librariesFile" .= f]) (pcLibrariesFile p)
      -- Emitted only when true: an absent key is the ordinary case, and a
      -- present one is the caller's problem to fix.
      <> [ "librariesFileMissing" .= True | pcLibrariesFileMissing p ]

-- | ProjectMismatch: the requested file belongs to a different checkout of a
-- library the server already has registered somewhere else.
--
-- The loud failure of issue #76.  Checking anyway would resolve the file's
-- imports against 'pmRegisteredRoot' while the file itself lives under
-- 'pmFileRoot' — a green answer about a tree the caller never asked about,
-- which § 3.6 of the feedback document calls the worst possible outcome for an
-- agent client: "a wrong answer, not an error".
data ProjectMismatch = ProjectMismatch
  { pmFilePath       :: FilePath   -- ^ The file that was requested.
  , pmLibraryName    :: Text       -- ^ The library name both trees claim.
  , pmFileRoot       :: FilePath   -- ^ Root of the file's own @*.agda-lib@.
  , pmRegisteredRoot :: FilePath   -- ^ Root the registry gives that name.
  , pmLibrariesFile  :: FilePath   -- ^ The registry that says so.
  } deriving (Eq, Show)

-- | mismatchMessage: the human-readable form of a 'ProjectMismatch'.
--
-- Names both trees and the registry that disagrees with the file, then says
-- what to do about it.  An agent that can only read the error string still
-- learns everything the structured payload carries.
mismatchMessage :: ProjectMismatch -> Text
mismatchMessage m = T.concat
  [ "agda-mcp: refusing to check ", T.pack (pmFilePath m)
  , " — it belongs to a different checkout than the one this server has registered.\n"
  , "  the file's nearest *.agda-lib declares library '", pmLibraryName m
  , "' rooted at ", T.pack (pmFileRoot m), "\n"
  , "  but the libraries file ", T.pack (pmLibrariesFile m)
  , " registers '", pmLibraryName m, "' at ", T.pack (pmRegisteredRoot m), "\n"
  , "  Checking here would resolve this file's imports against "
  , T.pack (pmRegisteredRoot m)
  , " and report success about a tree you did not ask about.\n"
  , "  Fix: restart the server against ", T.pack (pmFileRoot m)
  , " (set the matching *_ROOT variable, or pass a --library-file whose '"
  , pmLibraryName m, "' entry points there)."
  ]

instance ToJSON ProjectMismatch where
  toJSON m = object
    [ "error"        .= mismatchMessage m
    , "rootMismatch" .= object
        [ "filePath"       .= pmFilePath m
        , "libraryName"    .= pmLibraryName m
        , "fileRoot"       .= pmFileRoot m
        , "registeredRoot" .= pmRegisteredRoot m
        , "librariesFile"  .= pmLibrariesFile m
        ]
    ]


-- | PathProblem: why a path the client sent could not be used.
--
-- Four cases rather than one, because the fix differs: a path that names
-- nothing is usually a path resolved against the wrong directory, a path that
-- names a directory is a caller passing the project instead of the file, a path
-- that names something that is neither is not Agda source at all, and a path
-- that names a readable-looking file we cannot open is a permissions or
-- hardware problem the caller cannot fix by rewriting the argument.
--
-- 'PathNotRegular' is the one that is about this server's survival rather than
-- about the caller's mistake, and it earns its own case for that reason.  A
-- FIFO, a socket, or a device passes an existence check and then reads
-- unboundedly or not at all: measured against @\/dev\/zero@, the read consumed
-- memory until the heap was exhausted and the process died; measured against a
-- named pipe with a writer attached, the read blocked forever, and it blocks
-- /before/ @--timeout@ has anything to bound, since that bound applies to the
-- @agda@ subprocess and this read happens first.  Neither is a failure the
-- client can even be told about, because the server does not survive to answer
-- (Copilot's review of PR 102).
data PathProblem
  = PathMissing            -- ^ Nothing is at the resolved path.
  | PathNotAFile           -- ^ Something is there, but it is a directory.
  | PathNotRegular Text    -- ^ Neither file nor directory: a FIFO, socket, or device.
  | PathUnreadable Text    -- ^ It is a regular file, but opening or decoding it failed.
  deriving (Eq, Show)

-- | PathFailure: the requested path could not be turned into a file this
-- server can read, and here is everything needed to see why.
--
-- The loud failure of issue #101, and the companion to 'ProjectMismatch'.
-- Where that one answers /which tree did you check?/, this one answers the
-- question before it: /which file did you mean, and where did I look for it?/
--
-- Both defects the field test hit are this one payload.  A relative path is
-- resolved against the __server's__ working directory — the server is a
-- separate process, and @scripts\/run-server.sh@ deliberately starts it in the
-- agda-native-air checkout (issue #76), so a path relative to the /client's/
-- project names a file in the wrong tree, or, far more often, no file at all.
-- And a path naming no file used to reach @readFile@ and throw, which escaped
-- the handler as JSON-RPC @-32603 Internal error@: an error that names neither
-- the path nor the rule, and so teaches a client nothing.  Issue #101's field
-- evidence is an agent that got exactly that on its first call and never
-- called the server again.
--
-- Reporting 'pfRequested' and 'pfResolved' side by side is the point: a caller
-- who can see that @src\/Foo.agda@ became
-- @\/home\/…\/agda-native-air\/src\/Foo.agda@ has diagnosed the whole problem
-- without reading any documentation.
data PathFailure = PathFailure
  { pfParameter :: Text        -- ^ The argument that carried it (@filePath@, @projectPath@).
  , pfRequested :: FilePath    -- ^ Exactly what the client sent.
  , pfResolved  :: FilePath    -- ^ What this server resolved it to.
  , pfRelative  :: Bool        -- ^ True when the client sent a relative path.
  , pfServerCwd :: FilePath    -- ^ The directory relative paths are resolved against.
  , pfProblem   :: PathProblem -- ^ What went wrong at 'pfResolved'.
  } deriving (Eq, Show)

-- | pathFailureMessage: the human-readable form of a 'PathFailure'.
--
-- Same house style as 'mismatchMessage': name the offending path, say
-- precisely what went wrong, and state the fix.  An agent that reads only the
-- error string still learns the rule — which is the whole repair, since the
-- @-32603@ this replaces taught nothing and ended adoption.
pathFailureMessage :: PathFailure -> Text
pathFailureMessage f = T.concat $
  [ "agda-mcp: ", pfParameter f, " ", verb, ": ", T.pack (pfResolved f), "\n" ]
  <> detail
  <> hazard
  <> resolution
  <> diagnosis
  <> [ "  this server's working directory: ", T.pack (pfServerCwd f), "\n"
     , "  Fix: ", fix ]
  where
    verb = case pfProblem f of
      PathMissing       -> "does not exist"
      PathNotAFile      -> "is a directory, not a file"
      PathNotRegular ty -> "is not a regular file, it is " <> ty
      -- Not "could not be read": 'AgdaMCP.Path.ioProblem' produces this case
      -- from the @stat@ as well as from the @open@, and a @stat@ that was
      -- refused means no read was attempted at all.  The detail line below
      -- carries the operating system's own message, which names the call that
      -- failed, so the summary does not have to guess at it.
      PathUnreadable _  -> "was refused by the operating system"

    detail = case pfProblem f of
      PathUnreadable why -> [ "  ", why, "\n" ]
      _                  -> []

    -- Why refusing a non-regular file is this server's business and not the
    -- caller's: the read, not the typecheck, is what would never come back.
    --
    -- Stated as the policy and the two cases that motivate it rather than as a
    -- property of whatever is actually there, because that property does not
    -- hold of every type this case covers: opening a unix socket fails at once
    -- with ENXIO (measured: "No such device or address"), and a block device is
    -- bounded by its size.  "Reading one is unbounded or blocking" was therefore
    -- true of the two types measured and false of the other two.
    hazard = case pfProblem f of
      PathNotRegular _ ->
        [ "  This server opens regular files only. Reading anything else can block\n"
        , "  forever (a FIFO waits for a writer) or never reach EOF (a character device\n"
        , "  such as /dev/zero), and it would do so before --timeout has anything to\n"
        , "  bound: that bound applies to the agda subprocess, and the read happens\n"
        , "  first.\n" ]
      _ -> []

    -- How the path was resolved: a fact about this call, stated for every
    -- failure.  Deliberately only the fact — the /diagnosis/ is separate, below,
    -- because it is not true of every failure.
    --
    -- The absolute arm claims resolution, not spelling.  An earlier version said
    -- the path "was used exactly as you sent it", which the two fields beside it
    -- can visibly contradict: 'System.Directory.makeAbsolute' normalises, so an
    -- absolute @\/a\/.\/b@ or @\/a\/\/b@ arrives as @\/a\/b@ (@..@ it leaves
    -- alone).  What is true of every absolute path is that the server's working
    -- directory had no part in it.
    resolution
      -- An empty path is relative, and 'makeAbsolute' turns it into the working
      -- directory itself.  Saying "you sent a RELATIVE path: " with nothing
      -- after the colon described that as a path the caller could go and look
      -- at; naming it for what it was is both shorter and true.
      | pfRelative f, null (pfRequested f) =
          [ "  you sent an EMPTY path, which resolves to this server's own working\n"
          , "  directory.\n" ]
      | pfRelative f =
          [ "  you sent a RELATIVE path (", T.pack (pfRequested f)
          , "), which this server resolved against its own\n"
          , "  working directory.\n" ]
      | otherwise =
          [ "  the path was absolute, so this server's working directory was not \
            \used to resolve it.\n" ]

    -- The sentence issue #101 exists to publish — and it belongs only on the
    -- failure it explains.
    --
    -- It used to be part of 'resolution', so every relative-path failure carried
    -- it.  That made a message argue with itself: a relative path naming a
    -- /directory/ resolved to something that is really there, so "a path
    -- relative to your project does not name your file here" was both beside the
    -- point and not established — for a client whose own directory is this
    -- server's, which is the in-repo case, it is plainly false — and the Fix
    -- line beneath it then gave an unrelated remedy.  Two competing diagnoses in
    -- one error is how a reader ends up trusting neither.  It is stated for
    -- 'PathMissing' alone, which is the only case where resolving against the
    -- wrong directory is what went wrong.
    diagnosis = case pfProblem f of
      PathMissing | pfRelative f ->
        [ "  This server is a separate process, normally started in its own checkout\n"
        , "  rather than in your project, so a path relative to your project does not\n"
        , "  name your file here.\n" ]
      _ -> []

    fix = case pfProblem f of
      PathNotAFile     -> "pass the Agda source file itself, not the directory holding it."
      PathNotRegular _ -> "pass a path naming an ordinary file of Agda source."
      -- Deliberately not "check the file's permissions".  Every failure that is
      -- not absence lands here — a permission wall, a symbolic-link loop, a
      -- device error — so naming one of them would be the same false-advice
      -- defect twice over: it asserts a cause this server did not establish, and
      -- it asserts a read that may never have happened.
      PathUnreadable _ -> "act on the reason above; it is the operating system's own, \
                          \it names the call that failed, and this server got no \
                          \further than reporting it."
      PathMissing
        -- Nothing to append for an empty path, and "followed by ." would have
        -- been the result of appending it anyway.
        | pfRelative f, null (pfRequested f) ->
            "pass an ABSOLUTE path to the file you meant."
        -- Actionable rather than merely correct: the caller knows its own
        -- project directory, so naming the two halves of the answer is the
        -- whole of the repair.
        | pfRelative f -> "pass an ABSOLUTE path: YOUR project's directory, followed by "
                          <> T.pack (pfRequested f) <> "."
        | otherwise    -> "check the path; nothing is there. (A relative path would be \
                          \resolved against the working directory above, never against \
                          \yours.)"

instance ToJSON PathProblem where
  toJSON PathMissing         = "missing"
  toJSON PathNotAFile        = "notAFile"
  toJSON (PathNotRegular _)  = "notRegularFile"
  toJSON (PathUnreadable _)  = "unreadable"

instance ToJSON PathFailure where
  toJSON f = object
    [ "error"     .= pathFailureMessage f
    , "pathError" .= object
        ( [ "parameter"     .= pfParameter f
          , "requestedPath" .= pfRequested f
          , "resolvedPath"  .= pfResolved f
          , "relative"      .= pfRelative f
          , "serverCwd"     .= pfServerCwd f
          , "problem"       .= pfProblem f
          ]
          -- Two cases have something to add: the underlying 'IOException' text,
          -- which names the syscall that refused, and the file type that was
          -- there instead of a regular file.
          <> case pfProblem f of
               PathUnreadable why -> [ "detail" .= why ]
               PathNotRegular ty  -> [ "detail" .= ty ]
               _                  -> [] )
    ]


-- ═══════════════════════════════════════════════════════════════════════════
-- Tool results (outbound to agent)
-- ═══════════════════════════════════════════════════════════════════════════

-- | A tool failure that still carries whatever the call managed to establish.
--
-- @get_goal@ is the one proof-state tool whose timeout cannot be folded into a
-- success-shaped response — there is no goal to report — so without this the
-- timing and cache metadata the call did produce would be dropped on the floor
-- of a plain error string (issue #77).  'FailProject' generalizes the same idea
-- to a failure that happens /before/ Agda is ever started (issue #76): the
-- structured payload names both trees, so a client sees the mismatch as data
-- rather than having to parse a sentence.  'FailPath' is the same move one step
-- earlier still (issue #101) — the requested path named no readable file, so
-- there is no tree to resolve, and no Agda run to describe — and it exists
-- because that case used to escape the handler as an uncaught 'IOException'
-- and reach the client as a bare @-32603 Internal error@.  'FailMessage' keeps
-- every ordinary failure exactly as it was: prose in, prose out.
--
-- All four proof-state tools fail through this type, so a client has one
-- failure shape to handle rather than one per tool.
data ToolFailure
  = FailMessage Text            -- ^ An ordinary failure; rendered as plain text.
  | FailTimeout TimeoutFailure  -- ^ The call hit @--timeout@; rendered as JSON.
  | FailProject ProjectMismatch -- ^ The file belongs to a different checkout; rendered as JSON.
  | FailPath    PathFailure     -- ^ The path named no readable file; rendered as JSON.
  | FailInteraction InteractionFailure
                                -- ^ The interaction lane's process failed the
                                --   call — a spawn failure, a timeout kill, or
                                --   a crash; rendered as JSON (issue #75).
  deriving (Eq, Show)

-- | The structured payload of a timed-out tool call: what went wrong, and what
-- the call still managed to measure on the way down.
--
-- It carries the same 'Verdict' / 'CommandEcho' / 'ProjectContext' echo as a
-- successful response, because a timeout is exactly the case where a caller
-- most needs to know which command against which tree ran out of time — a cold
-- interface build for a large library is the usual cause, and the answer is
-- visible in the flags.
data TimeoutFailure = TimeoutFailure
  { tfMessage           :: Text        -- ^ Human-readable explanation (names the bound).
  , tfElapsedMs         :: Int         -- ^ Wall-clock ms before the process was killed.
  , tfCheckedFromSource :: Maybe Bool  -- ^ Cache signal, when the killed run produced evidence.
  , tfVerdict           :: Verdict        -- ^ What was run and what it would have meant (#72).
  , tfCommand           :: CommandEcho    -- ^ The resolved agda command line (#72).
  , tfProject           :: ProjectContext -- ^ The tree that was being checked (#76).
  } deriving (Eq, Show)

instance ToJSON TimeoutFailure where
  toJSON t = object $
    [ "error"     .= tfMessage t
    , "timedOut"  .= True
    , "elapsedMs" .= tfElapsedMs t
    , "verdict"   .= tfVerdict t
    , "command"   .= tfCommand t
    , "project"   .= tfProject t
    ] <> maybe [] (\b -> ["checkedFromSource" .= b]) (tfCheckedFromSource t)

-- | Result of @get_goal@: the hole's goal type and local context.
--
-- 'giElapsedMs' and 'giCheckedFromSource' are optional so a 'GoalInfo' can be
-- built without a timed Agda run (hole listings use 'HoleInfo' instead); the
-- top-level @get_goal@ response always populates both.  'giVerdict',
-- 'giCommand', and 'giProject' are optional for the same reason and are always
-- populated by the tool.
data GoalInfo = GoalInfo
  { giGoal              :: Text         -- ^ Pretty-printed goal type.
  , giContext           :: [CtxEntry]   -- ^ Local context (bound variables with types).
  , giModule            :: Maybe Text   -- ^ Module name: the one Agda resolved, else the one the source declares.
  , giElapsedMs         :: Maybe Int    -- ^ Wall-clock ms spent in the Agda subprocess.
  , giCheckedFromSource :: Maybe Bool   -- ^ Did Agda re-check from source (vs. load @.agdai@)?
  , giVerdict           :: Maybe Verdict        -- ^ What was run and what it means (#72).
  , giCommand           :: Maybe CommandEcho    -- ^ The resolved agda command line (#72).
  , giProject           :: Maybe ProjectContext -- ^ The tree that was checked (#76).
  } deriving (Eq, Show)

instance ToJSON GoalInfo where
  toJSON g = object $
    [ "goal"    .= giGoal g
    , "context" .= giContext g
    ] <> maybe [] (\m -> ["module"            .= m]) (giModule g)
      <> maybe [] (\m -> ["elapsedMs"         .= m]) (giElapsedMs g)
      <> maybe [] (\b -> ["checkedFromSource" .= b]) (giCheckedFromSource g)
      <> maybe [] (\v -> ["verdict"           .= v]) (giVerdict g)
      <> maybe [] (\c -> ["command"           .= c]) (giCommand g)
      <> maybe [] (\p -> ["project"           .= p]) (giProject g)

-- | One open hole in a file, as listed by @get_diagnostics@, @check_file@, and
-- @fill_hole@.  The index is the 0-based @holeIndex@ that @get_goal@ /
-- @fill_hole@ accept; line and column are 1-based positions in the file as
-- written, so for literate sources they are literate-file coordinates (issue
-- #73).
--
-- @line@ and @col@ are the pair to pass back: they describe where the hole's
-- text sits, so a fill moves them only when it changes the text above them,
-- whereas @index@ is a place in the source-order list and is renumbered by any
-- fill at all (issue #79).  Neither is a permanent name: take the listing from
-- the latest response.
data HoleInfo = HoleInfo
  { hiIndex :: Int    -- ^ 0-based hole index (source order).
  , hiLine  :: Int    -- ^ 1-based line of the hole's first character.
  , hiCol   :: Int    -- ^ 1-based column of the hole's first character.
  , hiGoal  :: Text   -- ^ Goal type placeholder (v0: "?"; per-hole goal extraction is a future enhancement).
  } deriving (Eq, Show)

instance ToJSON HoleInfo where
  toJSON h = object
    [ "index" .= hiIndex h
    , "line"  .= hiLine h
    , "col"   .= hiCol h
    , "goal"  .= hiGoal h
    ]

-- | Outcome of a @fill_hole@ attempt.
data FillStatus = FillOk | FillTypeError | FillTimeout | FillCrash
  deriving (Eq, Show)

instance ToJSON FillStatus where
  toJSON FillOk        = String "ok"
  toJSON FillTypeError = String "type_error"
  toJSON FillTimeout   = String "timeout"
  toJSON FillCrash     = String "crash"

instance FromJSON FillStatus where
  parseJSON = withText "FillStatus" $ \t -> case t of
    "ok"         -> pure FillOk
    "type_error" -> pure FillTypeError
    "timeout"    -> pure FillTimeout
    "crash"      -> pure FillCrash
    other        -> fail $ "Unknown FillStatus: " <> show other

-- | Result of @fill_hole@.
--
-- 'frHoles' is the re-anchoring payload of issue #79: the holes of the file /as
-- this candidate leaves it/, so a client that keeps the candidate has the next
-- hole's position without a second call.  It describes the patched content, not
-- the bytes on disk — @fill_hole@ restores the file — so until the candidate is
-- written back the file still has the holes it started with.  'frRemainingHoles'
-- is its length, kept as the pre-#79 scalar.
data FillResult = FillResult
  { frStatus    :: FillStatus
  , frCandidate :: Text           -- ^ The candidate that was tried.
  , frMessage   :: Maybe Text     -- ^ Agda error message on failure; Nothing on success.
  , frRemainingHoles :: Maybe Int -- ^ Number of remaining holes after filling (if determinable).
  , frHoles     :: [HoleInfo]     -- ^ Those holes, with index and (line, col) (#79).
  , frElapsedMs :: Int            -- ^ Wall-clock ms spent in the Agda subprocess.
  , frCheckedFromSource :: Maybe Bool -- ^ Did Agda re-check from source (vs. load
                                  --   @.agdai@)?  Nothing — and the field omitted —
                                  --   when the run died before producing evidence.
  , frVerdict   :: Verdict        -- ^ What was run and what @status@ means (#72).
  , frCommand   :: CommandEcho    -- ^ The resolved agda command line (#72).
  , frProject   :: ProjectContext -- ^ The tree that was checked (#76).
  } deriving (Eq, Show)

instance ToJSON FillResult where
  toJSON r = object $
    [ "status"            .= frStatus r
    , "candidate"         .= frCandidate r
    , "holes"             .= frHoles r
    , "elapsedMs"         .= frElapsedMs r
    , "verdict"           .= frVerdict r
    , "command"           .= frCommand r
    , "project"           .= frProject r
    ] <> maybe [] (\m -> ["message"  .= m]) (frMessage r)
      <> maybe [] (\n -> ["remainingHoles" .= n]) (frRemainingHoles r)
      <> maybe [] (\b -> ["checkedFromSource" .= b]) (frCheckedFromSource r)

-- | Severity level for a diagnostic.
data DiagSeverity = DiagError | DiagWarning | DiagInfo
  deriving (Eq, Show)

instance ToJSON DiagSeverity where
  toJSON DiagError   = String "error"
  toJSON DiagWarning = String "warning"
  toJSON DiagInfo    = String "info"

-- | A source range, in 1-based (line, column) coordinates of the file as
-- written — literate-file coordinates for literate sources, matching what an
-- editor shows and what Agda's own messages print.
--
-- Agda prints a same-line range as @9.12-13@ (Agda ≥ 2.6.2) or @9,12-13@
-- (older), and a multi-line one as @9.12-11.5@ / @9,12-11,3@; both spellings
-- parse to the same four numbers here (issue #74).  A range that names a single
-- position has @end == start@.
data DiagRange = DiagRange
  { rngStartLine :: Int
  , rngStartCol  :: Int
  , rngEndLine   :: Int
  , rngEndCol    :: Int
  } deriving (Eq, Show)

instance ToJSON DiagRange where
  toJSON r = object
    [ "startLine" .= rngStartLine r
    , "startCol"  .= rngStartCol r
    , "endLine"   .= rngEndLine r
    , "endCol"    .= rngEndCol r
    ]

-- | The entities a diagnostic is about, lifted out of its prose so a client can
-- act on them without a regex (feedback document § 3.4, error corpus § 5).
--
-- Which fields are populated depends on the diagnostic's 'diagCode'; the
-- extraction is best-effort, and an absent field means "Agda did not print
-- one", never "there is none".
--
-- +---------------------------+------------------------------------------------+
-- | Code                      | Payload                                        |
-- +===========================+================================================+
-- | @UnequalTerms@ and other  | 'invActual' and 'invExpected': the two sides   |
-- | mismatches                | of Agda's @A != B@ / @A !=< B@ line, in that   |
-- |                           | order (Agda prints the actual type first).     |
-- +---------------------------+------------------------------------------------+
-- | @NotInScope@              | 'invCandidates': the "did you mean" names,     |
-- |                           | qualified as Agda prints them (so the module   |
-- |                           | that would export each one is visible).        |
-- +---------------------------+------------------------------------------------+
-- | @AmbiguousName@,          | 'invCandidates': the qualified names the       |
-- | @AmbiguousModule@, …      | ambiguous one could refer to.                  |
-- +---------------------------+------------------------------------------------+
-- | @ModuleDoesntExport@      | 'invCandidates': the names the module does not |
-- |                           | export.                                        |
-- +---------------------------+------------------------------------------------+
-- | @ClashingDefinition@, …   | 'invCandidates': the origin of the pre-existing|
-- |                           | definition, as Agda's @file:range@ location.   |
-- +---------------------------+------------------------------------------------+
-- | @UnsolvedMetaVariables@,  | 'invMetaTypes': one entry per meta or          |
-- | @UnsolvedConstraints@,    | constraint Agda lists — locations for the meta |
-- | @UnsolvedInteractionMetas@| classes, and the blocked constraint with its   |
-- |                           | type for @UnsolvedConstraints@.                |
-- +---------------------------+------------------------------------------------+
data Involved = Involved
  { invExpected   :: Maybe Text  -- ^ The expected type, where Agda names one.
  , invActual     :: Maybe Text  -- ^ The actual (inferred) type, where Agda names one.
  , invCandidates :: [Text]      -- ^ The names involved, qualified as Agda prints them.
  , invMetaTypes  :: [Text]      -- ^ One entry per unsolved meta or constraint.
  } deriving (Eq, Show)

-- | The empty payload: a diagnostic whose prose named nothing extractable.
noInvolved :: Involved
noInvolved = Involved
  { invExpected   = Nothing
  , invActual     = Nothing
  , invCandidates = []
  , invMetaTypes  = []
  }

-- | Did anything get extracted?  Drives omission of the @involved@ key, so an
-- empty payload costs a client nothing to skip.
hasInvolved :: Involved -> Bool
hasInvolved i = i /= noInvolved

instance ToJSON Involved where
  toJSON i = object $
    maybe [] (\e -> ["expected" .= e]) (invExpected i)
    <> maybe [] (\a -> ["actual" .= a]) (invActual i)
    <> (if null (invCandidates i) then [] else ["candidates" .= invCandidates i])
    <> (if null (invMetaTypes i)  then [] else ["metaTypes"  .= invMetaTypes i])

-- | A single diagnostic (error, warning, or info) from Agda.
--
-- The shape is issue #74's: 'diagCode' is Agda's own bracketed name, so a client
-- branches on it instead of matching prose; 'diagFile' and 'diagRange' locate it
-- without regexing the header; and 'diagMessage' is the bounded /full/ message
-- body, not just the header line.  All four are optional because Agda does not
-- always print them — @error: [UnsolvedConstraints]@, for one, carries no
-- location at all.
data Diagnostic = Diagnostic
  { diagSeverity :: DiagSeverity
  , diagCode     :: Maybe Text        -- ^ Agda's bracketed name, e.g. @UnsolvedMetaVariables@.
  , diagFile     :: Maybe FilePath    -- ^ The file the position refers to (may differ from the checked file).
  , diagRange    :: Maybe DiagRange   -- ^ Source range, 1-based, in the file as written.
  , diagMessage  :: Text              -- ^ The full message body, bounded (see 'AgdaMCP.Diagnostics').
  , diagInvolved :: Involved          -- ^ The entities named in the message.
  } deriving (Eq, Show)

-- | plainDiagnostic: a diagnostic that is ours rather than Agda's — severity and
-- prose, with no code, position, or payload to report (the timeout notice).
plainDiagnostic :: DiagSeverity -> Text -> Diagnostic
plainDiagnostic sev msg = Diagnostic
  { diagSeverity = sev
  , diagCode     = Nothing
  , diagFile     = Nothing
  , diagRange    = Nothing
  , diagMessage  = msg
  , diagInvolved = noInvolved
  }

-- | The wire form.  @line@ and @col@ are the range's start, retained under their
-- original names so pre-#74 clients keep working unchanged.
instance ToJSON Diagnostic where
  toJSON d = object $
    [ "severity" .= diagSeverity d ]
    <> maybe [] (\c -> ["code"  .= c]) (diagCode d)
    <> maybe [] (\f -> ["file"  .= f]) (diagFile d)
    <> maybe [] (\r -> [ "range" .= r
                       , "line"  .= rngStartLine r
                       , "col"   .= rngStartCol r
                       ]) (diagRange d)
    <> [ "message" .= diagMessage d ]
    <> (if hasInvolved (diagInvolved d) then ["involved" .= diagInvolved d] else [])

-- | Result of @check_file@.
--
-- 'fcrSuccess' is a function of Agda's exit code alone (echoed as
-- @verdict.exitCode@) and the timeout flag — never of the diagnostics list.
-- Deriving it from parsed messages instead would make the verdict hostage to
-- Agda's prose: a format change would silently empty 'fcrDiagnostics' and
-- report a passing build (issue #72).
--
-- 'fcrHoles' lists the holes 'fcrHolesCount' counts, so the first call of a
-- session already hands back the positions to address them by (issue #79).
data FileCheckResult = FileCheckResult
  { fcrSuccess     :: Bool          -- ^ True iff Agda exited 0, in time.
  , fcrDiagnostics :: [Diagnostic]  -- ^ Up to @maxDiagnostics@ of them, most likely root cause first.
  , fcrDiagnosticsTotal :: Int      -- ^ How many were found before the cap; equals
                                    --   @length fcrDiagnostics@ when nothing was dropped.
  , fcrHolesCount  :: Int           -- ^ Number of open holes (any hole syntax, code regions only).
  , fcrHoles       :: [HoleInfo]    -- ^ Those holes, with index and (line, col) — the
                                    --   anchors to address them by (#79).  Free here:
                                    --   the same scan already produced the count.
  , fcrTimedOut    :: Bool          -- ^ True iff the check hit the @--timeout@ bound.
                                    --   When set, 'fcrSuccess' is False and the timeout
                                    --   appears as an error in 'fcrDiagnostics'.
  , fcrElapsedMs   :: Int           -- ^ Wall-clock ms spent in the Agda subprocess.
  , fcrCheckedFromSource :: Maybe Bool -- ^ Did Agda re-check from source (vs. load
                                    --   @.agdai@)?  Nothing — and the field omitted —
                                    --   when the run died before producing evidence.
  , fcrVerdict     :: Verdict        -- ^ What was run and what @success@ means (#72).
  , fcrCommand     :: CommandEcho    -- ^ The resolved agda command line (#72).
  , fcrProject     :: ProjectContext -- ^ The tree that was checked (#76).
  } deriving (Eq, Show)

instance ToJSON FileCheckResult where
  toJSON r = object $
    [ "success"           .= fcrSuccess r
    , "diagnostics"       .= fcrDiagnostics r
    , "diagnosticsTotal"  .= fcrDiagnosticsTotal r
    , "holesCount"        .= fcrHolesCount r
    , "holes"             .= fcrHoles r
    , "timedOut"          .= fcrTimedOut r
    , "elapsedMs"         .= fcrElapsedMs r
    , "verdict"           .= fcrVerdict r
    , "command"           .= fcrCommand r
    , "project"           .= fcrProject r
    ] <> maybe [] (\b -> ["checkedFromSource" .= b]) (fcrCheckedFromSource r)

-- | Result of @get_diagnostics@ (cached state from last check).
--
-- 'drDiagnostics' exposes the parsed diagnostics this tool already computed in
-- order to produce 'drErrors' / 'drWarnings'.  Surfacing the list is what lets a
-- timeout be reported the same way @check_file@ reports it — @success: false@
-- plus an explanatory error entry — rather than as a silent zero-error summary
-- of output Agda never got to produce.
--
-- The counts are over /every/ diagnostic found, not over the capped list, so
-- @maxDiagnostics@ shortens the payload without ever understating how much is
-- wrong (issue #74).
--
-- 'drSuccess' and 'drVerdict' are the same fields @check_file@ carries, with
-- the same meaning and the same derivation from Agda's exit code (issue #72).
-- The counts are a convenience over Agda's prose; the verdict is not, which is
-- why a message-format drift can zero 'drErrors' but can never flip
-- 'drSuccess'.
data DiagnosticsResult = DiagnosticsResult
  { drFilePath    :: FilePath
  , drErrors      :: Int
  , drWarnings    :: Int
  , drHoles       :: [HoleInfo]  -- ^ Open holes with index and (line, col).
  , drSuccess     :: Bool        -- ^ True iff Agda exited 0, in time.
  , drDiagnostics :: [Diagnostic]-- ^ Up to @maxDiagnostics@ of them, most likely root cause first.
  , drDiagnosticsTotal :: Int    -- ^ How many were found before the cap.
  , drTimedOut    :: Bool        -- ^ True iff the run hit the @--timeout@ bound.
  , drElapsedMs   :: Int         -- ^ Wall-clock ms spent in the Agda subprocess.
  , drCheckedFromSource :: Maybe Bool -- ^ Did Agda re-check from source (vs. load
                                 --   @.agdai@)?  Nothing — and the field omitted —
                                 --   when the run died before producing evidence.
  , drVerdict     :: Verdict        -- ^ What was run and what @success@ means (#72).
  , drCommand     :: CommandEcho    -- ^ The resolved agda command line (#72).
  , drProject     :: ProjectContext -- ^ The tree that was checked (#76).
  } deriving (Eq, Show)

instance ToJSON DiagnosticsResult where
  toJSON r = object $
    [ "filePath"          .= drFilePath r
    , "errors"            .= drErrors r
    , "warnings"          .= drWarnings r
    , "holes"             .= drHoles r
    , "success"           .= drSuccess r
    , "diagnostics"       .= drDiagnostics r
    , "diagnosticsTotal"  .= drDiagnosticsTotal r
    , "timedOut"          .= drTimedOut r
    , "elapsedMs"         .= drElapsedMs r
    , "verdict"           .= drVerdict r
    , "command"           .= drCommand r
    , "project"           .= drProject r
    ] <> maybe [] (\b -> ["checkedFromSource" .= b]) (drCheckedFromSource r)

-- ═══════════════════════════════════════════════════════════════════════════
-- § The whole-project gate (issue #78)
--
-- @check_project@ runs the project's own acceptance gate — a @make@ target, an
-- operator-configured command, or @agda@ on the project's @Everything@ module —
-- and reports its verdict without ever misreporting its exit code.
-- ═══════════════════════════════════════════════════════════════════════════

-- | GateSource: how the command that ran was decided.
--
-- Which one it was matters to a caller: @makefile-target@ and
-- @everything-module@ were /discovered/ from the tree and can be re-derived by
-- reading it, while @server-config@ is whatever the operator passed to
-- @--check-command@ and is knowable only from this echo.
data GateSource = GateFromMakefile | GateFromServerConfig | GateFromEverything
  deriving (Eq, Show)

instance ToJSON GateSource where
  toJSON GateFromMakefile     = String "makefile-target"
  toJSON GateFromServerConfig = String "server-config"
  toJSON GateFromEverything   = String "everything-module"

-- | Gate: which gate was chosen, and on what evidence.
--
-- The command itself is /not/ here — it is the response's 'CommandEcho', built
-- from the argument vector actually handed to the process, exactly as it is for
-- the per-file tools.  This record answers the question the echo cannot: why
-- that command and not another one.
data Gate = Gate
  { gateSource       :: GateSource   -- ^ How the command was decided.
  , gateTarget       :: Maybe Text   -- ^ The @make@ target, when the gate is one.
  , gateMakefile     :: Maybe FilePath -- ^ The Makefile that declares it.
  , gateEntry        :: Maybe FilePath -- ^ The @Everything@ module, when it is the gate.
  , gateSearchedFrom :: FilePath     -- ^ The directory discovery started from — the
                                     --   requested @projectPath@, or the server's
                                     --   working directory when none was given.
  } deriving (Eq, Show)

instance ToJSON Gate where
  toJSON g = object $
    [ "source"       .= gateSource g
    , "searchedFrom" .= gateSearchedFrom g
    ] <> maybe [] (\t -> ["target"   .= t]) (gateTarget g)
      <> maybe [] (\m -> ["makefile" .= m]) (gateMakefile g)
      <> maybe [] (\e -> ["entry"    .= e]) (gateEntry g)

-- | Result of @check_project@: the gate's verdict, and the evidence for it.
--
-- 'cprSuccess' is a /conjunction/, and deliberately so.  The per-file tools
-- read success off Agda's exit code and nothing else (issue #72), because there
-- the only failure mode worth defending against is Agda's prose drifting and
-- silently turning a red build green.  A project gate has a second failure mode
-- the field session met head-on: a wrapper script whose last command is an
-- @echo@ exits 0 whatever @make@ did, so the shell's exit code says the build
-- passed while the log is full of errors — which is why that session had to
-- grep its logs for @error:@ four times.  So:
--
--   * the gate's exit code is echoed verbatim as @verdict.exitCode@ and is
--     never overridden or reinterpreted — with the one qualification 'Verdict'
--     documents, that a run which produced no status of its own (never started,
--     or killed at the bound) reports @-1@, which 'cprTimedOut' disambiguates;
--   * 'cprSuccess' is true only when that code is 0, the run finished inside
--     its bound, /and/ no failure evidence was found in its output — an Agda
--     error diagnostic, or the gate's own failure line (make reporting a recipe
--     that died);
--   * the third conjunct failing on its own is 'cprMaskedFailure', named and
--     reported rather than folded silently into the verdict.
--
-- The evidence can therefore make a green gate red, never the other way round —
-- the safe direction, and the one that removes the grep.  Those recognizers are
-- a list, not a theory: a mask that prints neither is reported as a pass, which
-- is why 'cprOutputTail' is returned whatever the verdict.
data CheckProjectResult = CheckProjectResult
  { cprSuccess        :: Bool          -- ^ Exit 0, in time, and no failure evidence in the
                                       --   output — an Agda error diagnostic, or the gate's
                                       --   own failure line.
  , cprTimedOut       :: Bool          -- ^ True iff the gate hit the @--check-timeout@ bound.
  , cprMaskedFailure  :: Bool          -- ^ True iff the gate exited 0 while its own output
                                       --   reported a failure.
  , cprElapsedMs      :: Int           -- ^ Wall-clock ms of the whole gate run.
  , cprTimeoutSeconds :: Maybe Int     -- ^ The bound in effect; 'Nothing' means unbounded.
  , cprGate           :: Gate          -- ^ Which gate ran, and why that one.
  , cprDiagnostics    :: [Diagnostic]  -- ^ Up to @maxDiagnostics@, most likely root cause first.
  , cprDiagnosticsTotal :: Int         -- ^ How many were found before the cap.
  , cprFirstError     :: Maybe Diagnostic -- ^ The first error-severity diagnostic, uncapped —
                                       --   the one to read first, lifted out so a client need
                                       --   not scan the list.
  , cprFailingModule  :: Maybe Text    -- ^ The module the gate stopped in, on a check that
                                       --   did not pass: the one carrying 'cprFirstError',
                                       --   or — when the gate failed without a located error,
                                       --   a timeout included — the last one Agda started
                                       --   checking.  Absent on a pass, where the last module
                                       --   started is simply the last module checked.
  , cprFailingFile    :: Maybe FilePath -- ^ That module's file.
  , cprModulesChecked :: Int           -- ^ Distinct modules Agda re-typechecked from source
                                       --   during the run (0 on a fully warm gate).  On a
                                       --   timeout this is how far it got.
  , cprOutputTail     :: Maybe Text    -- ^ The tail of the gate's output, bounded, whatever
                                       --   the verdict — absent only when the gate printed
                                       --   nothing.  A gate can fail for reasons Agda never
                                       --   printed (a missing tool, a shell error), and a
                                       --   mask this server cannot recognize is reported as a
                                       --   pass, so the evidence has to be there to be read.
  , cprVerdict        :: Verdict        -- ^ What was run and what @success@ means (#72).
  , cprCommand        :: CommandEcho    -- ^ The resolved command line and its cwd (#72).
  , cprProject        :: ProjectContext -- ^ The tree the gate ran in (#76).
  } deriving (Eq, Show)

instance ToJSON CheckProjectResult where
  toJSON r = object $
    [ "success"          .= cprSuccess r
    , "timedOut"         .= cprTimedOut r
    , "elapsedMs"        .= cprElapsedMs r
    , "gate"             .= cprGate r
    , "diagnostics"      .= cprDiagnostics r
    , "diagnosticsTotal" .= cprDiagnosticsTotal r
    , "modulesChecked"   .= cprModulesChecked r
    , "verdict"          .= cprVerdict r
    , "command"          .= cprCommand r
    , "project"          .= cprProject r
    ]
    -- Emitted only when true, as 'pcLibrariesFileMissing' is: an absent key is
    -- the ordinary case, and a present one is a finding.
    <> [ "maskedFailure" .= True | cprMaskedFailure r ]
    <> maybe [] (\n -> ["timeoutSeconds" .= n]) (cprTimeoutSeconds r)
    <> maybe [] (\d -> ["firstError"     .= d]) (cprFirstError r)
    <> maybe [] (\m -> ["failingModule"  .= m]) (cprFailingModule r)
    <> maybe [] (\f -> ["failingFile"    .= f]) (cprFailingFile r)
    <> maybe [] (\t -> ["outputTail"     .= t]) (cprOutputTail r)


-- ═══════════════════════════════════════════════════════════════════════════
-- § Corpus types (agda-strux JSONL schema v0.01)
--
-- These types track the canonical JSONL output; see docs/representation.md §3.
-- The primary key is @prettyQname@.
-- ═══════════════════════════════════════════════════════════════════════════
--

-- | CorpusEntry: a single definition from the agda-strux JSONL corpus.
--
-- Corresponds to one line of the "Full" format output.
-- We parse all required fields; optional fields (@body@, @hasBody@) are
-- best-effort.  The @typeAst@ is stored as opaque JSON — we do not
-- interpret its structure in M1-3 (structural matching is an M2 goal).
data CorpusEntry = CorpusEntry
  { ceFile          :: Text           -- ^ Source file path used by extractor.
  , ceModule        :: Text           -- ^ Raw Agda module name.
  , ceName          :: Text           -- ^ Unqualified name component.
  , ceQname         :: Text           -- ^ Raw qualified name (Agda internal).
  , cePrettyModule  :: Text           -- ^ Normalized module name.
  , cePrettyName    :: Text           -- ^ Normalized unqualified name.
  , cePrettyQname   :: Text           -- ^ @prettyModule.prettyName@ — primary key.
  , ceType          :: Text           -- ^ Pretty-printed type signature.
  , ceTypeAstVer    :: Text           -- ^ Version tag for typeAst encoding.
  , ceTypeAst       :: Value          -- ^ Structural AST (opaque JSON for now).
  , ceDefKind       :: Text           -- ^ function | data | record | constructor | postulate | primitive | other
  , ceDependencies  :: [Text]         -- ^ Heuristic tokens from type (type-level deps).
  , ceAstSize       :: Int            -- ^ Character length of the @type@ string.
  , ceBody          :: Maybe Text     -- ^ Pretty-printed clause bodies (may be absent).
  , ceHasBody       :: Bool           -- ^ True iff body is present/non-empty.
  } deriving (Eq, Show)
instance FromJSON CorpusEntry where
  parseJSON = withObject "CorpusEntry" $ \o ->
    CorpusEntry
      <$> o .:  "file"
      <*> o .:  "module"
      <*> o .:  "name"
      <*> o .:  "qname"
      <*> o .:  "prettyModule"
      <*> o .:  "prettyName"
      <*> o .:  "prettyQname"
      <*> o .:  "type"
      <*> o .:  "typeAstVersion"
      <*> o .:  "typeAst"
      <*> o .:  "defKind"
      <*> o .:  "dependencies"
      <*> o .:  "astSize"
      <*> o .:? "body"
      <*> (maybe False id <$> o .:? "hasBody")
instance ToJSON CorpusEntry where
  toJSON e = object $
    [ "file"           .= ceFile e
    , "module"         .= ceModule e
    , "name"           .= ceName e
    , "qname"          .= ceQname e
    , "prettyModule"   .= cePrettyModule e
    , "prettyName"     .= cePrettyName e
    , "prettyQname"    .= cePrettyQname e
    , "type"           .= ceType e
    , "typeAstVersion" .= ceTypeAstVer e
    , "typeAst"        .= ceTypeAst e
    , "defKind"        .= ceDefKind e
    , "dependencies"   .= ceDependencies e
    , "astSize"        .= ceAstSize e
    , "hasBody"        .= ceHasBody e
    ] <> maybe [] (\b -> ["body" .= b]) (ceBody e)


-- | CorpusIndex: in-memory corpus index.
--
-- The primary structure is a 'Map' from @prettyQname@ to 'CorpusEntry'.
-- For M1-3, name and type search are O(n) linear scans over 'ciEntries'.
-- M2-2 will add inverted indices and a graph adjacency list.
data CorpusIndex = CorpusIndex
  { ciEntries :: Map Text CorpusEntry
    -- ^ All entries, keyed by @prettyQname@.
  , ciSize    :: Int
    -- ^ Number of entries (cached for diagnostics).
  } deriving (Eq, Show)


-- ═══════════════════════════════════════════════════════════════════════════
-- § Tool parameters (inbound from agent) — search
-- ═══════════════════════════════════════════════════════════════════════════

-- | Parameters for the @search_by_name@ tool.
data SearchByNameParams = SearchByNameParams
  { sbnPattern :: Text       -- ^ Substring pattern to match against prettyQname / prettyName.
  , sbnLimit   :: Maybe Int  -- ^ Maximum results (default: 20).
  } deriving (Eq, Show)
instance FromJSON SearchByNameParams where
  parseJSON = withObject "SearchByNameParams" $ \o ->
    SearchByNameParams <$> o .: "pattern" <*> o .:? "limit"

-- | Parameters for the @search_by_type@ tool.
data SearchByTypeParams = SearchByTypeParams
  { sbtPattern :: Text       -- ^ Substring pattern to match against the type signature.
  , sbtLimit   :: Maybe Int  -- ^ Maximum results (default: 20).
  } deriving (Eq, Show)
instance FromJSON SearchByTypeParams where
  parseJSON = withObject "SearchByTypeParams" $ \o ->
    SearchByTypeParams <$> o .: "pattern" <*> o .:? "limit"

-- | Parameters for the @get_dependencies@ tool.
data GetDependenciesParams = GetDependenciesParams
  { gdpName   :: Text        -- ^ The prettyQname of the definition to look up.
  , gdpExpand :: Maybe Bool  -- ^ If true, also return entries for each dependency (1-hop).
  } deriving (Eq, Show)
instance FromJSON GetDependenciesParams where
  parseJSON = withObject "GetDependenciesParams" $ \o ->
    GetDependenciesParams <$> o .: "name" <*> o .:? "expand"


-- ═══════════════════════════════════════════════════════════════════════════
-- § Tool results (outbound to agent) — search
-- ═══════════════════════════════════════════════════════════════════════════

-- | A single search hit, returned by @search_by_name@ and @search_by_type@.
data SearchResult = SearchResult
  { srPrettyQname  :: Text    -- ^ Fully-qualified normalized name.
  , srType         :: Text    -- ^ Pretty-printed type signature.
  , srDefKind      :: Text    -- ^ function | data | record | ...
  , srModule       :: Text    -- ^ Module the definition lives in.
  , srHasBody      :: Bool    -- ^ Whether a body/proof is available.
  } deriving (Eq, Show)
instance ToJSON SearchResult where
  toJSON r = object
    [ "prettyQname" .= srPrettyQname r
    , "type"        .= srType r
    , "defKind"     .= srDefKind r
    , "module"      .= srModule r
    , "hasBody"     .= srHasBody r
    ]

-- | Result of @get_dependencies@.
data DependenciesResult = DependenciesResult
  { depName         :: Text           -- ^ The looked-up definition's prettyQname.
  , depType         :: Text           -- ^ Its type signature (for context).
  , depDependencies :: [Text]         -- ^ Direct dependency tokens from the type.
  , depNeighbors    :: [SearchResult] -- ^ Expanded entries (if @expand@ was true).
  } deriving (Eq, Show)
instance ToJSON DependenciesResult where
  toJSON r = object
    [ "name"         .= depName r
    , "type"         .= depType r
    , "dependencies" .= depDependencies r
    , "neighbors"    .= depNeighbors r
    ]

-- ═══════════════════════════════════════════════════════════════════════════
-- § Live queries — the interaction lane's tools (issue #75)
--
-- Parameters and results for type_of, normalize, resolve_name, definition_of,
-- and exports_of.  These tools answer from a persistent
-- @agda --interaction-json@ child (AgdaMCP.Interaction) and NEVER carry a
-- build verdict: interaction mode is tolerant by design, so the batch lane's
-- @verdict@ contract (issue #72) stays with check_file, check_project, and
-- fill_hole.  What these responses carry instead is the lane echo: which
-- root's child answered, what it did to answer (spawned? re-loaded? why?),
-- the exact IOTCM lines sent, and the timings.
-- ═══════════════════════════════════════════════════════════════════════════

-- | Parameters for the @type_of@ tool: infer the type of an expression in a
-- file's scope, no edit required.  @line@ optionally scopes the question to
-- the goal whose range contains that line, which is what makes local
-- variables visible to the query.
data TypeOfParams = TypeOfParams
  { topFilePath :: FilePath
  , topExpr     :: Text
  , topLine     :: Maybe Int
  , topReload   :: Bool       -- ^ Force a fresh load (a changed dependency).
  } deriving (Eq, Show)

instance FromJSON TypeOfParams where
  parseJSON = withObject "TypeOfParams" $ \o ->
    TypeOfParams <$> o .: "filePath" <*> o .: "expr" <*> o .:? "line"
                 <*> (o .:? "reload" .!= False)

-- | Parameters for the @normalize@ tool: evaluate an expression to normal
-- form in a file's scope.  @line@ as in 'TypeOfParams'.
data NormalizeParams = NormalizeParams
  { nomFilePath :: FilePath
  , nomExpr     :: Text
  , nomLine     :: Maybe Int
  , nomReload   :: Bool
  } deriving (Eq, Show)

instance FromJSON NormalizeParams where
  parseJSON = withObject "NormalizeParams" $ \o ->
    NormalizeParams <$> o .: "filePath" <*> o .: "expr" <*> o .:? "line"
                    <*> (o .:? "reload" .!= False)

-- | Parameters for the @resolve_name@ tool: what does this name resolve to
-- here, and why?  @line@ as in 'TypeOfParams'; for scope questions it matters
-- more, because a goal-scoped query sees local variables and, on a hole-free
-- file, more of the opened names than the completed toplevel scope does (see
-- docs/agda-mcp-interaction-lane.md § 2.6).
data ResolveNameParams = ResolveNameParams
  { rnpFilePath :: FilePath
  , rnpName     :: Text
  , rnpLine     :: Maybe Int
  , rnpReload   :: Bool
  } deriving (Eq, Show)

instance FromJSON ResolveNameParams where
  parseJSON = withObject "ResolveNameParams" $ \o ->
    ResolveNameParams <$> o .: "filePath" <*> o .: "name" <*> o .:? "line"
                      <*> (o .:? "reload" .!= False)

-- | Parameters for the @definition_of@ tool: where is this name defined?
data DefinitionOfParams = DefinitionOfParams
  { dopFilePath :: FilePath
  , dopName     :: Text
  , dopLine     :: Maybe Int
  , dopReload   :: Bool
  } deriving (Eq, Show)

instance FromJSON DefinitionOfParams where
  parseJSON = withObject "DefinitionOfParams" $ \o ->
    DefinitionOfParams <$> o .: "filePath" <*> o .: "name" <*> o .:? "line"
                       <*> (o .:? "reload" .!= False)

-- | Parameters for the @exports_of@ tool: the public surface of a module, as
-- seen from a file whose scope can name it.  The empty string names the
-- file's own top-level module.
data ExportsOfParams = ExportsOfParams
  { eopFilePath :: FilePath
  , eopModule   :: Text
  , eopReload   :: Bool
  } deriving (Eq, Show)

instance FromJSON ExportsOfParams where
  parseJSON = withObject "ExportsOfParams" $ \o ->
    ExportsOfParams <$> o .: "filePath" <*> o .: "module"
                    <*> (o .:? "reload" .!= False)

-- | LaneEcho: what the interaction lane did to answer this call (issue #75's
-- analogue of the batch lane's verdict/command echo, issue #72).
--
-- @lchLoad@ is one of @reused@, @first@, @switch@, @changed@, @retry@ — the
-- evidence that triggered (or spared) a re-load; @lchLoadElapsedMs@ is absent
-- exactly when no load ran.  @lchIotcm@ is the exact wire lines this call
-- sent, sentinel included, so a client can replay the call by hand.
data LaneEcho = LaneEcho
  { lchRoot          :: FilePath
  , lchPid           :: Maybe Int
  , lchSpawned       :: Bool
  , lchLoad          :: Text
  , lchLoadElapsedMs :: Maybe Int
  , lchAgdaVersion   :: Maybe Text
  , lchIotcm         :: [Text]
  } deriving (Eq, Show)

instance ToJSON LaneEcho where
  toJSON l = object $
    [ "root"    .= lchRoot l
    , "spawned" .= lchSpawned l
    , "load"    .= lchLoad l
    , "iotcm"   .= lchIotcm l
    ]
    <> maybe [] (\x -> ["pid"           .= x]) (lchPid l)
    <> maybe [] (\x -> ["loadElapsedMs" .= x]) (lchLoadElapsedMs l)
    <> maybe [] (\x -> ["agdaVersion"   .= x]) (lchAgdaVersion l)

-- | LiveMeta: the echo block shared by every live-query response —
-- timing, cache evidence, the lane, and the same @command@ / @project@
-- pair the batch tools report (issues #72, #76).  Serialized flattened into
-- the response object by 'liveMetaPairs'.
data LiveMeta = LiveMeta
  { lmElapsedMs         :: Int
  , lmCheckedFromSource :: Bool
  , lmLane              :: LaneEcho
  , lmCommand           :: CommandEcho
  , lmProject           :: ProjectContext
  } deriving (Eq, Show)

liveMetaPairs :: LiveMeta -> [Pair]
liveMetaPairs m =
  [ "elapsedMs"         .= lmElapsedMs m
  , "checkedFromSource" .= lmCheckedFromSource m
  , "lane"              .= lmLane m
  , "command"           .= lmCommand m
  , "project"           .= lmProject m
  ]

-- | LiveError: an Agda-level negative answer, in band.  A query tool's
-- product includes "it does not typecheck" and "that module is not in scope
-- here", so these arrive inside a success-shaped response with the stage
-- (@load@, @expression@, @name@, or @module@), Agda's own bracketed code when
-- the message carried one, and the message.  Lane-level process failures are
-- 'InteractionFailure' instead.
data LiveError = LiveError
  { lveStage   :: Text
  , lveCode    :: Maybe Text
  , lveMessage :: Text
  } deriving (Eq, Show)

instance ToJSON LiveError where
  toJSON e = object $
    [ "stage"   .= lveStage e
    , "message" .= lveMessage e
    ]
    <> maybe [] (\c -> ["code" .= c]) (lveCode e)

-- | DefSite: a definition's location — file plus a 1-based (line, col) range
-- in that file's own coordinates — optionally with the qualified name it
-- locates.
data DefSite = DefSite
  { dsQualified :: Maybe Text
  , dsFile      :: FilePath
  , dsLine      :: Int
  , dsCol       :: Int
  , dsEndLine   :: Int
  , dsEndCol    :: Int
  } deriving (Eq, Show)

instance ToJSON DefSite where
  toJSON d = object $
    [ "file"    .= dsFile d
    , "line"    .= dsLine d
    , "col"     .= dsCol d
    , "endLine" .= dsEndLine d
    , "endCol"  .= dsEndCol d
    ]
    <> maybe [] (\q -> ["qualified" .= q]) (dsQualified d)

-- | ProvenanceEcho: one step of a name's provenance chain — @its definition@,
-- @the opening of M@, @the application of M@ — with its location when Agda's
-- prose carried one (steps through other modules' scope information may not).
data ProvenanceEcho = ProvenanceEcho
  { peStep :: Text
  , peSite :: Maybe DefSite
  } deriving (Eq, Show)

instance ToJSON ProvenanceEcho where
  toJSON p = object $
    ["step" .= peStep p]
    <> maybe [] (\st -> ["site" .= st]) (peSite p)

-- | NameCandidate: one resolution of a name — one @*@ bullet of Agda's
-- WhyInScope answer, or one entry recovered from an AmbiguousName error.
data NameCandidate = NameCandidate
  { ncDescription :: Text             -- ^ E.g. @a defined name M.N.amb@.
  , ncQualified   :: Maybe Text       -- ^ The fully qualified name.
  , ncProvenance  :: [ProvenanceEcho] -- ^ Outermost step first.
  , ncDefinition  :: Maybe DefSite    -- ^ The defining site, when located.
  } deriving (Eq, Show)

instance ToJSON NameCandidate where
  toJSON c = object $
    [ "description" .= ncDescription c
    , "provenance"  .= ncProvenance c
    ]
    <> maybe [] (\q -> ["qualified"  .= q]) (ncQualified c)
    <> maybe [] (\d -> ["definition" .= d]) (ncDefinition c)

-- | ExportEntry: one name of a module's public surface, with its type as
-- Agda printed it.
data ExportEntry = ExportEntry
  { exName :: Text
  , exTerm :: Text
  } deriving (Eq, Show)

instance ToJSON ExportEntry where
  toJSON e = object ["name" .= exName e, "type" .= exTerm e]

-- | Result of @type_of@.  Exactly one of @type@ / @error@ is present.
data TypeOfResult = TypeOfResult
  { torExpr  :: Text
  , torScope :: Text              -- ^ @toplevel@, or @goal N@ with its line.
  , torType  :: Maybe Text
  , torError :: Maybe LiveError
  , torMeta  :: LiveMeta
  } deriving (Eq, Show)

instance ToJSON TypeOfResult where
  toJSON r = object $
    [ "expr"  .= torExpr r
    , "scope" .= torScope r
    ]
    <> maybe [] (\t -> ["type"  .= t]) (torType r)
    <> maybe [] (\e -> ["error" .= e]) (torError r)
    <> liveMetaPairs (torMeta r)

-- | Result of @normalize@.  Exactly one of @normalForm@ / @error@ is present.
data NormalizeResult = NormalizeResult
  { nrExpr       :: Text
  , nrScope      :: Text
  , nrNormalForm :: Maybe Text
  , nrError      :: Maybe LiveError
  , nrMeta       :: LiveMeta
  } deriving (Eq, Show)

instance ToJSON NormalizeResult where
  toJSON r = object $
    [ "expr"  .= nrExpr r
    , "scope" .= nrScope r
    ]
    <> maybe [] (\t -> ["normalForm" .= t]) (nrNormalForm r)
    <> maybe [] (\e -> ["error"      .= e]) (nrError r)
    <> liveMetaPairs (nrMeta r)

-- | Result of @resolve_name@.
--
-- @inScope@ is WhyInScope's own verdict on the name as written.  When it is
-- false the candidates may still be non-empty: the § 2.6 recovery ran, and
-- @recovered@ names the route — @ambiguous-name-error@ (the name is in scope
-- ambiguously, or invisible to the completed toplevel scope) or
-- @did-you-mean@ (Agda's suggestions, each then resolved for its chain).
data ResolveNameResult = ResolveNameResult
  { rnrName       :: Text
  , rnrScope      :: Text
  , rnrInScope    :: Bool
  , rnrCandidates :: [NameCandidate]
  , rnrRecovered  :: Maybe Text
  , rnrError      :: Maybe LiveError
  , rnrMeta       :: LiveMeta
  } deriving (Eq, Show)

instance ToJSON ResolveNameResult where
  toJSON r = object $
    [ "name"       .= rnrName r
    , "scope"      .= rnrScope r
    , "inScope"    .= rnrInScope r
    , "candidates" .= rnrCandidates r
    ]
    <> maybe [] (\x -> ["recovered" .= x]) (rnrRecovered r)
    <> maybe [] (\e -> ["error"     .= e]) (rnrError r)
    <> liveMetaPairs (rnrMeta r)

-- | Result of @definition_of@: the located definitions of every candidate
-- the name resolves to, plus the descriptions of candidates whose site the
-- prose did not carry (so a partial answer is never mistaken for a total
-- one).
data DefinitionOfResult = DefinitionOfResult
  { dorName        :: Text
  , dorScope       :: Text
  , dorDefinitions :: [DefSite]
  , dorUnlocated   :: [Text]
  , dorRecovered   :: Maybe Text
  , dorError       :: Maybe LiveError
  , dorMeta        :: LiveMeta
  } deriving (Eq, Show)

instance ToJSON DefinitionOfResult where
  toJSON r = object $
    [ "name"        .= dorName r
    , "scope"       .= dorScope r
    , "definitions" .= dorDefinitions r
    , "unlocated"   .= dorUnlocated r
    ]
    <> maybe [] (\x -> ["recovered" .= x]) (dorRecovered r)
    <> maybe [] (\e -> ["error"     .= e]) (dorError r)
    <> liveMetaPairs (dorMeta r)

-- | Result of @exports_of@.  Exactly one of @exports@ / @error@ is present.
data ExportsOfResult = ExportsOfResult
  { exrModule  :: Text
  , exrExports :: Maybe [ExportEntry]
  , exrError   :: Maybe LiveError
  , exrMeta    :: LiveMeta
  } deriving (Eq, Show)

instance ToJSON ExportsOfResult where
  toJSON r = object $
    [ "module" .= exrModule r ]
    <> maybe [] (\es -> ["exports" .= es]) (exrExports r)
    <> maybe [] (\e  -> ["error"   .= e]) (exrError r)
    <> liveMetaPairs (exrMeta r)

-- | InteractionFailure: the interaction lane's process failed this call — it
-- could not be spawned, it hit the timeout and was killed by the group
-- ladder, or it crashed mid-command.  Serialized as the error text of an
-- @isError@ tool result (never a JSON-RPC -32603, the issue-#101 rule), with
-- everything a client needs to see what was attempted: the root, the wire
-- lines sent, the child's last words, and the same command/project echo the
-- successful path carries.
data InteractionFailure = InteractionFailure
  { xfEvent      :: Text            -- ^ @timeout@ | @crash@ | @spawn-failure@.
  , xfMessage    :: Text
  , xfStderrTail :: [Text]          -- ^ Newest first, bounded.
  , xfElapsedMs  :: Int
  , xfRoot       :: FilePath
  , xfIotcm      :: [Text]
  , xfCommand    :: CommandEcho
  , xfProject    :: ProjectContext
  } deriving (Eq, Show)

instance ToJSON InteractionFailure where
  toJSON f = object
    [ "error"      .= xfMessage f
    , "event"      .= xfEvent f
    , "timedOut"   .= (xfEvent f == "timeout")
    , "stderrTail" .= xfStderrTail f
    , "elapsedMs"  .= xfElapsedMs f
    , "root"       .= xfRoot f
    , "iotcm"      .= xfIotcm f
    , "command"    .= xfCommand f
    , "project"    .= xfProject f
    ]
