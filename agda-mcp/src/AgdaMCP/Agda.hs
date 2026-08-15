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

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE StrictData        #-}

module AgdaMCP.Agda
  ( -- * Configuration
    AgdaConfig (..)
  , defaultConfig
    -- * Debug output
  , debugLog
    -- * Marker parsing (pure)
  , parseGoalContext
    -- * Agda subprocess (IO)
  , runAgda
  , AgdaResult (..)
  ) where

import Control.Exception (catch, SomeException)
import Data.Text.IO as TIO
import Data.Text (Text)
import qualified Data.Text as T
import System.Exit (ExitCode (..))
import System.IO (stderr)
import System.Process (readProcessWithExitCode)

import AgdaMCP.Types (CtxEntry (..))


-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- | Configuration for invoking the Agda binary.
data AgdaConfig = AgdaConfig
  { agdaBin       :: FilePath     -- ^ Path to the agda binary.
  , agdaFlags     :: [String]     -- ^ Extra flags (e.g. @["-i", "agda", "--library-file=..."]@).
  , agdaTimeout   :: Maybe Int    -- ^ Timeout in seconds (Nothing = no timeout).
  , reportExpr    :: Text         -- ^ Reporting expression to inject (default: "reportGoalCtx").
  , agdaVerbose   :: Bool         -- ^ Emit debug output to stderr.
  } deriving (Eq, Show)

-- | Sensible defaults; the caller should override @agdaFlags@ for their project.
defaultConfig :: AgdaConfig
defaultConfig = AgdaConfig
  { agdaBin     = "agda"
  , agdaFlags   = []
  , agdaTimeout = Just 30
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
  { arExitCode :: Int       -- ^ Process exit code (0 = success).
  , arStdout   :: Text      -- ^ Captured stdout.
  , arStderr   :: Text      -- ^ Captured stderr.
  } deriving (Eq, Show)

-- | Run the Agda binary on the given file path.
--
-- Captures stdout and stderr separately, since Agda emits most diagnostics
-- on stderr.
runAgda :: AgdaConfig -> FilePath -> IO AgdaResult
runAgda cfg path = do
  let args = agdaFlags cfg <> [path]
  result <- safeReadProcess (agdaBin cfg) args ""
  case result of
    Left err -> pure AgdaResult
      { arExitCode = -1
      , arStdout   = ""
      , arStderr   = "agda-mcp: failed to run agda: " <> T.pack (show err)
      }
    Right (ec, out, err) ->
      -- TODO: enforce agdaTimeout via System.Timeout.timeout
      -- SEE: https://github.com/formalverification/agda-native-air/pull/38#discussion_r2969684706
      let code = case ec of
            ExitSuccess   -> 0
            ExitFailure n -> n
      in pure AgdaResult
        { arExitCode = code
        , arStdout   = T.pack out
        , arStderr   = T.pack err
        }

-- | readProcessWithExitCode wrapped in exception handling.
safeReadProcess
  :: FilePath -> [String] -> String
  -> IO (Either SomeException (ExitCode, String, String))
safeReadProcess cmd args stdin' =
  (Right <$> readProcessWithExitCode cmd args stdin')
    `catch` \e -> pure (Left (e :: SomeException))
