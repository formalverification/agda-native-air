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
  open import Algebra.Properties.Group G using ( ∙-cancelˡ ; ∙-cancelʳ )
  open import Relation.Binary.Reasoning.Setoid setoid

  squares-commute : (∀ x y → (x ∙ y) ∙ (x ∙ y) ≈ (x ∙ x) ∙ (y ∙ y)) → Commutative _≈_ _∙_
  squares-commute sq x y = ∙-cancelˡ x (x ∙ y) (y ∙ x)
                             (∙-cancelʳ y (x ∙ (x ∙ y)) (x ∙ (y ∙ x)) step)
    where
    step : (x ∙ (x ∙ y)) ∙ y ≈ (x ∙ (y ∙ x)) ∙ y
    step = begin
      (x ∙ (x ∙ y)) ∙ y  ≈⟨ ∙-congʳ (assoc x x y) ⟨
      ((x ∙ x) ∙ y) ∙ y  ≈⟨ assoc (x ∙ x) y y ⟩
      (x ∙ x) ∙ (y ∙ y)  ≈⟨ sq x y ⟨
      (x ∙ y) ∙ (x ∙ y)  ≈⟨ assoc x y (x ∙ y) ⟩
      x ∙ (y ∙ (x ∙ y))  ≈⟨ ∙-congˡ (assoc y x y) ⟨
      x ∙ ((y ∙ x) ∙ y)  ≈⟨ assoc x (y ∙ x) y ⟨
      (x ∙ (y ∙ x)) ∙ y  ∎
