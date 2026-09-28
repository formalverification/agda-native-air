-- Group-involutive-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/gold/Group-involutive-commute.agda
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

  involutive-commute : (∀ x → x ∙ x ≈ ε) → Commutative _≈_ _∙_
  involutive-commute inv x y = begin
    x ∙ y        ≈⟨ z≈z⁻¹ (x ∙ y) ⟩
    (x ∙ y) ⁻¹   ≈⟨ ⁻¹-anti-homo-∙ x y ⟩
    y ⁻¹ ∙ x ⁻¹  ≈⟨ ∙-cong (z≈z⁻¹ y) (z≈z⁻¹ x) ⟨
    y ∙ x        ∎
    where
    open import Algebra.Properties.Group G using ( inverseˡ-unique ; ⁻¹-anti-homo-∙ )
    open import Relation.Binary.Reasoning.Setoid setoid
    z≈z⁻¹ : ∀ z → z ≈ z ⁻¹
    z≈z⁻¹ z = inverseˡ-unique z z (inv z)

  -- An alternative proof, by the group axioms alone (see data/benchmarks/README.md,
  -- "Alternative proofs").
  involutive-commute-by-axioms : (∀ x → x ∙ x ≈ ε) → Commutative _≈_ _∙_
  involutive-commute-by-axioms inv x y = begin
    x ∙ y                        ≈⟨ identityˡ (x ∙ y)                   ⟨
    ε ∙ (x ∙ y)                  ≈⟨ ∙-congʳ (inv (y ∙ x))               ⟨
    y ∙ x ∙ (y ∙ x) ∙ (x ∙ y)    ≈⟨ assoc (y ∙ x) (y ∙ x) (x ∙ y)       ⟩
    y ∙ x ∙ (y ∙ x ∙ (x ∙ y))    ≈⟨ ∙-congˡ (assoc y x (x ∙ y))         ⟩
    y ∙ x ∙ (y ∙ (x ∙ (x ∙ y)))  ≈⟨ ∙-congˡ (∙-congˡ (assoc x x y))     ⟨
    y ∙ x ∙ (y ∙ (x ∙ x ∙ y))    ≈⟨ ∙-congˡ (∙-congˡ (∙-congʳ (inv x))) ⟩
    y ∙ x ∙ (y ∙ (ε ∙ y))        ≈⟨ ∙-congˡ (∙-congˡ (identityˡ y))     ⟩
    y ∙ x ∙ (y ∙ y)              ≈⟨ ∙-congˡ (inv y)                     ⟩
    y ∙ x ∙ ε                    ≈⟨ identityʳ (y ∙ x)                   ⟩
    y ∙ x                        ∎
    where
    open import Relation.Binary.Reasoning.Setoid setoid
