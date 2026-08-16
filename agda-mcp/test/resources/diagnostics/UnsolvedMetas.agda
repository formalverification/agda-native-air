-- UnsolvedMetas.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/UnsolvedMetas.agda
--
-- Description:
--   Fixture for issue #74: [UnsolvedConstraints] together with
--   [UnsolvedMetaVariables] — the last row of the feedback document's § 5
--   corpus, and the shape of the field session's own worst case ("implicits
--   under a defined function", § 4).
--
--   The postulate below takes two implicit Nats and its type mentions only
--   their sum.  Addition is a defined function and not injective, so the use
--   underneath leaves `_n + _m = 3` stuck: Agda reports the unsolvable
--   constraint with no position at all, and the unsolved metas with one.
--   Between them they exercise both halves of the parser — the located header
--   and the bare `error: [Code]` one, which the pre-#74 extractor dropped
--   entirely.  (The postulate's name is deliberately not spelled in this
--   header: the test locates its use site by searching the fixture for it.)
module UnsolvedMetas where

open import Agda.Builtin.Nat

postulate
  Bounded : Nat → Set
  blocked : {n m : Nat} → Bounded (n + m)

three : Bounded 3
three = blocked
