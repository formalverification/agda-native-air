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

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  squares-commute : (∀ x y → (x ∙ y) ∙ (x ∙ y) ≈ (x ∙ x) ∙ (y ∙ y)) → Commutative _≈_ _∙_
  squares-commute sq = {!!}
