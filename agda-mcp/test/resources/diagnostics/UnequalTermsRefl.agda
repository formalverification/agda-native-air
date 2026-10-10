-- UnequalTermsRefl.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/UnequalTermsRefl.agda
--
-- Description:
--   Fixture for issue #234: the [UnequalTerms] error for two terms.  Under
--   Agda 2.8.0 the sibling UnequalTerms.agda, a mismatch of types, raised
--   [UnequalTerms] too; under 2.9.0 that one raises [UnequalTypes], and
--   [UnequalTerms] is left to terms that differ, as here.  So this fixture
--   keeps the code under test in both versions: `0 != 1 of type Nat` under
--   2.8.0, "The terms 0 and 1 are not equal at type Nat" under 2.9.0, with
--   `involved.actual` 0 and `involved.expected` 1 either way.
module UnequalTermsRefl where

open import Agda.Builtin.Equality
open import Agda.Builtin.Nat

p : 0 ≡ 1
p = refl
