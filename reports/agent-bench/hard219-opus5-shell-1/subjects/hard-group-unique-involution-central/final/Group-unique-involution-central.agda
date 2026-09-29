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
import Relation.Binary.Reasoning.Setoid as SetoidReasoning

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open SetoidReasoning setoid

  private
    cancelˡ′ : ∀ x y → x ⁻¹ ∙ (x ∙ y) ≈ y
    cancelˡ′ x y = begin
      x ⁻¹ ∙ (x ∙ y)  ≈⟨ assoc (x ⁻¹) x y ⟨
      (x ⁻¹ ∙ x) ∙ y  ≈⟨ ∙-congʳ (inverseˡ x) ⟩
      ε ∙ y           ≈⟨ identityˡ y ⟩
      y               ∎

    cancelʳ′ : ∀ x y → (y ∙ x ⁻¹) ∙ x ≈ y
    cancelʳ′ x y = begin
      (y ∙ x ⁻¹) ∙ x  ≈⟨ assoc y (x ⁻¹) x ⟩
      y ∙ (x ⁻¹ ∙ x)  ≈⟨ ∙-congˡ (inverseˡ x) ⟩
      y ∙ ε           ≈⟨ identityʳ y ⟩
      y               ∎

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b = resolve (unique bab bab²≈ε)
    where
    bab : Carrier
    bab = (b ∙ a) ∙ b ⁻¹

    bab²≈ε : bab ∙ bab ≈ ε
    bab²≈ε = begin
      ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹)
        ≈⟨ ∙-cong (assoc b a (b ⁻¹)) (assoc b a (b ⁻¹)) ⟩
      (b ∙ (a ∙ b ⁻¹)) ∙ (b ∙ (a ∙ b ⁻¹))
        ≈⟨ assoc b (a ∙ b ⁻¹) (b ∙ (a ∙ b ⁻¹)) ⟩
      b ∙ ((a ∙ b ⁻¹) ∙ (b ∙ (a ∙ b ⁻¹)))
        ≈⟨ ∙-congˡ (assoc a (b ⁻¹) (b ∙ (a ∙ b ⁻¹))) ⟩
      b ∙ (a ∙ (b ⁻¹ ∙ (b ∙ (a ∙ b ⁻¹))))
        ≈⟨ ∙-congˡ (∙-congˡ (cancelˡ′ b (a ∙ b ⁻¹))) ⟩
      b ∙ (a ∙ (a ∙ b ⁻¹))
        ≈⟨ ∙-congˡ (assoc a a (b ⁻¹)) ⟨
      b ∙ ((a ∙ a) ∙ b ⁻¹)
        ≈⟨ ∙-congˡ (∙-congʳ a²≈ε) ⟩
      b ∙ (ε ∙ b ⁻¹)
        ≈⟨ ∙-congˡ (identityˡ (b ⁻¹)) ⟩
      b ∙ b ⁻¹
        ≈⟨ inverseʳ b ⟩
      ε ∎

    bab≈ε⇒a≈ε : bab ≈ ε → a ≈ ε
    bab≈ε⇒a≈ε bab≈ε = begin
      a                              ≈⟨ cancelˡ′ b a ⟨
      b ⁻¹ ∙ (b ∙ a)                 ≈⟨ ∙-congˡ (cancelʳ′ b (b ∙ a)) ⟨
      b ⁻¹ ∙ (((b ∙ a) ∙ b ⁻¹) ∙ b)  ≈⟨ ∙-congˡ (∙-congʳ bab≈ε) ⟩
      b ⁻¹ ∙ (ε ∙ b)                 ≈⟨ ∙-congˡ (identityˡ b) ⟩
      b ⁻¹ ∙ b                       ≈⟨ inverseˡ b ⟩
      ε                              ∎

    resolve : bab ≈ ε ⊎ bab ≈ a → bab ≈ a
    resolve (inj₁ bab≈ε) = ⊥-elim (a≉ε (bab≈ε⇒a≈ε bab≈ε))
    resolve (inj₂ bab≈a) = bab≈a
