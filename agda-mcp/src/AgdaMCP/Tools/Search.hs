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
--   The tools are as follows:
--   * search_by_name: substring match on prettyQname and prettyName;
--   * search_by_type: every fragment in the type as a statement writes it
--     (issue #202), or, with qualified: true, a substring of the corpus's
--     printing;
--   * get_dependencies: dependency list and an optional 1-hop expansion.
--
-- See also:
--   AgdaMCP.Corpus     — the search/index logic.
--   AgdaMCP.Types      — param/result types.
--   docs/roadmap.md M1-3 — issue description.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.Search
  ( handleSearchByName
  , inScopeParams
  , handleSearchByType
  , handleGetDependencies
  ) where

import Data.Text (Text)

import AgdaMCP.Corpus (searchByName, searchByType, searchByTypeWritten, getDeps)
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


-- | inScopeParams: a @search_by_name@ call with @inScopeAt@, as the
-- search_in_scope query it is (issue #203): the name pattern is the query,
-- the address is the anchor, and the limit counts accepted names.  Nothing
-- else of search_in_scope's is offered here (type tokens, the goal-derived
-- query, exclusions, the probe budget); a server started with @--expose@
-- naming search_in_scope presents those.  The server routes such a call to
-- 'AgdaMCP.Tools.SearchInScope.handleSearchInScope', since it needs the
-- interaction lane, which this module's pure handlers never touch.
inScopeParams :: SearchByNameParams -> InScopeAt -> SearchInScopeParams
inScopeParams p at = SearchInScopeParams
  { sipFilePath  = isaFilePath at
  , sipLine      = isaLine at
  , sipColumn    = isaColumn at
  , sipQuery     = Just (SearchQuery (Just (sbnPattern p)) [])
  , sipLimit     = sbnLimit p
  , sipMaxProbes = Nothing
  , sipExclude   = Nothing
  , sipReload    = isaReload at
  }


-- ═══════════════════════════════════════════════════════════════════════════
-- § search_by_type
-- ═══════════════════════════════════════════════════════════════════════════

-- | Handle the @search_by_type@ tool call.
--
-- The fragments are @pattern@ and every member of @patterns@; a call with
-- neither is refused.  By default each fragment is matched against the type
-- as a statement writes it ('searchByTypeWritten'); @qualified: true@ is the
-- match from before issue #202, a substring of the printed type, which for
-- one pattern answers exactly as the tool did then ('searchByType').
-- Returns a JSON array of 'SearchResult' objects.
handleSearchByType :: CorpusIndex -> SearchByTypeParams -> Either Text [SearchResult]
handleSearchByType idx params
  | null fragments =
      Left "search_by_type needs pattern or patterns: a fragment of a type, written as a statement writes it."
  | sbtQualified params == Just True =
      Right (searchByType fragments (sbtLimit params) idx)
  | otherwise =
      searchByTypeWritten fragments (sbtLimit params) idx
  where
    fragments = maybe [] pure (sbtPattern params) <> maybe [] id (sbtPatterns params)


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
