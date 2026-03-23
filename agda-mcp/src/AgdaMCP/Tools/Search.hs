-- | Search.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Tools/Search.hs
--
-- Description:
--   Search tool handlers for the agda-mcp MCP server (M1-3).
--
--   These tools allow the agent to discover relevant definitions from the
--   agda-strux corpus index without calling Agda.  They are pure lookups
--   on the in-memory 'CorpusIndex' loaded at server startup.
--
--   Tools:
--   * search_by_name   — substring match on prettyQname / prettyName
--   * search_by_type   — substring match on the type signature
--   * get_dependencies — dependency list + optional 1-hop expansion
--
-- See also:
--   AgdaMCP.Corpus     — the search/index logic.
--   AgdaMCP.Types      — param/result types.
--   docs/roadmap.md M1-3 — issue description.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.Search
  ( handleSearchByName
  , handleSearchByType
  , handleGetDependencies
  ) where

import Data.Text (Text)

import AgdaMCP.Corpus (searchByName, searchByType, getDeps)
import AgdaMCP.Types


-- ═══════════════════════════════════════════════════════════════════════════
-- § search_by_name
-- ═══════════════════════════════════════════════════════════════════════════

-- | Handle the @search_by_name@ tool call.
--
-- Searches the corpus for definitions whose name matches the given pattern.
-- Returns a JSON array of 'SearchResult' objects.
handleSearchByName :: CorpusIndex -> SearchByNameParams -> Either Text [SearchResult]
handleSearchByName idx params =
  let results = searchByName (sbnPattern params) (sbnLimit params) idx
  in Right results


-- ═══════════════════════════════════════════════════════════════════════════
-- § search_by_type
-- ═══════════════════════════════════════════════════════════════════════════

-- | Handle the @search_by_type@ tool call.
--
-- Searches the corpus for definitions whose type signature contains the pattern.
-- Returns a JSON array of 'SearchResult' objects.
handleSearchByType :: CorpusIndex -> SearchByTypeParams -> Either Text [SearchResult]
handleSearchByType idx params =
  let results = searchByType (sbtPattern params) (sbtLimit params) idx
  in Right results


-- ═══════════════════════════════════════════════════════════════════════════
-- § get_dependencies
-- ═══════════════════════════════════════════════════════════════════════════

-- | Handle the @get_dependencies@ tool call.
--
-- Looks up a definition by prettyQname and returns its dependencies.
-- If @expand@ is true, also returns the corpus entries for each dependency.
handleGetDependencies :: CorpusIndex -> GetDependenciesParams -> Either Text DependenciesResult
handleGetDependencies idx params =
  getDeps (gdpName params) (gdpExpand params) idx
