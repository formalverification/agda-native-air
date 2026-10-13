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

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b = result
    where
    open import Relation.Binary.Reasoning.Setoid setoid
    open import Data.Sum.Base using ( inj₁ ; inj₂ )
    open import Data.Empty using ( ⊥-elim )

    d : Carrier
    d = (b ∙ a) ∙ b ⁻¹

    step1 : b ⁻¹ ∙ d ≈ a ∙ b ⁻¹
    step1 = begin
      b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹)  ≈⟨ sym (assoc (b ⁻¹) (b ∙ a) (b ⁻¹)) ⟩
      (b ⁻¹ ∙ (b ∙ a)) ∙ b ⁻¹  ≈⟨ ∙-cong (sym (assoc (b ⁻¹) b a)) refl ⟩
      ((b ⁻¹ ∙ b) ∙ a) ∙ b ⁻¹  ≈⟨ ∙-cong (∙-cong (inverseˡ b) refl) refl ⟩
      (ε ∙ a) ∙ b ⁻¹           ≈⟨ ∙-cong (identityˡ a) refl ⟩
      a ∙ b ⁻¹                 ∎

    cc : d ∙ d ≈ ε
    cc = begin
      ((b ∙ a) ∙ b ⁻¹) ∙ d  ≈⟨ assoc (b ∙ a) (b ⁻¹) d ⟩
      (b ∙ a) ∙ (b ⁻¹ ∙ d)  ≈⟨ ∙-cong refl step1 ⟩
      (b ∙ a) ∙ (a ∙ b ⁻¹)  ≈⟨ assoc b a (a ∙ b ⁻¹) ⟩
      b ∙ (a ∙ (a ∙ b ⁻¹))  ≈⟨ ∙-cong refl (sym (assoc a a (b ⁻¹))) ⟩
      b ∙ ((a ∙ a) ∙ b ⁻¹)  ≈⟨ ∙-cong refl (∙-cong a²≈ε refl) ⟩
      b ∙ (ε ∙ b ⁻¹)        ≈⟨ ∙-cong refl (identityˡ (b ⁻¹)) ⟩
      b ∙ b ⁻¹              ≈⟨ inverseʳ b ⟩
      ε                     ∎

    c≉ε : ¬ (d ≈ ε)
    c≉ε c≈ε = a≉ε a≈ε
      where
      ba≈b : b ∙ a ≈ b
      ba≈b = begin
        b ∙ a                  ≈⟨ sym (identityʳ (b ∙ a)) ⟩
        (b ∙ a) ∙ ε            ≈⟨ ∙-cong refl (sym (inverseˡ b)) ⟩
        (b ∙ a) ∙ (b ⁻¹ ∙ b)  ≈⟨ sym (assoc (b ∙ a) (b ⁻¹) b) ⟩
        ((b ∙ a) ∙ b ⁻¹) ∙ b  ≈⟨ ∙-cong c≈ε refl ⟩
        ε ∙ b                  ≈⟨ identityˡ b ⟩
        b                      ∎

      a≈ε : a ≈ ε
      a≈ε = begin
        a               ≈⟨ sym (identityˡ a) ⟩
        ε ∙ a           ≈⟨ ∙-cong (sym (inverseˡ b)) refl ⟩
        (b ⁻¹ ∙ b) ∙ a ≈⟨ assoc (b ⁻¹) b a ⟩
        b ⁻¹ ∙ (b ∙ a) ≈⟨ ∙-cong refl ba≈b ⟩
        b ⁻¹ ∙ b        ≈⟨ inverseˡ b ⟩
        ε               ∎

    result : d ≈ a
    result with unique d cc
    ... | inj₁ c≈ε = ⊥-elim (c≉ε c≈ε)
    ... | inj₂ c≈a = c≈a
