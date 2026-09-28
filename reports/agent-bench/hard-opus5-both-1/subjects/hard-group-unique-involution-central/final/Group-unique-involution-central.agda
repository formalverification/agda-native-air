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

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open import Relation.Binary.Reasoning.Setoid setoid

  private
    cancelˡ-⁻¹ : ∀ x y → x ⁻¹ ∙ (x ∙ y) ≈ y
    cancelˡ-⁻¹ x y = begin
      x ⁻¹ ∙ (x ∙ y)  ≈⟨ sym (assoc (x ⁻¹) x y) ⟩
      (x ⁻¹ ∙ x) ∙ y  ≈⟨ ∙-congʳ (inverseˡ x) ⟩
      ε ∙ y           ≈⟨ identityˡ y ⟩
      y               ∎

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b = result
    where
      κ : Carrier
      κ = (b ∙ a) ∙ b ⁻¹

      κ²≈ε : κ ∙ κ ≈ ε
      κ²≈ε = begin
        ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹)
          ≈⟨ assoc (b ∙ a) (b ⁻¹) ((b ∙ a) ∙ b ⁻¹) ⟩
        (b ∙ a) ∙ (b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹))
          ≈⟨ ∙-congˡ (∙-congˡ (assoc b a (b ⁻¹))) ⟩
        (b ∙ a) ∙ (b ⁻¹ ∙ (b ∙ (a ∙ b ⁻¹)))
          ≈⟨ ∙-congˡ (cancelˡ-⁻¹ b (a ∙ b ⁻¹)) ⟩
        (b ∙ a) ∙ (a ∙ b ⁻¹)
          ≈⟨ assoc b a (a ∙ b ⁻¹) ⟩
        b ∙ (a ∙ (a ∙ b ⁻¹))
          ≈⟨ ∙-congˡ (sym (assoc a a (b ⁻¹))) ⟩
        b ∙ ((a ∙ a) ∙ b ⁻¹)
          ≈⟨ ∙-congˡ (∙-congʳ a²≈ε) ⟩
        b ∙ (ε ∙ b ⁻¹)
          ≈⟨ ∙-congˡ (identityˡ (b ⁻¹)) ⟩
        b ∙ b ⁻¹
          ≈⟨ inverseʳ b ⟩
        ε ∎

      refute : κ ≈ ε → a ≈ ε
      refute κ≈ε = begin
        a                             ≈⟨ sym (cancelˡ-⁻¹ b a) ⟩
        b ⁻¹ ∙ (b ∙ a)                ≈⟨ ∙-congˡ (sym (identityʳ (b ∙ a))) ⟩
        b ⁻¹ ∙ ((b ∙ a) ∙ ε)          ≈⟨ ∙-congˡ (∙-congˡ (sym (inverseˡ b))) ⟩
        b ⁻¹ ∙ ((b ∙ a) ∙ (b ⁻¹ ∙ b)) ≈⟨ ∙-congˡ (sym (assoc (b ∙ a) (b ⁻¹) b)) ⟩
        b ⁻¹ ∙ (((b ∙ a) ∙ b ⁻¹) ∙ b) ≈⟨ ∙-congˡ (∙-congʳ κ≈ε) ⟩
        b ⁻¹ ∙ (ε ∙ b)                ≈⟨ ∙-congˡ (identityˡ b) ⟩
        b ⁻¹ ∙ b                      ≈⟨ inverseˡ b ⟩
        ε ∎

      result : κ ≈ a
      result with unique κ κ²≈ε
      ... | inj₁ κ≈ε = ⊥-elim (a≉ε (refute κ≈ε))
      ... | inj₂ κ≈a = κ≈a
