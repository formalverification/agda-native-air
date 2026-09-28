-- Group-unique-involution-central.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/gold/Group-unique-involution-central.agda
--
-- Benchmark obligation: hard-group-unique-involution-central
-- Difficulty: non-obvious
-- Source: exam genre (Algebra.Bundles.Group)
-- Import stratum: novel
-- Strategy: conjugate a by b; the conjugate is an involution, so it is ε or a; ε is refuted
--
-- A unique nontrivial involution is central: if a ∙ a ≈ ε, a is not ε, and every involution is ε or a, then b ∙ a ∙ b ⁻¹ ≈ a for every b.
--
module Group-unique-involution-central where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )
open import Data.Sum.Base            using ( _⊎_ )
open import Relation.Nullary.Negation using ( ¬_ )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b =
    fromInj₂ (λ aᵇ≈ε → contradiction (a≈ε aᵇ≈ε) a≉ε) (unique aᵇ aᵇ∙aᵇ≈ε)
    where
    open import Algebra.Properties.Group G              using  ( ∙-cancelˡ
                                                               ; \\-leftDividesʳ
                                                               ; x∙y⁻¹≈ε⇒x≈y )
    open import Algebra.Properties.Semigroup semigroup  using  ( uv≈w⇒xu∙vy≈x∙wy )
    open import Data.Sum.Base                           using  ( fromInj₂ )
    open import Relation.Nullary.Negation               using  ( contradiction )
    open import Relation.Binary.Reasoning.Setoid setoid

    -- The conjugate of a by b is an involution, so it is ε or a ...
    aᵇ : Carrier
    aᵇ = (b ∙ a) ∙ b ⁻¹

    aᵇ∙aᵇ≈ε : aᵇ ∙ aᵇ ≈ ε
    aᵇ∙aᵇ≈ε = begin
      b ∙ a ∙ b ⁻¹ ∙ (b ∙ a ∙ b ⁻¹)  ≈⟨ uv≈w⇒xu∙vy≈x∙wy (\\-leftDividesʳ b a) (b ∙ a) (b ⁻¹) ⟩
      b ∙ a ∙ (a ∙ b ⁻¹)             ≈⟨ uv≈w⇒xu∙vy≈x∙wy a²≈ε b (b ⁻¹) ⟩
      b ∙ (ε ∙ b ⁻¹)                 ≈⟨ ∙-congˡ (identityˡ (b ⁻¹)) ⟩
      b ∙ b ⁻¹                       ≈⟨ inverseʳ b ⟩
      ε                              ∎

    -- ... and it is not ε, since then a would be.
    a≈ε : aᵇ ≈ ε → a ≈ ε
    a≈ε aᵇ≈ε = ∙-cancelˡ b a ε (begin
      b ∙ a  ≈⟨ x∙y⁻¹≈ε⇒x≈y (b ∙ a) b aᵇ≈ε ⟩
      b      ≈⟨ identityʳ b ⟨
      b ∙ ε  ∎)
