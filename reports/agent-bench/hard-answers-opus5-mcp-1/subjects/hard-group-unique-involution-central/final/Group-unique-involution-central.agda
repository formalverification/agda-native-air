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

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open import Algebra.Properties.Group G
  open import Relation.Binary.Reasoning.Setoid setoid

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b =
    conclude (unique ((b ∙ a) ∙ b ⁻¹) k²≈ε)
    where
    k²≈ε : ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹) ≈ ε
    k²≈ε = begin
      ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹)
        ≈⟨ assoc (b ∙ a) (b ⁻¹) ((b ∙ a) ∙ b ⁻¹) ⟩
      (b ∙ a) ∙ (b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹))
        ≈⟨ ∙-congˡ (assoc (b ⁻¹) (b ∙ a) (b ⁻¹)) ⟨
      (b ∙ a) ∙ ((b ⁻¹ ∙ (b ∙ a)) ∙ b ⁻¹)
        ≈⟨ ∙-congˡ (∙-congʳ (\\-leftDividesʳ b a)) ⟩
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

    k≈ε⇒a≈ε : (b ∙ a) ∙ b ⁻¹ ≈ ε → a ≈ ε
    k≈ε⇒a≈ε eq = ∙-cancelˡ b a ε (begin
      b ∙ a                 ≈⟨ //-rightDividesˡ b (b ∙ a) ⟨
      ((b ∙ a) ∙ b ⁻¹) ∙ b  ≈⟨ ∙-congʳ eq ⟩
      ε ∙ b                 ≈⟨ identityˡ b ⟩
      b                     ≈⟨ identityʳ b ⟨
      b ∙ ε                 ∎)

    conclude : (b ∙ a) ∙ b ⁻¹ ≈ ε ⊎ (b ∙ a) ∙ b ⁻¹ ≈ a → (b ∙ a) ∙ b ⁻¹ ≈ a
    conclude (inj₁ eq) = contradiction (k≈ε⇒a≈ε eq) a≉ε
    conclude (inj₂ eq) = eq
