-- Group-inverse-homo-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/gold/Group-inverse-homo-commute.agda
--
-- Benchmark obligation: hard-group-inverse-homo-commute
-- Difficulty: compositional
-- Source: exam genre (Algebra.Bundles.Group); Algebra.Properties.Group has ⁻¹-anti-homo-∙
-- Import stratum: novel
-- Strategy: compare (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹ with ⁻¹-anti-homo-∙ and apply ⁻¹-involutive
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

  inverse-homo-commute : (∀ x y → (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹) → Commutative _≈_ _∙_
  inverse-homo-commute ih x y = begin
    x ∙ y               ≈⟨ ∙-cong (⁻¹-involutive x) (⁻¹-involutive y) ⟨
    x ⁻¹ ⁻¹ ∙ y ⁻¹ ⁻¹   ≈⟨ ⁻¹-anti-homo-∙ (y ⁻¹) (x ⁻¹)               ⟨
    ( y ⁻¹ ∙ x ⁻¹ ) ⁻¹  ≈⟨ ⁻¹-cong (ih y x)                           ⟨
    ( y ∙ x )⁻¹ ⁻¹      ≈⟨ ⁻¹-involutive (y ∙ x)                      ⟩
    y ∙ x               ∎
    where
    open import Relation.Binary.Reasoning.Setoid setoid
    open import Algebra.Properties.Group G using ( ⁻¹-involutive ; ⁻¹-anti-homo-∙ )
