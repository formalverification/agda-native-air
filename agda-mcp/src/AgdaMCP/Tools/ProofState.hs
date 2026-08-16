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
  , errorTagsOf
  , onlyOpenHoleErrors
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
  ( AgdaConfig, AgdaResult (..), agdaFlags, debugLog, reportExpr
  , parseGoalContext, runAgda
  )
import AgdaMCP.Holes
  ( HoleSpan (..), LiterateFlavour, findHoles, flavourOf, maskNonCode
  , injectReportExpr, substituteHole
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
      -- ensureDebugImport runs BEFORE hole finding, so injectReportExpr
      -- locates the hole in the already-shifted (import-injected) source.
      case injectReportExpr (reportExpr cfg) (flavourOf absPath)
             (ggHoleIndex params) (ensureDebugImport (flavourOf absPath) src) of
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
-- 3. Exit 0 → ok.  A non-zero exit is ok only when 'onlyOpenHoleErrors' holds,
--    i.e. every reported error is an open hole's @[UnsolvedInteractionMetas]@;
--    a candidate that leaves @[UnsolvedMetaVariables]@ or
--    @[UnsolvedConstraints]@ behind is a type error (issue #69).
handleFillHole :: AgdaConfig -> FillHoleParams -> IO (Either Text FillResult)
handleFillHole cfg params = do
  absPath <- makeAbsolute (fhFilePath params)
  origBytes <- BS.readFile absPath
  case TE.decodeUtf8' origBytes of
    Left err  -> pure (Left (decodeError absPath err))
    Right src ->
      case substituteHole (flavourOf absPath) (fhHoleIndex params) (fhCandidate params) src of
        Nothing -> pure . Left $
          "Hole index " <> T.pack (show (fhHoleIndex params))
          <> " not found in " <> T.pack (fhFilePath params)
        Just patched -> do
          result <- runInPlace cfg absPath origBytes patched
          -- Agda 2.8.0 emits some errors on stdout; check both streams.
          let combined = arStdout result <> "\n" <> arStderr result
              -- Verdict (issue #69).  A non-zero exit is ok only when every
              -- reported error is an open hole's [UnsolvedInteractionMetas];
              -- 'onlyOpenHoleErrors' explains why this is a whitelist.  An
              -- exit code of -1 means the agda binary could not be run at all.
              status
                | arExitCode result == 0      = FillOk
                | arExitCode result == (-1)   = FillCrash
                | onlyOpenHoleErrors combined = FillOk
                | otherwise                   = FillTypeError
              msg    = if status == FillOk
                         then Nothing
                         else Just (T.take 2000 combined)
              -- Count remaining holes (every Agda hole syntax, code regions
              -- only) in the patched source after substitution.
              remainingHoles = length (findHoles (flavourOf absPath) patched)
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
      nHoles  = length (findHoles (flavourOf absPath) src)
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
--
-- Each hole is reported with its 0-based index (the @holeIndex@ accepted by
-- get_goal / fill_hole) and its 1-based line/column in the file as written —
-- literate-file coordinates for literate sources (issue #73).
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
      holes    = findHoles (flavourOf absPath) src
      holeInfo = [ HoleInfo
                     { hiIndex = i
                     , hiLine  = hsLine h
                     , hiCol   = hsCol h
                     , hiGoal  = "?"  -- Lightweight: no goal extraction here.
                     }
                 | (i, h) <- zip [0 ..] holes
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
--
-- Only the file's /contents/ are restored, not its modification time: the restore write
-- deliberately leaves a fresh mtime.  That is intentional — a newer mtime forces Agda to
-- re-typecheck from the restored source on its next load under any interface-freshness
-- rule, whereas resetting mtime to the original (older) value could let Agda reuse an
-- @.agdai@ built from the transiently-patched content (e.g. a fill_hole candidate that
-- completed the module).  Editors that compare content, not mtime alone, will not prompt,
-- since the bytes are unchanged.
runInPlace :: AgdaConfig -> FilePath -> BS.ByteString -> Text -> IO AgdaResult
runInPlace cfg absPath originalBytes patched =
  bracket_
    (BS.writeFile absPath (TE.encodeUtf8 patched))
    (BS.writeFile absPath originalBytes)
    (runAgda cfgInPlace absPath)
  where
    cfgInPlace = cfg { agdaFlags = agdaFlags cfg <> ["-i", takeDirectory absPath] }


-- | ensureDebugImport: ensure @open import AgdaDojang.Debug@ is in scope at the top
-- level (best-effort).
--
-- The @reportGoalCtx@ macro get_goal injects lives in @AgdaDojang.Debug@; a library
-- file being inspected will not normally import it.  If the top-level module already
-- imports it this is a no-op; otherwise the import is inserted immediately after the
-- module header — i.e. after the header's closing @where@, which may be several lines
-- below the @module@ keyword when the module is parameterised (common in agda-algebras).
-- agda-dojang is on the library path (@-l agda-dojang@), so the import resolves.
--
-- Literate awareness (issues #71/#73): all line scans run over the source with its
-- non-code regions masked out ('maskNonCode'), so a prose line that happens to start
-- with @module@ (or mention the import) can neither misplace the injection nor
-- suppress it — the header is found inside a code region, where the inserted line is
-- Agda-visible.  The import also inherits the header line's indentation, which keeps
-- it inside indentation-delimited code blocks (@.lagda.rst@); an unindented insert
-- there would terminate the block.  Masking preserves the line structure, so line
-- indices found on the masked text splice correctly into the original.
--
-- The "already imported?" scan is restricted to the *top-level* prelude — the lines
-- after the top-level module header, up to the first nested @module@ — so an import
-- inside a nested module (which does not bring names into the surrounding scope) does
-- not suppress injection.  Both that scan and the header search look at real
-- import/module lines (not mere substrings), so a passing mention of @AgdaDojang.Debug@
-- or @module@ in a comment neither suppresses the injection nor misplaces it.  When no
-- @module … where@ header is found the source is returned unchanged (get_goal then
-- surfaces the resulting scope error), so injection is best-effort, not guaranteed.
ensureDebugImport :: LiterateFlavour -> Text -> Text
ensureDebugImport flav src =
  case moduleHeaderSpan maskedLs of
    Nothing -> src   -- no top-level module header found; leave as-is (best-effort)
    Just (hdrLine, afterHdr)
      | any isDebugImportLine (takeWhile (not . startsModule) (drop afterHdr maskedLs)) -> src
      | otherwise ->
          let indent          = T.takeWhile isIndentChar (maskedLs !! hdrLine)
              (before, after) = splitAt afterHdr (T.lines src)
          in  T.unlines (before <> [indent <> "open import AgdaDojang.Debug"] <> after)
  where
    maskedLs = T.lines (maskNonCode flav src)

    isIndentChar c = c == ' ' || c == '\t'

    -- A nested `module …` line ends the top-level prelude; imports below it are not in
    -- the surrounding scope, so they must not count as "already imported".
    startsModule l = "module" `T.isPrefixOf` T.stripStart (stripLineComment l)

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

-- | moduleHeaderSpan: locate the top-level module header in (masked) source lines.
-- Returns the 0-based index of the @module@ line and the index just past the header's
-- closing line — the first subsequent line carrying a standalone @where@ token (they
-- may be the same line, or several apart for a parameterised module).  Line comments
-- are stripped before the scan, so a @where@ (or @module@) sitting inside a @--@
-- comment on a header line is ignored.  Returns @Nothing@ if no header is found.
moduleHeaderSpan :: [Text] -> Maybe (Int, Int)
moduleHeaderSpan ls = do
  i    <- findIndex (\l -> "module" `T.isPrefixOf` T.stripStart (stripLineComment l)) ls
  jRel <- findIndex (\l -> "where" `elem` T.words (stripLineComment l)) (drop i ls)
  pure (i, i + jRel + 1)

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


-- | errorTagsOf: every bracketed error name in Agda's output, in order of
-- appearance.  Agda (≥ 2.6.4) prints one @…: error: [TagName]@ header line per
-- error; warning headers say @warning: [TagName]@ and are deliberately not
-- collected — a warning never flips a fill verdict.
errorTagsOf :: Text -> [Text]
errorTagsOf out =
  [ tag
  | ln <- T.lines out
  , let (_, rest) = T.breakOn marker ln
  , not (T.null rest)
  , let tag = T.takeWhile (/= ']') (T.drop (T.length marker) rest)
  , not (T.null tag)
  ]
  where
    marker = "error: ["

-- | onlyOpenHoleErrors: does a failed typecheck fail /only/ because of open
-- holes?
--
-- Interaction metas are always visible holes in the source — the file's other,
-- still-open holes, or new sub-holes the candidate itself introduced (a
-- successful refinement, per the tool contract).  So a non-zero exit is
-- attributable to open holes exactly when every reported error is
-- @[UnsolvedInteractionMetas]@.  Anything else — @[UnsolvedMetaVariables]@,
-- @[UnsolvedConstraints]@, a scope or type error — is a defect the strict gate
-- (@agda \<file\>@) would report, and calling it ok is the trust failure of
-- issue #69: a candidate that "typechecks" per fill_hole yet fails the build.
--
-- This replaces an earlier tag /blacklist/, which reported ok whenever an open
-- hole's interaction metas appeared alongside an unlisted error class (e.g.
-- [UnsolvedMetaVariables] from an implicit nothing constrains).  As a
-- whitelist, unrecognized error classes fail closed — including a failure
-- whose output carries no parsable error header at all.
onlyOpenHoleErrors :: Text -> Bool
onlyOpenHoleErrors combined =
  case errorTagsOf combined of
    []   -> False
    tags -> all (== "UnsolvedInteractionMetas") tags


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
