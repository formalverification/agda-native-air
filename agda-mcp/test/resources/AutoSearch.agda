-- AutoSearch.agda
--
-- File: agda-native-air/agda-mcp/test/resources/AutoSearch.agda
--
-- Description:
--   The auto tool's fixture (issue #205): one hole per answer Agda's own
--   proof search (Mimer, Cmd_autoOne) gives, each measured under the pinned
--   Agda 2.8.0 before a test asserted it.
--
--   * pair: solved from the context alone, as m , n.
--   * plusZero: no solution, since the search does no induction; with the
--     hint lemma it answers lemma m.  Its other hints are the ones the tool
--     refuses before the search runs: m, a variable of the hole's context,
--     and one, a pattern synonym, both of which the search drops silently.
--   * spread: the term Agda prints runs past its line width, so it arrives
--     across three lines with each continuation at column 1, which a splice
--     as printed cannot absorb.
--   * unwrap: the search projects the record's field, and prints it with the
--     full name AutoScopeInner.Cell.contents, which this file cannot write
--     (it imports AutoScopeOuter alone), so Agda refuses its own term with
--     NotInScope.
module AutoSearch where

open import Agda.Builtin.Nat
open import Agda.Builtin.Equality
open import AutoScopeOuter using (Wrapped)

data _×_ (A B : Set) : Set where
  _,_ : A → B → A × B
infixr 4 _,_
infixr 2 _×_

pair : Nat → Nat → Nat × Nat
pair m n = {!!}

cong : {A B : Set} (f : A → B) {x y : A} → x ≡ y → f x ≡ f y
cong f refl = refl

lemma : (n : Nat) → n + 0 ≡ n
lemma zero    = refl
lemma (suc n) = cong suc (lemma n)

pattern one = suc zero

plusZero : (m : Nat) → m + 0 ≡ m
plusZero m = {!!}

spread : (theFirstLongHypothesisName theSecondLongHypothesisName
          theThirdLongHypothesisName theFourthLongHypothesisName : Nat)
       → Nat × Nat × Nat × Nat
spread theFirstLongHypothesisName theSecondLongHypothesisName
       theThirdLongHypothesisName theFourthLongHypothesisName = {!!}

unwrap : Wrapped → Nat
unwrap w = {!!}
