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
  squares-commute sq x y = ∙-cancelʳ x (x ∙ y) (y ∙ x) step₂
    where
    step₁ : x ∙ (y ∙ x) ≈ y ∙ (x ∙ x)
    step₁ = ∙-cancelˡ y (x ∙ (y ∙ x)) (y ∙ (x ∙ x)) (begin
      y ∙ (x ∙ (y ∙ x))  ≈⟨ assoc y x (y ∙ x) ⟨
      (y ∙ x) ∙ (y ∙ x)  ≈⟨ sq y x ⟩
      (y ∙ y) ∙ (x ∙ x)  ≈⟨ assoc y y (x ∙ x) ⟩
      y ∙ (y ∙ (x ∙ x))  ∎)

    step₂ : (x ∙ y) ∙ x ≈ (y ∙ x) ∙ x
    step₂ = begin
      (x ∙ y) ∙ x  ≈⟨ assoc x y x ⟩
      x ∙ (y ∙ x)  ≈⟨ step₁ ⟩
      y ∙ (x ∙ x)  ≈⟨ assoc y x x ⟨
      (y ∙ x) ∙ x  ∎
