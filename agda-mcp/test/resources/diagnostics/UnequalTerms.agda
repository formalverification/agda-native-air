-- UnequalTerms.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/UnequalTerms.agda
--
-- Description:
--   Fixture for issue #74: the [UnequalTerms] error.  The body below has the
--   wrong type for its signature, so Agda prints its `actual !=< expected`
--   line — the feedback document's § 5 row asking for "expected and actual,
--   normalized, plus the source range", which the diagnostic carries as
--   `involved.actual` / `involved.expected` and `range`.
module UnequalTerms where

open import Agda.Builtin.Bool
open import Agda.Builtin.Nat

n : Nat
n = true
