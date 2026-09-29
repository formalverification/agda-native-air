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

import Algebra.Properties.Group as GroupProperties

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupProperties G using ( ⁻¹-involutive ; ⁻¹-anti-homo-∙ )

  inverse-homo-commute : (∀ x y → (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹) → Commutative _≈_ _∙_
  inverse-homo-commute ih x y = trans (trans step₁ step₂) step₃
    where
    step₁ : x ∙ y ≈ (y ⁻¹ ∙ x ⁻¹) ⁻¹
    step₁ = trans (sym (⁻¹-involutive (x ∙ y))) (⁻¹-cong (⁻¹-anti-homo-∙ x y))

    step₂ : (y ⁻¹ ∙ x ⁻¹) ⁻¹ ≈ y ⁻¹ ⁻¹ ∙ x ⁻¹ ⁻¹
    step₂ = ih (y ⁻¹) (x ⁻¹)

    step₃ : y ⁻¹ ⁻¹ ∙ x ⁻¹ ⁻¹ ≈ y ∙ x
    step₃ = ∙-cong (⁻¹-involutive y) (⁻¹-involutive x)
