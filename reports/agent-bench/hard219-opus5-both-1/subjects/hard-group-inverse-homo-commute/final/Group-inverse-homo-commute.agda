-- Group-inverse-homo-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-inverse-homo-commute.agda
--
-- Benchmark obligation: hard-group-inverse-homo-commute
-- Difficulty: compositional
-- Import stratum: novel
--
-- If (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹ for all x and y, the group is commutative.
--
module Group-inverse-homo-commute where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open import Algebra.Properties.Group G
    using ( ⁻¹-involutive ; ⁻¹-anti-homo-∙ )
  open import Relation.Binary.Reasoning.Setoid setoid

  inverse-homo-commute : (∀ x y → (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹) → Commutative _≈_ _∙_
  inverse-homo-commute ih x y = begin
    x ∙ y                  ≈⟨ ⁻¹-involutive (x ∙ y) ⟨
    ((x ∙ y) ⁻¹) ⁻¹        ≈⟨ ⁻¹-cong (ih x y) ⟩
    (x ⁻¹ ∙ y ⁻¹) ⁻¹       ≈⟨ ⁻¹-anti-homo-∙ (x ⁻¹) (y ⁻¹) ⟩
    (y ⁻¹) ⁻¹ ∙ (x ⁻¹) ⁻¹  ≈⟨ ∙-cong (⁻¹-involutive y) (⁻¹-involutive x) ⟩
    y ∙ x                  ∎
