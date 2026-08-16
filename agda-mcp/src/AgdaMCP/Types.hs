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
--   type, and meaning, and the one new /failure/ shape ('FailProject') is a new
--   kind rather than a changed one — so the schema version is unchanged.
--
--   These types correspond 1-to-1 with the policy contract defined in
--   agda-dojang/python/tools/policy_contract.py, ensuring interoperability
--   between the Haskell MCP server and the Python evaluator/policy backends.
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
    -- * Response echo (issues #72, #76)
  , CommandEcho (..)
  , commandLine
  , Verdict (..)
  , RootSource (..)
  , LibraryEntry (..)
  , ProjectContext (..)
  , ProjectMismatch (..)
  , mismatchMessage
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
  ) where

import Data.Aeson
  ( FromJSON (..), ToJSON (..), Value (..), (.:), (.:?), (.=)
  , object, withObject, withText
  )
import Data.Map.Strict (Map)
import Data.Text (Text)
import qualified Data.Text as T


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

-- | Parameters for the @get_goal@ tool.
data GetGoalParams = GetGoalParams
  { ggFilePath  :: FilePath
  , ggHoleIndex :: Int
  } deriving (Eq, Show)

instance FromJSON GetGoalParams where
  parseJSON = withObject "GetGoalParams" $ \o ->
    GetGoalParams <$> o .: "filePath" <*> o .: "holeIndex"

-- | Parameters for the @fill_hole@ tool.
data FillHoleParams = FillHoleParams
  { fhFilePath  :: FilePath
  , fhHoleIndex :: Int
  , fhCandidate :: Text       -- ^ The candidate proof term to try.
  } deriving (Eq, Show)

instance FromJSON FillHoleParams where
  parseJSON = withObject "FillHoleParams" $ \o ->
    FillHoleParams <$> o .: "filePath" <*> o .: "holeIndex" <*> o .: "candidate"

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
  , vExitCode     :: Int    -- ^ Agda's exit code (@-1@: the binary could not be run).
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
  , pcLibrariesFile :: Maybe FilePath     -- ^ The libraries registry consulted, if any.
  , pcRegistered    :: [LibraryEntry]     -- ^ What that registry declares.
  , pcSelected      :: [Text]             -- ^ Library names selected by the server's @-l@ flags.
  , pcIncludePaths  :: [FilePath]         -- ^ Include directories from the server's @-i@ flags.
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
-- rather than having to parse a sentence.  'FailMessage' keeps every ordinary
-- failure exactly as it was: prose in, prose out.
--
-- All four proof-state tools fail through this type, so a client has one
-- failure shape to handle rather than one per tool.
data ToolFailure
  = FailMessage Text            -- ^ An ordinary failure; rendered as plain text.
  | FailTimeout TimeoutFailure  -- ^ The call hit @--timeout@; rendered as JSON.
  | FailProject ProjectMismatch -- ^ The file belongs to a different checkout; rendered as JSON.
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
  , giModule            :: Maybe Text   -- ^ Module name (if determinable).
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

-- | One open hole in a file, as listed by @get_diagnostics@.  The index is
-- the 0-based @holeIndex@ that @get_goal@ / @fill_hole@ accept; line and
-- column are 1-based positions in the file as written, so for literate
-- sources they are literate-file coordinates (issue #73).
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
data FillResult = FillResult
  { frStatus    :: FillStatus
  , frCandidate :: Text           -- ^ The candidate that was tried.
  , frMessage   :: Maybe Text     -- ^ Agda error message on failure; Nothing on success.
  , frRemainingHoles :: Maybe Int -- ^ Number of remaining holes after filling (if determinable).
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
data FileCheckResult = FileCheckResult
  { fcrSuccess     :: Bool          -- ^ True iff Agda exited 0, in time.
  , fcrDiagnostics :: [Diagnostic]  -- ^ Up to @maxDiagnostics@ of them, most likely root cause first.
  , fcrDiagnosticsTotal :: Int      -- ^ How many were found before the cap; equals
                                    --   @length fcrDiagnostics@ when nothing was dropped.
  , fcrHolesCount  :: Int           -- ^ Number of open holes (any hole syntax, code regions only).
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
