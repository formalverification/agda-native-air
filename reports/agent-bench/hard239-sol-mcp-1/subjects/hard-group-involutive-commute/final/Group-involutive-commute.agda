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
  involutive-commute inv x y =
    trans (uniqueʳ-⁻¹ (x ∙ y) (x ∙ y) (inv (x ∙ y)))
          (sym (uniqueʳ-⁻¹ (x ∙ y) (y ∙ x) product-inverse))
    where
    product-inverse : (x ∙ y) ∙ (y ∙ x) ≈ ε
    product-inverse =
      trans (assoc x y (y ∙ x))
      (trans (∙-cong refl (sym (assoc y y x)))
      (trans (∙-cong refl (∙-cong (inv y) refl))
      (trans (∙-cong refl (identityˡ x))
             (inv x))))
