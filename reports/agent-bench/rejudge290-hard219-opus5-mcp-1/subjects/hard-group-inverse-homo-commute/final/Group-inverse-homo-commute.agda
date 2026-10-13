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

open import Algebra.Properties.Group  using ( ⁻¹-involutive ; ⁻¹-anti-homo-∙ )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  inverse-homo-commute : (∀ x y → (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹) → Commutative _≈_ _∙_
  inverse-homo-commute ih x y =
    trans (∙-cong (sym (inv x)) (sym (inv y)))
   (trans (sym (⁻¹-anti-homo-∙ G (y ⁻¹) (x ⁻¹)))
   (trans (ih (y ⁻¹) (x ⁻¹))
          (∙-cong (inv y) (inv x))))
    where
    inv : ∀ z → (z ⁻¹) ⁻¹ ≈ z
    inv = ⁻¹-involutive G
