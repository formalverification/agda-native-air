-- FixtureStdlibBooleanAlgebra.agda
--
-- File: agda-dojang/data/fixtures/FixtureStdlibBooleanAlgebra.agda
--
-- Description:
--   Tiny fixture for deterministic Agda-check evaluation.  Intended to be solved by
--   the scripted fixture policy.  These are very simple examples of holes that can
--   be used to test the behavior of the hole policy.  Each hole (`?`) should be
--   filled in by the hole policy according to the context and goal.
--

module FixtureStdlibBooleanAlgebra where

-- AgdaDojang reporting macro used by agent_bridge / eval_fixtures:
open import AgdaDojang.Debug using (reportGoalCtx)

open import Data.Bool.Base using (Bool; true; false)
open import Data.Bool.Properties using  ( ∨-∧-booleanAlgebra
                                        ; ∧-identityˡ ; ∧-identityʳ
                                        ; ∨-identityʳ
                                        ; ∨-zeroʳ; ∧-zeroʳ )
open import Algebra.Lattice.Bundles using (BooleanAlgebra)
open BooleanAlgebra (∨-∧-booleanAlgebra)
open import Relation.Binary.Reasoning.Setoid setoid
-- The `setoid` is inherited from the boolean algebra's distributive lattice.
open import Algebra.Definitions (_≈_) using (Involutive)
-- Stdlib already proves these for any BooleanAlgebra; instantiate with the Bool one.
open import Algebra.Lattice.Properties.BooleanAlgebra (∨-∧-booleanAlgebra)
  using (⊥≉⊤; deMorgan₁; deMorgan₂)

complements : ∀ x y → x ∧ y ≈ ⊥ → x ∨ y ≈ ⊤ → ¬ x ≈ y
complements x y x∧y=⊥ x∨y=⊤ = begin
  ¬ x                ≈˘⟨ ∧-identityʳ _ ⟩
  ¬ x ∧ ⊤            ≈˘⟨ ∧-congˡ x∨y=⊤ ⟩
  ¬ x ∧ (x ∨ y)      ≈⟨ ∧-distribˡ-∨ (¬ x) x y ⟩
  ¬ x ∧ x ∨ ¬ x ∧ y  ≈⟨ ∨-congʳ (∧-complementˡ x) ⟩
  ⊥ ∨ ¬ x ∧ y        ≈˘⟨ ∨-congʳ x∧y=⊥ ⟩
  x ∧ y ∨ ¬ x ∧ y    ≈˘⟨ ∧-distribʳ-∨ y x (¬ x) ⟩
  (x ∨ ¬ x) ∧ y      ≈⟨ ∧-congʳ (∨-complementʳ x) ⟩
  ⊤ ∧ y              ≈⟨ ∧-identityˡ _ ⟩
  y                  ∎

¬-involutive : Involutive ¬_
¬-involutive x = complements (¬ x) x (∧-complementˡ x) (∨-complementˡ x)

lemma₁ : ∀ x y → (x ∧ y) ∧ (¬ x ∨ ¬ y) ≈ ⊥
lemma₁ x y = begin
  (x ∧ y) ∧ (¬ x ∨ ¬ y)          ≈⟨ ∧-distribˡ-∨ (x ∧ y) (¬ x) (¬ y) ⟩
  (x ∧ y) ∧ ¬ x ∨ (x ∧ y) ∧ ¬ y  ≈⟨ ∨-congʳ (∧-congʳ (∧-comm x y)) ⟩
  (y ∧ x) ∧ ¬ x ∨ (x ∧ y) ∧ ¬ y  ≈⟨ ∨-cong (∧-assoc y x (¬ x)) (∧-assoc x y (¬ y)) ⟩
  y ∧ (x ∧ ¬ x) ∨ x ∧ (y ∧ ¬ y)  ≈⟨ ∨-cong (∧-congˡ {y} (∧-complementʳ x)) (∧-congˡ (∧-complementʳ y)) ⟩
  (y ∧ ⊥) ∨ (x ∧ ⊥)              ≈⟨ ∨-cong (∧-zeroʳ y) (∧-zeroʳ x) ⟩
  ⊥ ∨ ⊥                          ≈⟨ ∨-identityʳ _ ⟩
  ⊥                              ∎

lemma₂ : (x y : Bool) → (x ∧ y) ∨ (¬ x ∨ ¬ y) ≈ ⊤
lemma₂ x y = begin
  (x ∧ y) ∨ (¬ x ∨ ¬ y)  ≈˘⟨ ∨-assoc (x ∧ y) (¬ x) (¬ y) ⟩
  ((x ∧ y) ∨ ¬ x) ∨ ¬ y  ≈⟨ ∨-congʳ lemma₃ ⟩
  (¬ x ∨ y) ∨ ¬ y        ≈⟨ ∨-assoc (¬ x) y (¬ y) ⟩
  ¬ x ∨ (y ∨ ¬ y)        ≈⟨ ∨-congˡ (∨-complementʳ y) ⟩
  ¬ x ∨ ⊤                ≈⟨ ∨-zeroʳ (¬ x) ⟩
  ⊤                      ∎
  where
  lemma₃ : (x ∧ y) ∨ ¬ x ≈ ¬ x ∨ y
  lemma₃ = begin
    (x ∧ y) ∨ ¬ x          ≈⟨ ∨-distribʳ-∧ (¬ x) x y  ⟩
    (x ∨ ¬ x) ∧ (y ∨ ¬ x)  ≈⟨ ∧-congʳ ( ∨-complementʳ x ) ⟩
    ⊤ ∧ (y ∨ ¬ x)          ≈⟨ ∧-identityˡ (y Data.Bool.Base.∨ ¬ x) ⟩
    y ∨ ¬ x                ≈⟨ ∨-comm y (¬ x) ⟩
    ¬ x ∨ y                ∎

oracle-¬⊥≈⊤ : ¬ ⊥ ≈ ⊤
oracle-¬⊥≈⊤ = complements ⊥ ⊤ (∧-identityʳ _) (∨-zeroʳ false)

oracle-deMorgan₁ : ∀ x y → ¬ (x ∧ y) ≈ ¬ x ∨ ¬ y
oracle-deMorgan₁ = λ x y → complements (x ∧ y) (¬ x ∨ ¬ y) (lemma₁ x y) (lemma₂ x y)

oracle-deMorgan₂ : ∀ x y → ¬ (x ∨ y) ≈ ¬ x ∧ ¬ y
oracle-deMorgan₂ x y = begin
  ¬ (x ∨ y)          ≈˘⟨ ¬-cong (∨-cong (¬-involutive x) (¬-involutive y)) ⟩
  ¬ (¬ ¬ x ∨ ¬ ¬ y)  ≈˘⟨ ¬-cong (oracle-deMorgan₁ (¬ x)(¬ y)) ⟩
  ¬ ¬ (¬ x ∧ ¬ y)    ≈⟨ ¬-involutive (¬ x ∧ ¬ y) ⟩
  ¬ x ∧ ¬ y          ∎

goal-¬⊥≈⊤ : ¬ ⊥ ≈ ⊤
goal-¬⊥≈⊤ = {!!}

goal-deMorgan₁ : ∀ x y → ¬ (x ∧ y) ≈ ¬ x ∨ ¬ y
goal-deMorgan₁ = λ x y → {!!}

goal-deMorgan₂ : ∀ x y → ¬ (x ∨ y) ≈ ¬ x ∧ ¬ y
goal-deMorgan₂ x y = {!!}
