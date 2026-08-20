-- SameLineScopes.agda
--
-- File: agda-native-air/agda-mcp/test/resources/SameLineScopes.agda
--
-- Description:
--   Fixture for the scoped live queries' column selection (issue #75,
--   Copilot round 3): two holes share one line with different scopes — the
--   first, inside the lambda, sees the bound variable `m`; the second, the
--   lambda's argument, does not.  A line alone cannot tell them apart, so
--   resolve_name("m") must answer differently by column.
module SameLineScopes where

open import Agda.Builtin.Nat

sameLine : Nat -> Nat
sameLine n = (\ m -> {!!}) {!!}
