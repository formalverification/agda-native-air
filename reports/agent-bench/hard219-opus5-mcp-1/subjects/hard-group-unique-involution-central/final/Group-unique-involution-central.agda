-- Group-unique-involution-central.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-unique-involution-central.agda
--
-- Benchmark obligation: hard-group-unique-involution-central
-- Difficulty: non-obvious
-- Import stratum: novel
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

open import Data.Sum.Base using ( inj₁ ; inj₂ )
open import Relation.Nullary.Negation using ( contradiction )
import Relation.Binary.Reasoning.Setoid as SetoidReasoning

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b = result
    where
    open SetoidReasoning setoid

    -- left cancellation of b
    b⁻¹bx : ∀ x → b ⁻¹ ∙ (b ∙ x) ≈ x
    b⁻¹bx x = begin
      b ⁻¹ ∙ (b ∙ x)  ≈⟨ assoc (b ⁻¹) b x ⟨
      (b ⁻¹ ∙ b) ∙ x  ≈⟨ ∙-congʳ (inverseˡ b) ⟩
      ε ∙ x           ≈⟨ identityˡ x ⟩
      x               ∎

    d : Carrier
    d = (b ∙ a) ∙ b ⁻¹

    d²≈ε : d ∙ d ≈ ε
    d²≈ε = begin
      ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹)
        ≈⟨ assoc (b ∙ a) (b ⁻¹) ((b ∙ a) ∙ b ⁻¹) ⟩
      (b ∙ a) ∙ (b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹))
        ≈⟨ ∙-congˡ (assoc (b ⁻¹) (b ∙ a) (b ⁻¹)) ⟨
      (b ∙ a) ∙ ((b ⁻¹ ∙ (b ∙ a)) ∙ b ⁻¹)
        ≈⟨ ∙-congˡ (∙-congʳ (b⁻¹bx a)) ⟩
      (b ∙ a) ∙ (a ∙ b ⁻¹)
        ≈⟨ assoc b a (a ∙ b ⁻¹) ⟩
      b ∙ (a ∙ (a ∙ b ⁻¹))
        ≈⟨ ∙-congˡ (assoc a a (b ⁻¹)) ⟨
      b ∙ ((a ∙ a) ∙ b ⁻¹)
        ≈⟨ ∙-congˡ (∙-congʳ a²≈ε) ⟩
      b ∙ (ε ∙ b ⁻¹)
        ≈⟨ ∙-congˡ (identityˡ (b ⁻¹)) ⟩
      b ∙ b ⁻¹
        ≈⟨ inverseʳ b ⟩
      ε ∎

    d≈ε⇒a≈ε : d ≈ ε → a ≈ ε
    d≈ε⇒a≈ε d≈ε = begin
      a               ≈⟨ b⁻¹bx a ⟨
      b ⁻¹ ∙ (b ∙ a)  ≈⟨ ∙-congˡ ba≈b ⟩
      b ⁻¹ ∙ b        ≈⟨ inverseˡ b ⟩
      ε               ∎
      where
      ba≈b : b ∙ a ≈ b
      ba≈b = begin
        b ∙ a                 ≈⟨ identityʳ (b ∙ a) ⟨
        (b ∙ a) ∙ ε           ≈⟨ ∙-congˡ (inverseˡ b) ⟨
        (b ∙ a) ∙ (b ⁻¹ ∙ b)  ≈⟨ assoc (b ∙ a) (b ⁻¹) b ⟨
        ((b ∙ a) ∙ b ⁻¹) ∙ b  ≈⟨ ∙-congʳ d≈ε ⟩
        ε ∙ b                 ≈⟨ identityˡ b ⟩
        b                     ∎

    result : (b ∙ a) ∙ b ⁻¹ ≈ a
    result with unique d d²≈ε
    ... | inj₁ d≈ε = contradiction (d≈ε⇒a≈ε d≈ε) a≉ε
    ... | inj₂ d≈a = d≈a
