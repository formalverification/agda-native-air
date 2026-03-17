-- | File: agda-native-air/agda-mcp/src/AgdaMCP/Types.hs
--
-- Shared types for the agda-mcp MCP server.
--
-- This module defines the JSON schema contract for tool requests and responses.
-- Every type has a hand-written Aeson instance to ensure the wire format is
-- stable across code changes (no Generic-derived surprises).
--
-- Schema version: agda-mcp/v0
--
-- These types correspond 1-to-1 with the policy contract defined in
-- agda-dojang/python/tools/policy_contract.py, ensuring interoperability
-- between the Haskell MCP server and the Python evaluator/policy backends.

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
  ) where

import Data.Aeson
  ( FromJSON (..), ToJSON (..), Value (..), (.:), (.:?), (.=)
  , object, withObject, withText
  )
import Data.Text (Text)


-- ---------------------------------------------------------------------------
-- Hole location
-- ---------------------------------------------------------------------------

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


-- ---------------------------------------------------------------------------
-- Context entry (matches agda-dojang's AGDADOJANG_CTX line protocol)
-- ---------------------------------------------------------------------------

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


-- ---------------------------------------------------------------------------
-- Tool parameters (inbound from agent)
-- ---------------------------------------------------------------------------

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


-- ---------------------------------------------------------------------------
-- Tool results (outbound to agent)
-- ---------------------------------------------------------------------------

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
  , frNewHoles  :: Maybe Int      -- ^ Number of new holes introduced (if any).
  } deriving (Eq, Show)

instance ToJSON FillResult where
  toJSON r = object $
    [ "status"    .= frStatus r
    , "candidate" .= frCandidate r
    ] <> maybe [] (\m -> ["message"  .= m]) (frMessage r)
      <> maybe [] (\n -> ["newHoles" .= n]) (frNewHoles r)

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
  , drHoles       :: [GoalInfo]     -- ^ Open holes with their goal types.
  } deriving (Eq, Show)

instance ToJSON DiagnosticsResult where
  toJSON r = object
    [ "filePath" .= drFilePath r
    , "errors"   .= drErrors r
    , "warnings" .= drWarnings r
    , "holes"    .= drHoles r
    ]
