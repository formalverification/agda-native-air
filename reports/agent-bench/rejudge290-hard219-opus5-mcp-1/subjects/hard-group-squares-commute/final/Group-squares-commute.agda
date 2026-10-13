-- Group-squares-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-squares-commute.agda
--
-- Benchmark obligation: hard-group-squares-commute
-- Difficulty: non-obvious
-- Import stratum: novel
--
-- If (x ∙ y)² ≈ x² ∙ y² for all x and y, the group is commutative.
--
module Group-squares-commute where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )

import Algebra.Properties.Group as GroupProperties

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupProperties G using ( ∙-cancelˡ ; ∙-cancelʳ )

  squares-commute : (∀ x y → (x ∙ y) ∙ (x ∙ y) ≈ (x ∙ x) ∙ (y ∙ y)) → Commutative _≈_ _∙_
  squares-commute sq x y = sym (∙-cancelʳ y (y ∙ x) (x ∙ y) step₂)
    where
    lhs : (x ∙ y) ∙ (x ∙ y) ≈ x ∙ ((y ∙ x) ∙ y)
    lhs = trans (assoc x y (x ∙ y)) (∙-congˡ (sym (assoc y x y)))

    rhs : (x ∙ x) ∙ (y ∙ y) ≈ x ∙ ((x ∙ y) ∙ y)
    rhs = trans (assoc x x (y ∙ y)) (∙-congˡ (sym (assoc x y y)))

    step₁ : x ∙ ((y ∙ x) ∙ y) ≈ x ∙ ((x ∙ y) ∙ y)
    step₁ = trans (sym lhs) (trans (sq x y) rhs)

    step₂ : (y ∙ x) ∙ y ≈ (x ∙ y) ∙ y
    step₂ = ∙-cancelˡ x ((y ∙ x) ∙ y) ((x ∙ y) ∙ y) step₁
