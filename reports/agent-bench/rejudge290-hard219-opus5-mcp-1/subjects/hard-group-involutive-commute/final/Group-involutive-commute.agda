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

import Algebra.Properties.Group as GroupProperties
import Relation.Binary.Reasoning.Setoid as SetoidReasoning

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupProperties G using ( ⁻¹-anti-homo-∙ )
  open SetoidReasoning setoid

  involutive-commute : (∀ x → x ∙ x ≈ ε) → Commutative _≈_ _∙_
  involutive-commute inv x y = begin
    x ∙ y        ≈⟨ self-inv (x ∙ y) ⟨
    (x ∙ y) ⁻¹   ≈⟨ ⁻¹-anti-homo-∙ x y ⟩
    y ⁻¹ ∙ x ⁻¹  ≈⟨ ∙-cong (self-inv y) (self-inv x) ⟩
    y ∙ x        ∎
    where
    self-inv : ∀ z → z ⁻¹ ≈ z
    self-inv z = begin
      z ⁻¹            ≈⟨ identityʳ (z ⁻¹) ⟨
      z ⁻¹ ∙ ε        ≈⟨ ∙-congˡ (inv z) ⟨
      z ⁻¹ ∙ (z ∙ z)  ≈⟨ assoc (z ⁻¹) z z ⟨
      z ⁻¹ ∙ z ∙ z    ≈⟨ ∙-congʳ (inverseˡ z) ⟩
      ε ∙ z           ≈⟨ identityˡ z ⟩
      z               ∎
