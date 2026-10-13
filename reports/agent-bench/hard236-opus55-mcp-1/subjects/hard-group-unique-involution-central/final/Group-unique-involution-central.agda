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
open import Data.Empty using ( ⊥-elim )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b with unique conj c²≈ε
    where
    open import Relation.Binary.Reasoning.Setoid setoid
    conj : Carrier
    conj = (b ∙ a) ∙ b ⁻¹
    c²≈ε : conj ∙ conj ≈ ε
    c²≈ε = begin
      ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹)  ≈⟨ assoc _ _ _ ⟩
      (b ∙ a) ∙ (b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹))  ≈⟨ ∙-congˡ (sym (assoc _ _ _)) ⟩
      (b ∙ a) ∙ ((b ⁻¹ ∙ (b ∙ a)) ∙ b ⁻¹)  ≈⟨ ∙-congˡ (∙-congʳ (sym (assoc _ _ _))) ⟩
      (b ∙ a) ∙ (((b ⁻¹ ∙ b) ∙ a) ∙ b ⁻¹)  ≈⟨ ∙-congˡ (∙-congʳ (∙-congʳ (inverseˡ b))) ⟩
      (b ∙ a) ∙ ((ε ∙ a) ∙ b ⁻¹)  ≈⟨ ∙-congˡ (∙-congʳ (identityˡ a)) ⟩
      (b ∙ a) ∙ (a ∙ b ⁻¹)  ≈⟨ assoc _ _ _ ⟩
      b ∙ (a ∙ (a ∙ b ⁻¹))  ≈⟨ ∙-congˡ (sym (assoc _ _ _)) ⟩
      b ∙ ((a ∙ a) ∙ b ⁻¹)  ≈⟨ ∙-congˡ (∙-congʳ a²≈ε) ⟩
      b ∙ (ε ∙ b ⁻¹)  ≈⟨ ∙-congˡ (identityˡ _) ⟩
      b ∙ b ⁻¹  ≈⟨ inverseʳ b ⟩
      ε  ∎
  ... | inj₂ h = h
  ... | inj₁ h = ⊥-elim (a≉ε a≈ε)
    where
    open import Relation.Binary.Reasoning.Setoid setoid
    a≈ε : a ≈ ε
    a≈ε = begin
      a  ≈⟨ sym (identityˡ a) ⟩
      ε ∙ a  ≈⟨ ∙-congʳ (sym (inverseˡ b)) ⟩
      (b ⁻¹ ∙ b) ∙ a  ≈⟨ assoc _ _ _ ⟩
      b ⁻¹ ∙ (b ∙ a)  ≈⟨ ∙-congˡ (sym (identityʳ _)) ⟩
      b ⁻¹ ∙ ((b ∙ a) ∙ ε)  ≈⟨ ∙-congˡ (∙-congˡ (sym (inverseˡ b))) ⟩
      b ⁻¹ ∙ ((b ∙ a) ∙ (b ⁻¹ ∙ b))  ≈⟨ ∙-congˡ (sym (assoc _ _ _)) ⟩
      b ⁻¹ ∙ (((b ∙ a) ∙ b ⁻¹) ∙ b)  ≈⟨ ∙-congˡ (∙-congʳ h) ⟩
      b ⁻¹ ∙ (ε ∙ b)  ≈⟨ ∙-congˡ (identityˡ b) ⟩
      b ⁻¹ ∙ b  ≈⟨ inverseˡ b ⟩
      ε  ∎
