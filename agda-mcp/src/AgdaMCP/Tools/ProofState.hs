-- | File: agda-native-air/agda-mcp/src/AgdaMCP/Tools/ProofState.hs
--
-- Core proof-state tools for the agda-mcp MCP server (M1-2).
--
-- Each function implements one MCP tool.  They share an 'AgdaConfig' and
-- call the Agda binary via 'AgdaMCP.Agda'.  The agent invokes these
-- through JSON-RPC tool calls; the MCP server layer (AgdaMCP.Server)
-- dispatches to the appropriate handler.
--
-- Tools:
--   * get_goal        — inspect goal type + context at a hole
--   * fill_hole       — try a candidate term and report typecheck result
--   * check_file      — load/reload a file and return all diagnostics
--   * get_diagnostics — lightweight summary (hole count, error count)

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.ProofState
  ( handleGetGoal
  , handleFillHole
  , handleCheckFile
  , handleGetDiagnostics
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath ((</>), takeFileName)

import AgdaMCP.Agda
  ( AgdaConfig, AgdaResult (..)
  , findHoles, injectReportExpr, substituteHole
  , parseGoalContext, runAgda
  )
import AgdaMCP.Types


-- ---------------------------------------------------------------------------
-- get_goal
-- ---------------------------------------------------------------------------

-- | Inspect the goal type and local context at hole @n@ in the given file.
--
-- Workflow:
--   1. Read the source file.
--   2. Replace hole @n@ with @reportGoalCtx ?@.
--   3. Write a temporary copy and run Agda on it.
--   4. Parse the AGDADOJANG_REQ_BEGIN/END block from stderr.
--   5. Return structured (goal, context).
handleGetGoal :: AgdaConfig -> GetGoalParams -> IO (Either Text GoalInfo)
handleGetGoal cfg params = do
  src <- TIO.readFile (ggFilePath params)
  case injectReportExpr cfg (ggHoleIndex params) src of
    Nothing -> pure . Left $
      "Hole index " <> T.pack (show (ggHoleIndex params))
      <> " not found in " <> T.pack (ggFilePath params)
    Just patched -> do
      tmpDir <- makeTmpDir "agda-mcp-goal"
      let tmpFile = tmpDir </> takeFileName (ggFilePath params)
      TIO.writeFile tmpFile patched
      result <- runAgda cfg tmpFile
      -- reportGoalCtx always causes a typeError (non-zero exit), so we
      -- ignore the exit code and just parse stderr for markers.
      case parseGoalContext (arStderr result) of
        Nothing -> pure . Left $
          "Could not parse goal/context markers from Agda output.\n"
          <> "stderr:\n" <> T.take 2000 (arStderr result)
        Just (goal, ctx) ->
          pure . Right $ GoalInfo
            { giGoal    = goal
            , giContext = ctx
            , giModule  = Just . T.pack . takeFileName $ ggFilePath params
            }


-- ---------------------------------------------------------------------------
-- fill_hole
-- ---------------------------------------------------------------------------

-- | Try substituting @candidate@ into hole @n@ and typecheck.
--
-- Workflow:
--   1. Read source, substitute candidate into hole n.
--   2. Write temp copy, run Agda.
--   3. If exit 0 → success; otherwise → type error.
handleFillHole :: AgdaConfig -> FillHoleParams -> IO (Either Text FillResult)
handleFillHole cfg params = do
  src <- TIO.readFile (fhFilePath params)
  case substituteHole (fhHoleIndex params) (fhCandidate params) src of
    Nothing -> pure . Left $
      "Hole index " <> T.pack (show (fhHoleIndex params))
      <> " not found in " <> T.pack (fhFilePath params)
    Just patched -> do
      tmpDir <- makeTmpDir "agda-mcp-fill"
      let tmpFile = tmpDir </> takeFileName (fhFilePath params)
      TIO.writeFile tmpFile patched
      result <- runAgda cfg tmpFile
      let status = if arExitCode result == 0 then FillOk else FillTypeError
          msg    = if arExitCode result == 0
                     then Nothing
                     else Just (T.take 2000 $ arStderr result)
          -- Count remaining holes in the patched source after substitution.
          newHoleCount = length (findHoles patched)
      pure . Right $ FillResult
        { frStatus    = status
        , frCandidate = fhCandidate params
        , frMessage   = msg
        , frNewHoles  = Just newHoleCount
        }


-- ---------------------------------------------------------------------------
-- check_file
-- ---------------------------------------------------------------------------

-- | Load/reload an Agda file and return all diagnostics.
handleCheckFile :: AgdaConfig -> CheckFileParams -> IO (Either Text FileCheckResult)
handleCheckFile cfg params = do
  src <- TIO.readFile (cfFilePath params)
  result <- runAgda cfg (cfFilePath params)
  let diags   = parseDiagnostics (arStderr result)
      nHoles  = length (findHoles src)
      success = arExitCode result == 0
  pure . Right $ FileCheckResult
    { fcrSuccess     = success
    , fcrDiagnostics = diags
    , fcrHolesCount  = nHoles
    }


-- ---------------------------------------------------------------------------
-- get_diagnostics
-- ---------------------------------------------------------------------------

-- | Lightweight diagnostic summary: run Agda, count errors/warnings/holes.
handleGetDiagnostics :: AgdaConfig -> GetDiagnosticsParams -> IO (Either Text DiagnosticsResult)
handleGetDiagnostics cfg params = do
  src <- TIO.readFile (gdFilePath params)
  result <- runAgda cfg (gdFilePath params)
  let diags    = parseDiagnostics (arStderr result)
      nErrors  = length [() | Diagnostic DiagError _ _ _ <- diags]
      nWarns   = length [() | Diagnostic DiagWarning _ _ _ <- diags]
      holes    = findHoles src
      holeInfo = [ GoalInfo
                     { giGoal    = "?"  -- Lightweight: no goal extraction here.
                     , giContext = []
                     , giModule  = Nothing
                     }
                 | _ <- holes
                 ]
  pure . Right $ DiagnosticsResult
    { drFilePath = gdFilePath params
    , drErrors   = nErrors
    , drWarnings = nWarns
    , drHoles    = holeInfo
    }


-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- | Parse Agda stderr into a list of diagnostics.
--
-- This is a best-effort heuristic parser.  Agda error messages typically
-- look like:
--   @/path/File.agda:10,5-15: error: [GenericDocError]@
-- followed by indented message lines.
--
-- For v0, we do a simple line-by-line scan for "error" and "warning".
parseDiagnostics :: Text -> [Diagnostic]
parseDiagnostics stderr' =
  let ls = T.lines stderr'
  in  concatMap classifyLine ls
  where
    classifyLine ln
      | hasLocatedError ln = [Diagnostic DiagError (T.strip ln) (parseLine ln) Nothing]
      | hasLocatedWarning ln = [Diagnostic DiagWarning (T.strip ln) (parseLine ln) Nothing]
      | otherwise = []

    hasLocatedError ln =
      ": error:" `T.isInfixOf` ln || "[Error]" `T.isInfixOf` ln
    hasLocatedWarning ln =
      ": warning:" `T.isInfixOf` ln || "[Warning]" `T.isInfixOf` ln

    -- Best-effort line number extraction from "File.agda:10,5-15:"
    parseLine ln =
      case T.splitOn ":" ln of
        (_ : locPart : _) ->
          case T.splitOn "," (T.strip locPart) of
            (lineT : _) -> case reads (T.unpack lineT) of
              [(n, "")] -> Just n
              _         -> Nothing
            _ -> Nothing
        _ -> Nothing

-- | Create a temporary directory for scratch Agda files.
makeTmpDir :: String -> IO FilePath
makeTmpDir label = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> label
  createDirectoryIfMissing True dir
  pure dir

-- Bring concatMap into scope for the list comprehension in parseDiagnostics.
-- (It's in Prelude, but explicit for clarity with GHC2021.)
