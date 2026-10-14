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
open import Algebra.Properties.Group using ( ⁻¹-anti-homo-∙ )
open import Relation.Binary.Reasoning.Setoid using ()

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  involutive-commute : (∀ x → x ∙ x ≈ ε) → Commutative _≈_ _∙_
  involutive-commute inv x y = begin
    x ∙ y             ≈⟨ sym (self-inverse (x ∙ y)) ⟩
    (x ∙ y) ⁻¹        ≈⟨ ⁻¹-anti-homo-∙ G x y ⟩
    (y ⁻¹) ∙ (x ⁻¹)   ≈⟨ ∙-cong (self-inverse y) (self-inverse x) ⟩
    y ∙ x             ∎
    where
    open Relation.Binary.Reasoning.Setoid setoid

    self-inverse : ∀ z → z ⁻¹ ≈ z
    self-inverse z = begin
      z ⁻¹               ≈⟨ sym (identityʳ (z ⁻¹)) ⟩
      (z ⁻¹) ∙ ε         ≈⟨ ∙-cong refl (sym (inv z)) ⟩
      (z ⁻¹) ∙ (z ∙ z)   ≈⟨ sym (assoc (z ⁻¹) z z) ⟩
      ((z ⁻¹) ∙ z) ∙ z   ≈⟨ ∙-cong (inverseˡ z) refl ⟩
      ε ∙ z              ≈⟨ identityˡ z ⟩
      z                  ∎
