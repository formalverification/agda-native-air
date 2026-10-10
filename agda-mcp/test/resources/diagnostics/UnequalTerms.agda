-- UnequalTerms.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/UnequalTerms.agda
--
-- Description:
--   Fixture for issue #74: a type mismatch, the § 5 row asking for "expected
--   and actual, normalized, plus the source range" (`involved.actual`,
--   `involved.expected`, `range`).  The body has the wrong type: [UnequalTerms]
--   `Bool !=< Nat` under Agda 2.8.0, [UnequalTypes] "The type Bool is not a
--   subtype of Nat" under 2.9.0 (#234; UnequalTermsRefl.agda keeps the code).
module UnequalTerms where

open import Agda.Builtin.Bool
open import Agda.Builtin.Nat

n : Nat
n = true
