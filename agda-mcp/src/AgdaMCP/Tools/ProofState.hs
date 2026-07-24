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
--
--   Design note — all four tools typecheck the file IN PLACE.
--     Agda decides a module's name from where its file sits relative to the include
--     path, so a module embedded in a library at a hierarchical path (e.g. FLRP.Bridge
--     at src/FLRP/Bridge.lagda.md) only resolves when it is checked at its real
--     location, with the library's src root on the include path (supplied by the
--     caller's `-l <lib>` flag).  An earlier version copied the file to a scratch
--     directory before checking it; that works for flat top-level modules but collides
--     with the module's canonical file for library-embedded ones (ModuleDefinedInOtherFile
--     / ModuleNameDoesntMatchFileName).  See issue #66.
--
--     get_goal and fill_hole must still alter the source (inject the reporting macro,
--     or substitute a candidate), so they patch the real file transiently and restore
--     it under 'Control.Exception.bracket_'.  The original is captured and restored as
--     raw bytes ('Data.ByteString'), so the file is returned byte-for-byte even if Agda
--     errors or the call is interrupted — no encoding or newline round-trip is involved.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.ProofState
  ( handleGetGoal
  , handleFillHole
  , handleCheckFile
  , handleGetDiagnostics
    -- * Exposed for testing
  , ensureDebugImport
  , moduleNameOf
  ) where

import Control.Exception (bracket_)
import qualified Data.ByteString as BS
import Data.List (find, findIndex)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (UnicodeException)
import qualified Data.Text.IO as TIO

import System.Directory (makeAbsolute)
import System.FilePath (takeDirectory)

import AgdaMCP.Agda
  ( AgdaConfig, AgdaResult (..), agdaFlags, debugLog
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
-- 2. Ensure @open import AgdaDojang.Debug@ is in scope (inject it if absent) so the
--    @reportGoalCtx@ macro resolves.
-- 3. Replace hole @n@ with @reportGoalCtx ?@.
-- 4. Typecheck the patched file IN PLACE (restoring the original afterwards).
-- 5. Parse the AGDADOJANG_REQ_BEGIN/END block from Agda's output.
-- 6. Return structured (goal, context).
handleGetGoal :: AgdaConfig -> GetGoalParams -> IO (Either Text GoalInfo)
handleGetGoal cfg params = do
  absPath <- makeAbsolute (ggFilePath params)
  origBytes <- BS.readFile absPath
  case TE.decodeUtf8' origBytes of
    Left err  -> pure (Left (decodeError absPath err))
    Right src ->
      case injectReportExpr cfg (ggHoleIndex params) (ensureDebugImport src) of
        Nothing -> pure . Left $
          "Hole index " <> T.pack (show (ggHoleIndex params))
          <> " not found in " <> T.pack absPath
        Just patched -> do
          result <- runInPlace cfg absPath origBytes patched
          -- DEBUG: show what Agda actually returned
          debugLog cfg $ "get_goal: exit=" <> T.pack (show (arExitCode result))
          debugLog cfg $ "get_goal stdout: " <> T.take 500 (arStdout result)
          debugLog cfg $ "get_goal stderr: " <> T.take 500 (arStderr result)
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
                -- The declared module name (e.g. FLRP.Bridge), parsed from the
                -- header — not the file's base name.
                , giModule  = moduleNameOf src
                }


-- ---------------------------------------------------------------------------
-- fill_hole
-- ---------------------------------------------------------------------------

