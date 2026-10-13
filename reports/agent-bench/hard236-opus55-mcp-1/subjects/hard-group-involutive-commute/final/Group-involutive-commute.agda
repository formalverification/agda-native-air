-- Group-involutive-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-involutive-commute.agda
--
-- Benchmark obligation: hard-group-involutive-commute
-- Difficulty: compositional
-- Import stratum: novel
--
-- If x ∙ x ≈ ε for every x, the group is commutative.
--
module Group-involutive-commute where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  involutive-commute : (∀ x → x ∙ x ≈ ε) → Commutative _≈_ _∙_
  involutive-commute inv x y = begin
      x ∙ y                           ≈⟨ sym (identityˡ (x ∙ y)) ⟩
      ε ∙ (x ∙ y)                     ≈⟨ ∙-congʳ (sym (inv (y ∙ x))) ⟩
      ((y ∙ x) ∙ (y ∙ x)) ∙ (x ∙ y)   ≈⟨ assoc (y ∙ x) (y ∙ x) (x ∙ y) ⟩
      (y ∙ x) ∙ ((y ∙ x) ∙ (x ∙ y))   ≈⟨ ∙-congˡ lem ⟩
      (y ∙ x) ∙ ε                     ≈⟨ identityʳ (y ∙ x) ⟩
      y ∙ x                           ∎
    where
    open import Relation.Binary.Reasoning.Setoid setoid
    lem : (y ∙ x) ∙ (x ∙ y) ≈ ε
    lem = begin
      (y ∙ x) ∙ (x ∙ y)   ≈⟨ assoc y x (x ∙ y) ⟩
      y ∙ (x ∙ (x ∙ y))   ≈⟨ ∙-congˡ (sym (assoc x x y)) ⟩
      y ∙ ((x ∙ x) ∙ y)   ≈⟨ ∙-congˡ (∙-congʳ (inv x)) ⟩
      y ∙ (ε ∙ y)         ≈⟨ ∙-congˡ (identityˡ y) ⟩
      y ∙ y               ≈⟨ inv y ⟩
      ε                   ∎
