-- TwoObligations.agda
--
-- File: strux-driver/src/test/resources/search/TwoObligations.agda
--
-- Test fixture for the proof-search state model (issue #113, P0): a goal
-- whose evident move is applying a lemma with TWO visible arguments, so a
-- single fill_hole of `lemma {!!} {!!}` answers status "ok" while leaving
-- two open obligations.  The integration test drives exactly the #112
-- regression scenario on it: discharging one obligation must not make the
-- state solved.  Builtins only, so it checks with no library flags.
--
module TwoObligations where

open import Agda.Builtin.Unit

record Pair : Set where
  constructor mkPair
  field
    fst : ⊤
    snd : ⊤

lemma : ⊤ → ⊤ → Pair
lemma a b = mkPair a b

goal : Pair
goal = {!!}
