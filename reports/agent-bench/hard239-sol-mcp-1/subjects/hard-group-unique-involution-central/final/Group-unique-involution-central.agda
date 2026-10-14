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
open import Data.Sum.Base using ( inj₁; inj₂ )
open import Data.Empty using ( ⊥-elim )
import Relation.Binary.Reasoning.Setoid as Reasoning

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b = conclude (unique q square)
    where
    open Reasoning (setoid)

    q : Carrier
    q = (b ∙ a) ∙ b ⁻¹

    qb : q ∙ b ≈ b ∙ a
    qb = begin
      q ∙ b ≈⟨ assoc (b ∙ a) (b ⁻¹) b ⟩
      (b ∙ a) ∙ ((b ⁻¹) ∙ b) ≈⟨ ∙-cong refl (inverseˡ b) ⟩
      (b ∙ a) ∙ ε ≈⟨ identityʳ (b ∙ a) ⟩
      b ∙ a ∎

    square : q ∙ q ≈ ε
    square = begin
      q ∙ q ≈⟨ sym (assoc q (b ∙ a) (b ⁻¹)) ⟩
      (q ∙ (b ∙ a)) ∙ b ⁻¹ ≈⟨ ∙-cong (sym (assoc q b a)) refl ⟩
      ((q ∙ b) ∙ a) ∙ b ⁻¹ ≈⟨ ∙-cong (∙-cong qb refl) refl ⟩
      ((b ∙ a) ∙ a) ∙ b ⁻¹ ≈⟨ ∙-cong (assoc b a a) refl ⟩
      (b ∙ (a ∙ a)) ∙ b ⁻¹ ≈⟨ ∙-cong (∙-cong refl a²≈ε) refl ⟩
      (b ∙ ε) ∙ b ⁻¹ ≈⟨ ∙-cong (identityʳ b) refl ⟩
      b ∙ b ⁻¹ ≈⟨ inverseʳ b ⟩
      ε ∎

    nontrivial : ¬ (q ≈ ε)
    nontrivial q≈ε = a≉ε (begin
      a ≈⟨ sym (identityˡ a) ⟩
      ε ∙ a ≈⟨ ∙-cong (sym (inverseˡ b)) refl ⟩
      ((b ⁻¹) ∙ b) ∙ a ≈⟨ assoc (b ⁻¹) b a ⟩
      (b ⁻¹) ∙ (b ∙ a) ≈⟨ ∙-cong refl (trans (sym qb) (trans (∙-cong q≈ε refl) (identityˡ b))) ⟩
      (b ⁻¹) ∙ b ≈⟨ inverseˡ b ⟩
      ε ∎)

    conclude : q ≈ ε ⊎ q ≈ a → q ≈ a
    conclude (inj₁ q≈ε) = ⊥-elim (nontrivial q≈ε)
    conclude (inj₂ q≈a) = q≈a
