-- | Corpus.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Corpus.hs
--
-- Description:
--   Corpus loading and search operations for the agda-mcp search tools (M1-3).
--
--   This module provides:
--   1. 'loadCorpus'    — read an agda-strux JSONL file into a 'CorpusIndex'.
--   2. 'searchByName'  — case-insensitive substring search on prettyQname/prettyName.
--   3. 'searchByType'  — case-insensitive substring search on the type signature.
--   4. 'getDeps'       — dependency lookup with optional 1-hop expansion.
--
--   All search functions are pure (operate on the in-memory 'CorpusIndex').
--   The index is loaded once at server startup via the @--corpus@ CLI flag.
--
--   Performance note (M1-3):
--     Name and type search are O(n) linear scans over the entry map.  Measured
--     against the real agda-algebras corpus (issue #84) — 11,666 rows keyed to
--     10,520 entries, 185 MB of JSONL — the whole file loads in 1.4 s to a
--     308 MB resident footprint, and a search answers well inside the time an
--     MCP round-trip costs anyway.  M2-2 (issue #16) upgrades to inverted
--     indices for sub-linear lookup.
--
--     The footprint is what it is because 'CorpusEntry' keeps only the fields
--     the search tools serve; see its Haddock in "AgdaMCP.Types" for what is
--     read and dropped, and why.
--
-- See also:
--   docs/representation.md §3 — canonical JSONL schema.
--   docs/roadmap.md M1-3     — issue description.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns      #-}

module AgdaMCP.Corpus
  ( -- * Loading
    loadCorpus
    -- * Search (pure)
  , searchByName
  , searchByType
  , getDeps
    -- * Utilities
  , entryToSearchResult
  ) where

import Control.Exception (IOException, try)
import Data.Aeson (eitherDecodeStrict')
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.IO (hPutStrLn, stderr)

import AgdaMCP.Types


-- ═══════════════════════════════════════════════════════════════════════════
-- § Loading
-- ═══════════════════════════════════════════════════════════════════════════

-- | Load an agda-strux JSONL file into a 'CorpusIndex'.
--
-- Each line is parsed as a 'CorpusEntry'; lines that fail to parse are
-- skipped and counted.  The first few parse errors are logged to stderr
-- for debugging.  Duplicate @prettyQname@ keys are resolved by keeping
-- the last occurrence (consistent with how Agda resolves re-exported names).
--
-- Returns @Left msg@ if the file cannot be read; @Right idx@ on success.
loadCorpus :: FilePath -> IO (Either Text CorpusIndex)
loadCorpus path = do
  hPutStrLn stderr $ "agda-mcp: loading corpus from " <> path
  result <- try (BS.readFile path)
  case result of
    Left (e :: IOException) ->
      pure . Left . T.pack $ "Failed to read corpus: " <> show e
    Right contents -> do
      let lns      = filter (not . BS8.null) (BS8.lines contents)
          (ok, bad) = foldl' parseLine ([], 0 :: Int) (zip [1 :: Int ..] lns)
          entryMap = Map.fromList [ (cePrettyQname e, e) | e <- reverse ok ]
          idx      = CorpusIndex { ciEntries = entryMap, ciSize = Map.size entryMap }
      if bad > 0
        then do
          hPutStrLn stderr $
            "agda-mcp: corpus loaded: " <> show (ciSize idx)
            <> " entries (" <> show bad <> " lines skipped due to parse errors)"
          -- Re-scan the first few failures for diagnostic output.
          -- Cost is negligible: we only do this when errors exist, and stop at 3.
          let firstErrors = take 3
                [ (ln, err)
                | (ln, bs) <- zip [1 :: Int ..] lns
                , Left err <- [eitherDecodeStrict' bs :: Either String CorpusEntry]
                ]
          mapM_ (\(ln, err) ->
            hPutStrLn stderr $ "  line " <> show ln <> ": " <> err) firstErrors
        else
          hPutStrLn stderr $
            "agda-mcp: corpus loaded: " <> show (ciSize idx) <> " entries"
      pure (Right idx)
  where
    parseLine :: ([CorpusEntry], Int) -> (Int, BS.ByteString) -> ([CorpusEntry], Int)
    parseLine (!acc, !errCount) (_lineNum, bs) =
      case eitherDecodeStrict' bs of
        Right entry -> (entry : acc, errCount)
        Left _err   -> (acc, errCount + 1)


-- ═══════════════════════════════════════════════════════════════════════════
-- § Search by name
-- ═══════════════════════════════════════════════════════════════════════════

-- | Find definitions whose @prettyQname@ or @prettyName@ contains the given
-- pattern (case-insensitive substring match).
--
-- Results are ordered by @prettyQname@ (Map iteration order = lexicographic).
-- Limited to @limit@ results (default: 20).
searchByName :: Text -> Maybe Int -> CorpusIndex -> [SearchResult]
searchByName pattern limit idx =
  take lim
    . map entryToSearchResult
    . filter matchesName
    . Map.elems
    $ ciEntries idx
  where
    lim = maybe 20 (max 1) limit  -- a positive integer
    -- ^ Minimum 1: a limit of 0 is treated as 1.
    patLower = T.toLower pattern
    matchesName e =
      patLower `T.isInfixOf` T.toLower (cePrettyQname e)
        || patLower `T.isInfixOf` T.toLower (cePrettyName e)


-- ═══════════════════════════════════════════════════════════════════════════
-- § Search by type
-- ═══════════════════════════════════════════════════════════════════════════

-- | Find definitions whose pretty-printed @type@ contains the given pattern
-- (case-insensitive substring match).
--
-- This is string-level matching for M1-3.  Structural matching via @typeAst@
-- is an M2 goal (see roadmap.md M2-3).
searchByType :: Text -> Maybe Int -> CorpusIndex -> [SearchResult]
searchByType pattern limit idx =
  take lim
    . map entryToSearchResult
    . filter matchesType
    . Map.elems
    $ ciEntries idx
  where
    lim      = maybe 20 (max 1) limit
    patLower = T.toLower pattern
    matchesType e =
      patLower `T.isInfixOf` T.toLower (ceType e)


-- ═══════════════════════════════════════════════════════════════════════════
-- § Get dependencies
-- ═══════════════════════════════════════════════════════════════════════════

-- | Look up a definition by @prettyQname@ and return its dependency list.
--
-- If @expand@ is 'True', also resolve each dependency token to its corpus
-- entry (by searching for entries whose @prettyName@ matches the token).
-- This gives the agent a 1-hop neighborhood view.
getDeps :: Text -> Maybe Bool -> CorpusIndex -> Either Text DependenciesResult
getDeps qname expand idx =
  case Map.lookup qname (ciEntries idx) of
    Nothing -> Left $ "Definition not found: " <> qname
    Just entry ->
      let deps     = ceDependencies entry
          doExpand = maybe False id expand
          neighbors
            | doExpand  = concatMap (resolveDepToken idx) deps
            | otherwise = []
      in Right DependenciesResult
           { depName         = cePrettyQname entry
           , depType         = ceType entry
           , depDependencies = deps
           , depNeighbors    = neighbors
           }


-- ═══════════════════════════════════════════════════════════════════════════
-- § Utilities
-- ═══════════════════════════════════════════════════════════════════════════

-- | Convert a 'CorpusEntry' to a 'SearchResult' (the agent-facing subset).
entryToSearchResult :: CorpusEntry -> SearchResult
entryToSearchResult e = SearchResult
  { srPrettyQname = cePrettyQname e
  , srType        = ceType e
  , srDefKind     = ceDefKind e
  , srModule      = cePrettyModule e
  , srHasBody     = ceHasBody e
  }

-- | Resolve a dependency token to matching corpus entries.
--
-- The @dependencies@ field holds tokens extracted from the type string (see
-- agda-strux Extract.hs 'dependenciesFromTypeText').  What those tokens look
-- like depends on the corpus, and the two shapes need different lookups:
--
--   +  A real extraction prints Agda's internal names, so the tokens are
--      FULLY QUALIFIED — @Overture.Signatures.Signature@, not @Signature@.
--      Those are exactly @prettyQname@ keys, so an exact map lookup resolves
--      them in one step.  Matching only on @prettyName@ resolved none of
--      them: driving the agda-algebras corpus through the real transport,
--      @expand=true@ on an isomorphism lemma expanded 0 of its 9 tokens
--      (issue #84).
--   +  Shorter, unqualified tokens (@Algebra@, @hom@, @Set@) still occur, so
--      the @prettyName@ scan remains as the fallback.  It is case-sensitive,
--      Agda names being case-sensitive, and capped at 5 matches so a very
--      common short name cannot blow up a response.
--
-- A token may match nothing at all, which is the honest answer for a
-- dependency on the standard library or on @Agda.Primitive@.
resolveDepToken :: CorpusIndex -> Text -> [SearchResult]
resolveDepToken idx token =
  case Map.lookup token (ciEntries idx) of
    Just entry -> [entryToSearchResult entry]
    Nothing    ->
      take 5
        . map entryToSearchResult
        . filter (\e -> cePrettyName e == token)
        . Map.elems
        $ ciEntries idx