-- | handleFillHole: try substituting @candidate@ into hole @n@ and typecheck.
--
-- 1. Read source, substitute candidate into hole n.
-- 2. Typecheck the patched file IN PLACE (restoring the original afterwards).
-- 3. If exit 0 → success; otherwise → type error (tolerating unsolved metas from
--    the file's other, still-open holes).
handleFillHole :: AgdaConfig -> FillHoleParams -> IO (Either Text FillResult)
handleFillHole cfg params = do
  absPath <- makeAbsolute (fhFilePath params)
  origBytes <- BS.readFile absPath
  case TE.decodeUtf8' origBytes of
    Left err  -> pure (Left (decodeError absPath err))
    Right src ->
      case substituteHole (fhHoleIndex params) (fhCandidate params) src of
        Nothing -> pure . Left $
          "Hole index " <> T.pack (show (fhHoleIndex params))
          <> " not found in " <> T.pack (fhFilePath params)
        Just patched -> do
          result <- runInPlace cfg absPath origBytes patched
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
              remainingHoles = length (findHoles patched)
          pure . Right $ FillResult
            { frStatus    = status
            , frCandidate = fhCandidate params
            , frMessage   = msg
            , frRemainingHoles = Just remainingHoles
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

-- | runInPlace: typecheck a transiently-patched version of a file at its real path.
--
-- Writes @patched@ (as UTF-8) over @absPath@, runs Agda there with the same include
-- strategy 'handleCheckFile' uses (base flags — which carry the caller's @-l \<lib\>@,
-- hence the library's src root — plus @-i \<dir-of-file\>@), then restores
-- @originalBytes@.  Both the write and the restore go through 'Data.ByteString', and
-- the restore runs under 'bracket_', so the file is returned to its exact original
-- bytes even if Agda errors or the call is interrupted — no encoding or newline
-- round-trip is involved.  Checking at the real path (rather than a scratch copy) is
-- what lets hierarchically-named library modules resolve — see the module header and
-- issue #66.
runInPlace :: AgdaConfig -> FilePath -> BS.ByteString -> Text -> IO AgdaResult
runInPlace cfg absPath originalBytes patched =
  bracket_
    (BS.writeFile absPath (TE.encodeUtf8 patched))
    (BS.writeFile absPath originalBytes)
    (runAgda cfgInPlace absPath)
  where
    cfgInPlace = cfg { agdaFlags = agdaFlags cfg <> ["-i", takeDirectory absPath] }


-- | ensureDebugImport: guarantee @open import AgdaDojang.Debug@ is in scope.
--
-- The @reportGoalCtx@ macro get_goal injects lives in @AgdaDojang.Debug@; a library
-- file being inspected will not normally import it.  If the module already imports it
-- this is a no-op; otherwise the import is inserted immediately after the module
-- header — i.e. after the header's closing @where@, which may be several lines below
-- the @module@ keyword when the module is parameterised (common in agda-algebras).
-- Placing it there is valid for both @.agda@ and literate @.lagda.md@ sources, since
-- the header sits in code context in both.  agda-dojang is on the library path
-- (@-l agda-dojang@), so the import resolves.
--
-- Both the "already imported?" test and the header search look at real import/module
-- lines (not mere substrings), so a passing mention of @AgdaDojang.Debug@ or @module@
-- in a comment neither suppresses the injection nor misplaces it.
ensureDebugImport :: Text -> Text
ensureDebugImport src
  | any isDebugImportLine ls = src
  | otherwise =
      case splitAfterModuleHeader ls of
        Nothing           -> src   -- no single-line-terminated module header found
        Just (hdr, rest)  ->
          T.unlines (hdr <> ["open import AgdaDojang.Debug"] <> rest)
  where
    ls = T.lines src

    -- A genuine import of the module: with any line comment stripped, the first
    -- token is an import-introducing keyword, @import@ is present, and
    -- @AgdaDojang.Debug@ appears as a whole module token — so none of a comment
    -- mention, an inline @-- … AgdaDojang.Debug@ trailer, or a longer name such as
    -- @AgdaDojang.Debug.Extra@ is mistaken for the import.
    isDebugImportLine ln =
      case T.words (stripLineComment ln) of
        ws@(w : _) -> w `elem` ["import", "open", "private"]
                   && "import"           `elem` ws
                   && "AgdaDojang.Debug"  `elem` ws
        []         -> False

-- | splitAfterModuleHeader: split source lines just after the top-level module
-- header.  The header runs from the first line whose code begins with @module@
-- through the first subsequent line that carries a standalone @where@ token (they may
-- be the same line, or several apart for a parameterised module).  Line comments are
-- stripped before the scan, so a @where@ (or @module@) sitting inside a @--@ comment on
-- a header line is ignored.  Returns @Nothing@ if no such header is found.
splitAfterModuleHeader :: [Text] -> Maybe ([Text], [Text])
splitAfterModuleHeader ls = do
  i    <- findIndex (\l -> "module" `T.isPrefixOf` T.stripStart (stripLineComment l)) ls
  jRel <- findIndex (\l -> "where" `elem` T.words (stripLineComment l)) (drop i ls)
  pure (splitAt (i + jRel + 1) ls)

-- | stripLineComment: drop an Agda @--@ line comment (best-effort: treats the first
-- @--@ as the comment start).  Enough to keep comment text out of the keyword and
-- @where@ scans above; block comments (@{- … -}@) are not handled.
stripLineComment :: Text -> Text
stripLineComment = fst . T.breakOn "--"

-- | moduleNameOf: the declared top-level module name, parsed from the @module …@
-- header line (with any line comment stripped).  This is the *declared* name — e.g.
-- @FLRP.Bridge@ — not the file's base name, which would mangle a hierarchical module
-- to its last segment and strip only one extension from a literate @.lagda.md@ file.
-- Returns @Nothing@ when no @module@ header is found.
moduleNameOf :: Text -> Maybe Text
moduleNameOf src = do
  hdr <- find (\l -> "module" `T.isPrefixOf` T.stripStart (stripLineComment l)) (T.lines src)
  case dropWhile (/= "module") (T.words (stripLineComment hdr)) of
    (_ : name : _) -> Just name
    _              -> Nothing

-- | decodeError: a structured error for a file whose bytes are not valid UTF-8.  Agda
-- source is required to be UTF-8, so this should not arise in practice, but returning a
-- 'Left' is friendlier than letting a 'UnicodeException' escape the tool call.
decodeError :: FilePath -> UnicodeException -> Text
decodeError path err =
  "Could not decode " <> T.pack path <> " as UTF-8 (Agda source must be UTF-8): "
  <> T.pack (show err)


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
