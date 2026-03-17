-- | File: agda-native-air/agda-mcp/src/AgdaMCP/Agda.hs
--
-- Agda subprocess interaction layer.
--
-- This module provides pure and IO functions for:
--   1. Finding {!!} holes in Agda source text.
--   2. Injecting the reportGoalCtx macro to extract (goal, context).
--   3. Parsing AGDADOJANG marker output from Agda's stderr.
--   4. Substituting candidate terms into holes and running Agda to typecheck.
--
-- It is a Haskell port of the essential logic in:
--   agda-dojang/python/tools/agent_bridge.py
--   agda-dojang/python/tools/report_parser.py
--
-- The functions here call the @agda@ binary as a subprocess.  The long-term
-- plan is to replace this with Agda-as-a-library calls once the Haskell
-- interface to AgdaDojang matures.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData        #-}

module AgdaMCP.Agda
  ( -- * Configuration
    AgdaConfig (..)
  , defaultConfig
    -- * Hole operations (pure)
  , HoleSpan (..)
  , findHoles
  , findNthHole
  , injectReportExpr
  , substituteHole
    -- * Marker parsing (pure)
  , parseGoalContext
    -- * Agda subprocess (IO)
  , runAgda
  , AgdaResult (..)
  ) where

import Control.Exception (catch, SomeException)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Exit (ExitCode (..))
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
  } deriving (Eq, Show)

-- | Sensible defaults; the caller should override @agdaFlags@ for their project.
defaultConfig :: AgdaConfig
defaultConfig = AgdaConfig
  { agdaBin     = "agda"
  , agdaFlags   = []
  , agdaTimeout = Just 30
  , reportExpr  = "reportGoalCtx"
  }


-- ---------------------------------------------------------------------------
-- Hole finding (pure)
-- ---------------------------------------------------------------------------

-- | A located hole token in source text.
data HoleSpan = HoleSpan
  { hsStart :: Int    -- ^ 0-based byte offset of '{' in "{!!}".
  , hsEnd   :: Int    -- ^ 0-based byte offset one past '}'.
  , hsLine  :: Int    -- ^ 1-based line number.
  , hsCol   :: Int    -- ^ 1-based column number.
  } deriving (Eq, Show)

holeToken :: Text
holeToken = "{!!}"

-- | Find all @{!!}@ holes in source text, in order.
findHoles :: Text -> [HoleSpan]
findHoles src = go 0 1 1 src
  where
    go !off !ln !col txt
      | T.null txt = []
      | Just rest <- T.stripPrefix holeToken txt =
          let span' = HoleSpan off (off + 4) ln col
          in  span' : go (off + 4) ln (col + 4) rest
      | T.head txt == '\n' =
          go (off + 1) (ln + 1) 1 (T.tail txt)
      | otherwise =
          go (off + 1) ln (col + 1) (T.tail txt)

-- | Find the n-th hole (0-indexed) in source text.
findNthHole :: Int -> Text -> Maybe HoleSpan
findNthHole n src =
  let holes = findHoles src
  in  if n < length holes then Just (holes !! n) else Nothing

-- | Replace the n-th hole with the reporting expression (e.g. "reportGoalCtx ?").
injectReportExpr :: AgdaConfig -> Int -> Text -> Maybe Text
injectReportExpr cfg n src = do
  hole <- findNthHole n src
  let (before, rest) = T.splitAt (hsStart hole) src
      after          = T.drop 4 rest  -- drop "{!!}"
      replacement    = reportExpr cfg <> " ?"
  pure $ before <> replacement <> after

-- | Replace the n-th hole with a candidate term.
substituteHole :: Int -> Text -> Text -> Maybe Text
substituteHole n candidate src = do
  hole <- findNthHole n src
  let (before, rest) = T.splitAt (hsStart hole) src
      after          = T.drop 4 rest  -- drop "{!!}"
  pure $ before <> candidate <> after


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
  -- Extract block between REQ_BEGIN and REQ_END (last occurrence).
  let afterBegin = snd <$> lastSplitOn reqBegin output
  block <- afterBegin >>= fstSplitOn reqEnd
  let ls = T.lines block
      goal = mconcat
           . map (T.strip . T.drop (T.length goalPrefix))
           . filter (\l -> T.isPrefixOf goalPrefix (T.strip l))
           $ ls
      ctx  = mapMaybe parseCtxLine ls
  if T.null goal then Nothing else Just (normaliseWs goal, ctx)

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
-- Merges stdout and stderr into @arStderr@ for convenience, since Agda
-- emits most diagnostics on stderr.
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
