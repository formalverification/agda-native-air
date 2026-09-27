-- Group-unique-involution-central.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-unique-involution-central.agda
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

open import Data.Empty                using ( ⊥-elim )
open import Data.Sum.Base             using ( inj₁ ; inj₂ )
import Algebra.Properties.Group as GroupProperties
import Relation.Binary.Reasoning.Setoid as SetoidReasoning

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupProperties G
  open SetoidReasoning setoid

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b = result
    where
    z : Carrier
    z = (b ∙ a) ∙ b ⁻¹

    -- the inner cancellation: b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹) ≈ a ∙ b ⁻¹
    inner : b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹) ≈ a ∙ b ⁻¹
    inner = begin
      b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹)  ≈⟨ ∙-congˡ (assoc b a (b ⁻¹)) ⟩
      b ⁻¹ ∙ (b ∙ (a ∙ b ⁻¹))  ≈⟨ assoc (b ⁻¹) b (a ∙ b ⁻¹) ⟨
      (b ⁻¹ ∙ b) ∙ (a ∙ b ⁻¹)  ≈⟨ ∙-congʳ (inverseˡ b) ⟩
      ε ∙ (a ∙ b ⁻¹)           ≈⟨ identityˡ (a ∙ b ⁻¹) ⟩
      a ∙ b ⁻¹                 ∎

    z²≈ε : z ∙ z ≈ ε
    z²≈ε = begin
      ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹)  ≈⟨ assoc (b ∙ a) (b ⁻¹) ((b ∙ a) ∙ b ⁻¹) ⟩
      (b ∙ a) ∙ (b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹))  ≈⟨ ∙-congˡ inner ⟩
      (b ∙ a) ∙ (a ∙ b ⁻¹)                 ≈⟨ assoc b a (a ∙ b ⁻¹) ⟩
      b ∙ (a ∙ (a ∙ b ⁻¹))                 ≈⟨ ∙-congˡ (assoc a a (b ⁻¹)) ⟨
      b ∙ ((a ∙ a) ∙ b ⁻¹)                 ≈⟨ ∙-congˡ (∙-congʳ a²≈ε) ⟩
      b ∙ (ε ∙ b ⁻¹)                       ≈⟨ ∙-congˡ (identityˡ (b ⁻¹)) ⟩
      b ∙ b ⁻¹                             ≈⟨ inverseʳ b ⟩
      ε                                    ∎

    z≈ε⇒a≈ε : z ≈ ε → a ≈ ε
    z≈ε⇒a≈ε z≈ε = ∙-cancelˡ b a ε (begin
      b ∙ a  ≈⟨ inverseˡ-unique (b ∙ a) (b ⁻¹) z≈ε ⟩
      b ⁻¹ ⁻¹  ≈⟨ ⁻¹-involutive b ⟩
      b        ≈⟨ identityʳ b ⟨
      b ∙ ε    ∎)

    result : z ≈ a
    result with unique z z²≈ε
    ... | inj₁ z≈ε = ⊥-elim (a≉ε (z≈ε⇒a≈ε z≈ε))
    ... | inj₂ z≈a = z≈a
