-- Group-inverse-homo-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-inverse-homo-commute.agda
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

open import Relation.Binary.Reasoning.Setoid as SetoidReasoning using ( )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open import Algebra.Properties.Group G using ( ⁻¹-involutive ; ⁻¹-anti-homo-∙ )
  open SetoidReasoning setoid

  inverse-homo-commute : (∀ x y → (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹) → Commutative _≈_ _∙_
  inverse-homo-commute ih x y = begin
    x ∙ y                 ≈⟨ ∙-cong (⁻¹-involutive x) (⁻¹-involutive y) ⟨
    x ⁻¹ ⁻¹ ∙ y ⁻¹ ⁻¹      ≈⟨ swap (x ⁻¹) (y ⁻¹) ⟩
    y ⁻¹ ⁻¹ ∙ x ⁻¹ ⁻¹      ≈⟨ ∙-cong (⁻¹-involutive y) (⁻¹-involutive x) ⟩
    y ∙ x                 ∎
    where
    swap : ∀ a b → a ⁻¹ ∙ b ⁻¹ ≈ b ⁻¹ ∙ a ⁻¹
    swap a b = trans (sym (ih a b)) (⁻¹-anti-homo-∙ a b)
