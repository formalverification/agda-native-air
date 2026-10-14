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
  unique-involution-central a a²≈ε a≉ε unique b = conclude (unique x square)
    where
    open Reasoning setoid

    x : Carrier
    x = (b ∙ a) ∙ b ⁻¹

    middle : ∀ u v → (u ∙ b ⁻¹) ∙ (b ∙ v) ≈ u ∙ v
    middle u v = begin
      (u ∙ b ⁻¹) ∙ (b ∙ v) ≈⟨ assoc u (b ⁻¹) (b ∙ v) ⟩
      u ∙ (b ⁻¹ ∙ (b ∙ v)) ≈⟨ ∙-cong refl (sym (assoc (b ⁻¹) b v)) ⟩
      u ∙ ((b ⁻¹ ∙ b) ∙ v) ≈⟨ ∙-cong refl (∙-cong (inverseˡ b) refl) ⟩
      u ∙ (ε ∙ v) ≈⟨ ∙-cong refl (identityˡ v) ⟩
      u ∙ v ∎

    square : x ∙ x ≈ ε
    square = begin
      x ∙ x ≈⟨ ∙-cong refl (assoc b a (b ⁻¹)) ⟩
      x ∙ (b ∙ (a ∙ b ⁻¹)) ≈⟨ middle (b ∙ a) (a ∙ b ⁻¹) ⟩
      (b ∙ a) ∙ (a ∙ b ⁻¹) ≈⟨ assoc b a (a ∙ b ⁻¹) ⟩
      b ∙ (a ∙ (a ∙ b ⁻¹)) ≈⟨ ∙-cong refl (sym (assoc a a (b ⁻¹))) ⟩
      b ∙ ((a ∙ a) ∙ b ⁻¹) ≈⟨ ∙-cong refl (∙-cong a²≈ε refl) ⟩
      b ∙ (ε ∙ b ⁻¹) ≈⟨ ∙-cong refl (identityˡ (b ⁻¹)) ⟩
      b ∙ b ⁻¹ ≈⟨ inverseʳ b ⟩
      ε ∎

    nontrivial : ¬ (x ≈ ε)
    nontrivial p = a≉ε (begin
      a ≈⟨ sym (identityˡ a) ⟩
      ε ∙ a ≈⟨ ∙-cong (sym (inverseˡ b)) refl ⟩
      (b ⁻¹ ∙ b) ∙ a ≈⟨ assoc (b ⁻¹) b a ⟩
      b ⁻¹ ∙ (b ∙ a) ≈⟨ ∙-cong refl (sym recover) ⟩
      b ⁻¹ ∙ (x ∙ b) ≈⟨ ∙-cong refl (∙-cong p refl) ⟩
      b ⁻¹ ∙ (ε ∙ b) ≈⟨ ∙-cong refl (identityˡ b) ⟩
      b ⁻¹ ∙ b ≈⟨ inverseˡ b ⟩
      ε ∎)
      where
      recover : x ∙ b ≈ b ∙ a
      recover = begin
        x ∙ b ≈⟨ assoc (b ∙ a) (b ⁻¹) b ⟩
        (b ∙ a) ∙ (b ⁻¹ ∙ b) ≈⟨ ∙-cong refl (inverseˡ b) ⟩
        (b ∙ a) ∙ ε ≈⟨ identityʳ (b ∙ a) ⟩
        b ∙ a ∎

    conclude : x ≈ ε ⊎ x ≈ a → x ≈ a
    conclude (inj₁ p) = ⊥-elim (nontrivial p)
    conclude (inj₂ p) = p
