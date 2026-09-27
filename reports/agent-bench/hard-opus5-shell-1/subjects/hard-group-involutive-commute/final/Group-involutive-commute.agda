-- Group-involutive-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-involutive-commute.agda
--
-- Benchmark obligation: hard-group-involutive-commute
-- Difficulty: compositional
-- Source: exam genre (Algebra.Bundles.Group)
-- Import stratum: novel
-- Strategy: every element is its own inverse; expand (x ∙ y) ∙ (x ∙ y) ≈ ε
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
  open import Algebra.Properties.Group G using ( inverseˡ-unique ; ⁻¹-anti-homo-∙ )
  open import Relation.Binary.Reasoning.Setoid setoid

  involutive-commute : (∀ x → x ∙ x ≈ ε) → Commutative _≈_ _∙_
  involutive-commute inv x y = begin
    x ∙ y              ≈⟨ inverseˡ-unique (x ∙ y) (x ∙ y) (inv (x ∙ y)) ⟩
    (x ∙ y) ⁻¹         ≈⟨ ⁻¹-anti-homo-∙ x y ⟩
    y ⁻¹ ∙ x ⁻¹        ≈⟨ ∙-cong (sym (self y)) (sym (self x)) ⟩
    y ∙ x              ∎
    where
    self : ∀ z → z ≈ z ⁻¹
    self z = inverseˡ-unique z z (inv z)
