-- ScopeSearchBarrel.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ScopeSearchBarrel.agda
--
-- Description:
--   A barrel that re-exports ScopeSearchBarrel.Core without defining anything
--   itself, for the search_in_scope fixture (issue #17): the shape whose rows
--   the scope rule admits at a dot boundary and whose defining module the
--   importing file cannot name directly.
module ScopeSearchBarrel where

open import ScopeSearchBarrel.Core public
