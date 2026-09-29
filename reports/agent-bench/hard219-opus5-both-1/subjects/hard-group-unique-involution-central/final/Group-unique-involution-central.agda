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

open import Data.Sum.Base                    using ( inj₁ ; inj₂ )
open import Relation.Nullary.Negation        using ( contradiction )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open import Algebra.Properties.Group G
    using ( inverseˡ-unique ; ⁻¹-involutive ; ∙-cancelˡ )
  open import Relation.Binary.Reasoning.Setoid setoid

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b = result
    where
    conj-∙ : ∀ x y → ((b ∙ x) ∙ b ⁻¹) ∙ ((b ∙ y) ∙ b ⁻¹) ≈ (b ∙ (x ∙ y)) ∙ b ⁻¹
    conj-∙ x y = begin
      ((b ∙ x) ∙ b ⁻¹) ∙ ((b ∙ y) ∙ b ⁻¹)  ≈⟨ assoc (b ∙ x) (b ⁻¹) ((b ∙ y) ∙ b ⁻¹) ⟩
      (b ∙ x) ∙ (b ⁻¹ ∙ ((b ∙ y) ∙ b ⁻¹))  ≈⟨ ∙-congˡ (∙-congˡ (assoc b y (b ⁻¹))) ⟩
      (b ∙ x) ∙ (b ⁻¹ ∙ (b ∙ (y ∙ b ⁻¹)))  ≈⟨ ∙-congˡ (assoc (b ⁻¹) b (y ∙ b ⁻¹)) ⟨
      (b ∙ x) ∙ ((b ⁻¹ ∙ b) ∙ (y ∙ b ⁻¹))  ≈⟨ ∙-congˡ (∙-congʳ (inverseˡ b)) ⟩
      (b ∙ x) ∙ (ε ∙ (y ∙ b ⁻¹))           ≈⟨ ∙-congˡ (identityˡ (y ∙ b ⁻¹)) ⟩
      (b ∙ x) ∙ (y ∙ b ⁻¹)                 ≈⟨ assoc (b ∙ x) y (b ⁻¹) ⟨
      ((b ∙ x) ∙ y) ∙ b ⁻¹                 ≈⟨ ∙-congʳ (assoc b x y) ⟩
      (b ∙ (x ∙ y)) ∙ b ⁻¹                 ∎

    conj²≈ε : ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹) ≈ ε
    conj²≈ε = begin
      ((b ∙ a) ∙ b ⁻¹) ∙ ((b ∙ a) ∙ b ⁻¹)  ≈⟨ conj-∙ a a ⟩
      (b ∙ (a ∙ a)) ∙ b ⁻¹                 ≈⟨ ∙-congʳ (∙-congˡ a²≈ε) ⟩
      (b ∙ ε) ∙ b ⁻¹                       ≈⟨ ∙-congʳ (identityʳ b) ⟩
      b ∙ b ⁻¹                             ≈⟨ inverseʳ b ⟩
      ε                                    ∎

    conj≈ε⇒a≈ε : (b ∙ a) ∙ b ⁻¹ ≈ ε → a ≈ ε
    conj≈ε⇒a≈ε h = ∙-cancelˡ b a ε (begin
      b ∙ a    ≈⟨ inverseˡ-unique (b ∙ a) (b ⁻¹) h ⟩
      b ⁻¹ ⁻¹  ≈⟨ ⁻¹-involutive b ⟩
      b        ≈⟨ identityʳ b ⟨
      b ∙ ε    ∎)

    result : (b ∙ a) ∙ b ⁻¹ ≈ a
    result with unique ((b ∙ a) ∙ b ⁻¹) conj²≈ε
    ... | inj₁ conj≈ε = contradiction (conj≈ε⇒a≈ε conj≈ε) a≉ε
    ... | inj₂ conj≈a = conj≈a
