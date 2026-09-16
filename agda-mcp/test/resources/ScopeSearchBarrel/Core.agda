-- Core.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ScopeSearchBarrel/Core.agda
--
-- Description:
--   The defining module behind the ScopeSearchBarrel re-export, for the
--   search_in_scope fixture (issue #17).  ScopeSearch.agda imports the barrel
--   and never this module, so `quad`'s own qualified name is not in that
--   file's scope and the ladder's third rung (the importing module qualifying
--   the bare name) is the one the lane accepts.
module ScopeSearchBarrel.Core where

open import Agda.Builtin.Nat

quad : Nat → Nat
quad n = n + n + n + n
