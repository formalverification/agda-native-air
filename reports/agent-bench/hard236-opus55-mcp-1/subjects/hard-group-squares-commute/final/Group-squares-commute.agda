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
  squares-commute sq x y = ∙-cancelʳ x (x ∙ y) (y ∙ x) (∙-cancelˡ y _ _ h)
    where
    open import Algebra.Properties.Group G using (∙-cancelˡ; ∙-cancelʳ)
    open import Relation.Binary.Reasoning.Setoid setoid
    h : y ∙ ((x ∙ y) ∙ x) ≈ y ∙ ((y ∙ x) ∙ x)
    h = begin
      y ∙ ((x ∙ y) ∙ x)   ≈⟨ ∙-congˡ (assoc x y x) ⟩
      y ∙ (x ∙ (y ∙ x))   ≈⟨ assoc y x (y ∙ x) ⟨
      (y ∙ x) ∙ (y ∙ x)   ≈⟨ sq y x ⟩
      (y ∙ y) ∙ (x ∙ x)   ≈⟨ assoc y y (x ∙ x) ⟩
      y ∙ (y ∙ (x ∙ x))   ≈⟨ ∙-congˡ (assoc y x x) ⟨
      y ∙ ((y ∙ x) ∙ x)   ∎
