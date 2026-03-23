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
    -- * Tool results (outbound)
  , GoalInfo (..)
  , FillResult (..)
  , FillStatus (..)
  , Diagnostic (..)
  , DiagSeverity (..)
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


-- ═══════════════════════════════════════════════════════════════════════════
-- Hole location
-- ═══════════════════════════════════════════════════════════════════════════

-- | Identifies a hole in a source file.
data HoleLocation = HoleLocation
  { holePath  :: FilePath   -- ^ Absolute or repo-relative path to the Agda file.
  , holeIndex :: Int        -- ^ 0-based index of the {!!} hole (in source order).
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
newtype CheckFileParams = CheckFileParams
  { cfFilePath :: FilePath
  } deriving (Eq, Show)

instance FromJSON CheckFileParams where
  parseJSON = withObject "CheckFileParams" $ \o ->
    CheckFileParams <$> o .: "filePath"

-- | Parameters for the @get_diagnostics@ tool.
newtype GetDiagnosticsParams = GetDiagnosticsParams
  { gdFilePath :: FilePath
  } deriving (Eq, Show)

instance FromJSON GetDiagnosticsParams where
  parseJSON = withObject "GetDiagnosticsParams" $ \o ->
    GetDiagnosticsParams <$> o .: "filePath"


-- ═══════════════════════════════════════════════════════════════════════════
-- Tool results (outbound to agent)
-- ═══════════════════════════════════════════════════════════════════════════

-- | Result of @get_goal@: the hole's goal type and local context.
data GoalInfo = GoalInfo
  { giGoal    :: Text         -- ^ Pretty-printed goal type.
  , giContext :: [CtxEntry]   -- ^ Local context (bound variables with types).
  , giModule  :: Maybe Text   -- ^ Module name (if determinable).
  } deriving (Eq, Show)

instance ToJSON GoalInfo where
  toJSON g = object $
    [ "goal"    .= giGoal g
    , "context" .= giContext g
    ] <> maybe [] (\m -> ["module" .= m]) (giModule g)

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
  } deriving (Eq, Show)

instance ToJSON FillResult where
  toJSON r = object $
    [ "status"    .= frStatus r
    , "candidate" .= frCandidate r
    ] <> maybe [] (\m -> ["message"  .= m]) (frMessage r)
      <> maybe [] (\n -> ["remainingHoles" .= n]) (frRemainingHoles r)

-- | Severity level for a diagnostic.
data DiagSeverity = DiagError | DiagWarning | DiagInfo
  deriving (Eq, Show)

instance ToJSON DiagSeverity where
  toJSON DiagError   = String "error"
  toJSON DiagWarning = String "warning"
  toJSON DiagInfo    = String "info"

-- | A single diagnostic (error, warning, or info) from Agda.
data Diagnostic = Diagnostic
  { diagSeverity :: DiagSeverity
  , diagMessage  :: Text
  , diagLine     :: Maybe Int     -- ^ 1-based line number (if available).
  , diagCol      :: Maybe Int     -- ^ 1-based column (if available).
  } deriving (Eq, Show)

instance ToJSON Diagnostic where
  toJSON d = object $
    [ "severity" .= diagSeverity d
    , "message"  .= diagMessage d
    ] <> maybe [] (\l -> ["line" .= l]) (diagLine d)
      <> maybe [] (\c -> ["col"  .= c]) (diagCol d)

-- | Result of @check_file@.
data FileCheckResult = FileCheckResult
  { fcrSuccess     :: Bool          -- ^ True iff Agda exited 0 with no errors.
  , fcrDiagnostics :: [Diagnostic]
  , fcrHolesCount  :: Int           -- ^ Number of remaining {!!} holes.
  } deriving (Eq, Show)

instance ToJSON FileCheckResult where
  toJSON r = object
    [ "success"     .= fcrSuccess r
    , "diagnostics" .= fcrDiagnostics r
    , "holesCount"  .= fcrHolesCount r
    ]

-- | Result of @get_diagnostics@ (cached state from last check).
data DiagnosticsResult = DiagnosticsResult
  { drFilePath    :: FilePath
  , drErrors      :: Int
  , drWarnings    :: Int
  , drHoles       :: [GoalInfo]  -- ^ Open holes (v0: giGoal is "?")
  } deriving (Eq, Show)          --   (per-hole goal extraction is a future enhancement).

instance ToJSON DiagnosticsResult where
  toJSON r = object
    [ "filePath" .= drFilePath r
    , "errors"   .= drErrors r
    , "warnings" .= drWarnings r
    , "holes"    .= drHoles r
    ]

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
