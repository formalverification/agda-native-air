-- | ProofState.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Tools/ProofState.hs
--
-- Description:
--   Core proof-state tools for the agda-mcp server.
--
--   Each function implements one MCP tool.  They share an 'AgdaConfig' and call the
--   Agda binary via 'AgdaMCP.Agda'.  The agent invokes these through JSON-RPC tool calls;
--   the MCP server layer (AgdaMCP.Server) dispatches to the appropriate handler.
--
--   Tools:
--   * get_goal        - inspect goal type + context at a hole
--   * fill_hole       - try a candidate term and report typecheck result
--   * check_file      - load/reload a file and return all diagnostics
--   * get_diagnostics - lightweight summary (hole count, error count)

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.ProofState
  ( handleGetGoal
  , handleFillHole
  , handleCheckFile
  , handleGetDiagnostics
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import Control.Exception (SomeException, catch)

import System.Directory (createDirectoryIfMissing, createFileLink, getTemporaryDirectory,
                          listDirectory, makeAbsolute, removeDirectoryRecursive)

import System.FilePath ((</>), takeFileName, takeDirectory)
import System.IO (stderr)

import AgdaMCP.Agda
  ( AgdaConfig, AgdaResult (..), agdaFlags
  , findHoles, injectReportExpr, substituteHole
  , parseGoalContext, runAgda
  )
import AgdaMCP.Types

-- ---------------------------------------------------------------------------
-- get_goal
-- ---------------------------------------------------------------------------

-- | handleGetGoal: inspect goal type and local context at hole @n@ in given file.
--
-- 1. Read source file.
-- 2. Replace hole @n@ with @reportGoalCtx ?@.
-- 3. Write a temporary copy and run Agda on it.
-- 4. Parse AGDADOJANG_REQ_BEGIN/END block from stderr.
-- 5. Return structured (goal, context).
handleGetGoal :: AgdaConfig -> GetGoalParams -> IO (Either Text GoalInfo)
handleGetGoal cfg params = do
  absPath <- makeAbsolute (ggFilePath params)
  src <- TIO.readFile absPath
  case injectReportExpr cfg (ggHoleIndex params) src of
    Nothing -> pure . Left $
      "Hole index " <> T.pack (show (ggHoleIndex params))
      <> " not found in " <> T.pack absPath
    Just patched -> do
      tmpDir <- makeTmpDir "agda-mcp-goal"
      let tmpFile = tmpDir </> takeFileName absPath
          srcDir  = takeDirectory absPath
      TIO.writeFile tmpFile patched
      -- Create an overlay of the source directory WITHOUT the file being
      -- checked, to avoid Agda's ModuleDefinedInOtherFile error.
      overlay <- makeOverlay tmpDir srcDir (takeFileName absPath)
      -- Port of agent_bridge.py's include-path strategy:
      --   1. Strip -i <srcDir> from base flags (avoids AmbiguousTopLevelModuleName
      --      if srcDir happens to be on the include path).
      --   2. Add -i <tmpDir> (where the patched file lives — resolves
      --      ModuleNameDoesntMatchFileName) and -i <overlay> (sibling modules).
      let baseFlags  = stripIncludeDir srcDir (agdaFlags cfg)
          extraFlags = ["-i", tmpDir, "-i", overlay]
          cfgWithDir = cfg { agdaFlags = baseFlags <> extraFlags }
      result <- runAgda cfgWithDir tmpFile
      -- DEBUG: show what Agda actually returned
      TIO.hPutStrLn stderr $ "DEBUG get_goal: exit=" <> T.pack (show (arExitCode result))
      TIO.hPutStrLn stderr $ "DEBUG stdout: " <> T.take 500 (arStdout result)
      TIO.hPutStrLn stderr $ "DEBUG stderr: " <> T.take 500 (arStderr result)
      -- Agda may emit markers on stdout or stderr; check both.
      let combined = arStdout result <> "\n" <> arStderr result
      case parseGoalContext combined of
        Nothing -> pure . Left $
          "Could not parse goal/context markers from Agda output.\n"
          <> "output:\n" <> T.take 2000 combined
        Just (goal, ctx) ->
          pure . Right $ GoalInfo
            { giGoal    = goal
            , giContext = ctx
            , giModule  = Just . T.pack . takeFileName $ ggFilePath params
            }


-- ---------------------------------------------------------------------------
-- fill_hole
-- ---------------------------------------------------------------------------

-- | handleFillHole: try substituting @candidate@ into hole @n@ and typecheck.
--
-- 1. Read source, substitute candidate into hole n.
-- 2. Write temp copy, run Agda.
-- 3. If exit 0 → success; otherwise → type error.
handleFillHole :: AgdaConfig -> FillHoleParams -> IO (Either Text FillResult)
handleFillHole cfg params = do
  absPath <- makeAbsolute (fhFilePath params)
  src <- TIO.readFile absPath
  case substituteHole (fhHoleIndex params) (fhCandidate params) src of
    Nothing -> pure . Left $
      "Hole index " <> T.pack (show (fhHoleIndex params))
      <> " not found in " <> T.pack (fhFilePath params)
    Just patched -> do
      tmpDir <- makeTmpDir "agda-mcp-fill"
      let tmpFile = tmpDir </> takeFileName absPath
          srcDir  = takeDirectory absPath
      TIO.writeFile tmpFile patched
      overlay <- makeOverlay tmpDir srcDir (takeFileName absPath)
      let baseFlags  = stripIncludeDir srcDir (agdaFlags cfg)
          extraFlags = ["-i", tmpDir, "-i", overlay]
          cfgWithDir = cfg { agdaFlags = baseFlags <> extraFlags }
      result <- runAgda cfgWithDir tmpFile
          -- Agda 2.8.0 emits some errors on stdout; check both streams.
      let combined = arStdout result <> "\n" <> arStderr result
          -- A non-zero exit is acceptable if the *only* errors are unsolved
          -- interaction metas (from other holes we haven't filled yet).
          -- This mirrors agent_bridge.py's _only_unsolved_metas logic.
          onlyMetas = arExitCode result /= 0
                   && "[UnsolvedInteractionMetas]" `T.isInfixOf` combined
                   && not ("[GenericDocError]"      `T.isInfixOf` combined)
                   && not ("[UnequalTerms]"         `T.isInfixOf` combined)
                   && not ("[TypeMismatch]"          `T.isInfixOf` combined)
                   && not ("[ModuleNameDoesntMatchFileName]" `T.isInfixOf` combined)
          status = if arExitCode result == 0 || onlyMetas then FillOk else FillTypeError
          msg    = if status == FillOk
                     then Nothing
                     else Just (T.take 2000 combined)
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

-- | handleCheckFile: load/reload an Agda file and return all diagnostics.
handleCheckFile :: AgdaConfig -> CheckFileParams -> IO (Either Text FileCheckResult)
handleCheckFile cfg params = do
  absPath <- makeAbsolute (cfFilePath params)
  src <- TIO.readFile absPath
  let extraFlags = ["-i", takeDirectory absPath]
      cfgWithDir = cfg { agdaFlags = agdaFlags cfg <> extraFlags }
  result <- runAgda cfgWithDir absPath
  let combined = arStdout result <> "\n" <> arStderr result
      diags   = parseDiagnostics combined
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

-- | handleGetDiagnostics: diagnostic summary; run Agda, count errors/warnings/holes.
handleGetDiagnostics :: AgdaConfig -> GetDiagnosticsParams -> IO (Either Text DiagnosticsResult)
handleGetDiagnostics cfg params = do
  absPath <- makeAbsolute (gdFilePath params)
  src <- TIO.readFile absPath
  let extraFlags = ["-i", takeDirectory absPath]
      cfgWithDir = cfg { agdaFlags = agdaFlags cfg <> extraFlags }
  result <- runAgda cfgWithDir absPath
  let combined = arStdout result <> "\n" <> arStderr result
      diags    = parseDiagnostics combined
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

-- | parseDiagnostics: parse Agda stderr into a list of diagnostics.
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


-- | stripIncludeDir: strip @-i <dir>@ token pairs from flag list when @dir@ matches @dropDir@.
--
-- In shadow mode we typecheck a temp copy; if the original directory is also on the
-- include path, Agda sees two files for the same module → AmbiguousTopLevelModuleName.
-- (Port of agent_bridge.py's @_drop_include_dir_tokens@.)
stripIncludeDir :: FilePath -> [String] -> [String]
stripIncludeDir _       []                    = []
stripIncludeDir dropDir ("-i" : dir : rest)
  | norm dir == norm dropDir                  = stripIncludeDir dropDir rest
  where norm p = reverse $ dropWhile (== '/') $ reverse p
stripIncludeDir dropDir (x : rest)            = x : stripIncludeDir dropDir rest


-- | makeTmpDir: create a temp directory for scratch Agda files.
makeTmpDir :: String -> IO FilePath
makeTmpDir label = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> label
  createDirectoryIfMissing True dir
  pure dir

-- Bring concatMap into scope for the list comprehension in parseDiagnostics.
-- (It's in Prelude, but explicit for clarity with GHC2021.)

-- | makeOverlay: create overlay directory mirroring @srcDir@ except for @excludeFile@.
--
-- This avoids Agda's @ModuleDefinedInOtherFile@ error when we typecheck a patched
-- copy of a file while still needing sibling imports to resolve.
-- (Port of agent_bridge.py's _ensure_overlay_dir.)
makeOverlay :: FilePath -> FilePath -> String -> IO FilePath
makeOverlay tmpDir srcDir excludeFile = do
  let overlay = tmpDir </> "_overlay"
  -- Remove stale overlay from previous invocations — a prior call may have
  -- excluded a different file, leaving entries that must now be absent.
  removeDirectoryRecursive overlay `catch` \(_ :: SomeException) -> pure ()
  createDirectoryIfMissing True overlay
  entries <- listDirectory srcDir
  let keep = [ e | e <- entries, e /= excludeFile ]
  mapM_ (safeLink overlay) keep
  pure overlay
  where
    safeLink overlay name = do
      let target = srcDir </> name
          link   = overlay </> name
      createFileLink target link
        `catch` \(_ :: SomeException) -> pure ()
