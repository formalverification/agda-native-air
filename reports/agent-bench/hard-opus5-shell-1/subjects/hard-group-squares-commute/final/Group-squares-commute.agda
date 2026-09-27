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

import Algebra.Properties.Group         as GroupProperties
import Relation.Binary.Reasoning.Setoid as SetoidReasoning

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupProperties G using ( ∙-cancelˡ ; ∙-cancelʳ )
  open SetoidReasoning setoid

  squares-commute : (∀ x y → (x ∙ y) ∙ (x ∙ y) ≈ (x ∙ x) ∙ (y ∙ y)) → Commutative _≈_ _∙_
  squares-commute sq x y = ∙-cancelʳ x (x ∙ y) (y ∙ x)
                             (∙-cancelˡ y ((x ∙ y) ∙ x) ((y ∙ x) ∙ x) step)
    where
    step : y ∙ ((x ∙ y) ∙ x) ≈ y ∙ ((y ∙ x) ∙ x)
    step = begin
      y ∙ ((x ∙ y) ∙ x)  ≈⟨ ∙-congˡ (assoc x y x) ⟩
      y ∙ (x ∙ (y ∙ x))  ≈⟨ assoc y x (y ∙ x) ⟨
      (y ∙ x) ∙ (y ∙ x)  ≈⟨ sq y x ⟩
      (y ∙ y) ∙ (x ∙ x)  ≈⟨ assoc y y (x ∙ x) ⟩
      y ∙ (y ∙ (x ∙ x))  ≈⟨ ∙-congˡ (assoc y x x) ⟨
      y ∙ ((y ∙ x) ∙ x)  ∎
