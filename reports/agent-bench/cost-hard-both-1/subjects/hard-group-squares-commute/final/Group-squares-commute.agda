-- Group-squares-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-squares-commute.agda
--
-- Benchmark obligation: hard-group-squares-commute
-- Difficulty: non-obvious
-- Source: exam genre, group theory qualifying exams (Algebra.Bundles.Group)
-- Import stratum: novel
-- Strategy: cancellation twice on the hypothesis at (x ∙ y) ∙ (x ∙ y)
--
-- If (x ∙ y)² ≈ x² ∙ y² for all x and y, the group is commutative.
--
module Group-squares-commute where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )

import Algebra.Properties.Group as GroupProperties
import Relation.Binary.Reasoning.Setoid as SetoidReasoning

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupProperties G using ( ∙-cancelˡ ; ∙-cancelʳ )
  open SetoidReasoning setoid

  squares-commute : (∀ x y → (x ∙ y) ∙ (x ∙ y) ≈ (x ∙ x) ∙ (y ∙ y)) → Commutative _≈_ _∙_
  squares-commute sq x y = sym (∙-cancelʳ y (y ∙ x) (x ∙ y) (∙-cancelˡ x _ _ inner))
    where
    inner : x ∙ ((y ∙ x) ∙ y) ≈ x ∙ ((x ∙ y) ∙ y)
    inner = begin
      x ∙ ((y ∙ x) ∙ y)  ≈⟨ ∙-congˡ (assoc y x y) ⟩
      x ∙ (y ∙ (x ∙ y))  ≈⟨ assoc x y (x ∙ y) ⟨
      (x ∙ y) ∙ (x ∙ y)  ≈⟨ sq x y ⟩
      (x ∙ x) ∙ (y ∙ y)  ≈⟨ assoc x x (y ∙ y) ⟩
      x ∙ (x ∙ (y ∙ y))  ≈⟨ ∙-congˡ (assoc x y y) ⟨
      x ∙ ((x ∙ y) ∙ y)  ∎
