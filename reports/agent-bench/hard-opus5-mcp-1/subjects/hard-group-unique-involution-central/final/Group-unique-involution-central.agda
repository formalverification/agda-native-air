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

open import Data.Sum.Base             using ( inj₁ ; inj₂ )
open import Relation.Nullary.Negation using ( contradiction )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open import Algebra.Properties.Group G
    using ( ∙-cancelˡ ; x∙y⁻¹≈ε⇒x≈y )
  open import Relation.Binary.Reasoning.Setoid setoid

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b = result
    where
    k : Carrier
    k = (b ∙ a) ∙ b ⁻¹

    cancel-b : ∀ x → b ⁻¹ ∙ (b ∙ x) ≈ x
    cancel-b x = begin
      b ⁻¹ ∙ (b ∙ x)  ≈⟨ assoc (b ⁻¹) b x ⟨
      (b ⁻¹ ∙ b) ∙ x  ≈⟨ ∙-congʳ (inverseˡ b) ⟩
      ε ∙ x           ≈⟨ identityˡ x ⟩
      x               ∎

    k²≈ε : k ∙ k ≈ ε
    k²≈ε = begin
      ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹)  ≈⟨ assoc (b ∙ a) (b ⁻¹) ((b ∙ a) ∙ b ⁻¹) ⟩
      (b ∙ a) ∙ (b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹))  ≈⟨ ∙-congˡ (assoc (b ⁻¹) (b ∙ a) (b ⁻¹)) ⟨
      (b ∙ a) ∙ ((b ⁻¹ ∙ (b ∙ a)) ∙ b ⁻¹)  ≈⟨ ∙-congˡ (∙-congʳ (cancel-b a)) ⟩
      (b ∙ a) ∙ (a ∙ b ⁻¹)                 ≈⟨ assoc b a (a ∙ b ⁻¹) ⟩
      b ∙ (a ∙ (a ∙ b ⁻¹))                 ≈⟨ ∙-congˡ (assoc a a (b ⁻¹)) ⟨
      b ∙ ((a ∙ a) ∙ b ⁻¹)                 ≈⟨ ∙-congˡ (∙-congʳ a²≈ε) ⟩
      b ∙ (ε ∙ b ⁻¹)                       ≈⟨ ∙-congˡ (identityˡ (b ⁻¹)) ⟩
      b ∙ b ⁻¹                             ≈⟨ inverseʳ b ⟩
      ε                                    ∎

    result : (b ∙ a) ∙ b ⁻¹ ≈ a
    result with unique k k²≈ε
    ... | inj₂ k≈a = k≈a
    ... | inj₁ k≈ε = contradiction
      (∙-cancelˡ b a ε (trans (x∙y⁻¹≈ε⇒x≈y (b ∙ a) b k≈ε) (sym (identityʳ b))))
      a≉ε
