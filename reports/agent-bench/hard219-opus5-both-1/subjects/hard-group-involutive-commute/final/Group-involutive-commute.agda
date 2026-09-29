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
  open import Algebra.Properties.Group G
    using ( inverseˡ-unique ; ⁻¹-anti-homo-∙ )

  involutive-commute : (∀ x → x ∙ x ≈ ε) → Commutative _≈_ _∙_
  involutive-commute inv x y =
    trans (inverseˡ-unique (x ∙ y) (x ∙ y) (inv (x ∙ y)))
    (trans (⁻¹-anti-homo-∙ x y)
           (∙-cong (sym (inverseˡ-unique y y (inv y)))
                   (sym (inverseˡ-unique x x (inv x)))))
