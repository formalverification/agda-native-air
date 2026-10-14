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

import Algebra.Properties.Group
open import Data.Sum.Base using (inj₁; inj₂)
open import Data.Empty using (⊥-elim)

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  unique-involution-central
    :  (a : Carrier) → a ∙ a ≈ ε → ¬ (a ≈ ε)
    →  (∀ b → b ∙ b ≈ ε → b ≈ ε ⊎ b ≈ a)
    →  ∀ b → (b ∙ a) ∙ b ⁻¹ ≈ a
  unique-involution-central a a²≈ε a≉ε unique b =
    choose (unique t t²≈ε)
    where
    open Algebra.Properties.Group G
      using (∙-cancelˡ; x∙y⁻¹≈ε⇒x≈y)
    open import Relation.Binary.Reasoning.Setoid setoid

    t : Carrier
    t = (b ∙ a) ∙ b ⁻¹

    undo-left : b ⁻¹ ∙ (b ∙ a) ≈ a
    undo-left = begin
      b ⁻¹ ∙ (b ∙ a) ≈⟨ sym (assoc (b ⁻¹) b a) ⟩
      (b ⁻¹ ∙ b) ∙ a ≈⟨ ∙-congʳ (inverseˡ b) ⟩
      ε ∙ a           ≈⟨ identityˡ a ⟩
      a               ∎

    t²≈ε : t ∙ t ≈ ε
    t²≈ε = begin
      t ∙ t
        ≈⟨ assoc (b ∙ a) (b ⁻¹) t ⟩
      (b ∙ a) ∙ (b ⁻¹ ∙ ((b ∙ a) ∙ b ⁻¹))
        ≈⟨ ∙-congˡ (sym (assoc (b ⁻¹) (b ∙ a) (b ⁻¹))) ⟩
      (b ∙ a) ∙ ((b ⁻¹ ∙ (b ∙ a)) ∙ b ⁻¹)
        ≈⟨ ∙-congˡ (∙-congʳ undo-left) ⟩
      (b ∙ a) ∙ (a ∙ b ⁻¹)
        ≈⟨ sym (assoc (b ∙ a) a (b ⁻¹)) ⟩
      ((b ∙ a) ∙ a) ∙ b ⁻¹
        ≈⟨ ∙-congʳ (assoc b a a) ⟩
      (b ∙ (a ∙ a)) ∙ b ⁻¹
        ≈⟨ ∙-congʳ (∙-congˡ a²≈ε) ⟩
      (b ∙ ε) ∙ b ⁻¹
        ≈⟨ ∙-congʳ (identityʳ b) ⟩
      b ∙ b ⁻¹
        ≈⟨ inverseʳ b ⟩
      ε ∎

    choose : t ≈ ε ⊎ t ≈ a → t ≈ a
    choose (inj₁ t≈ε) = ⊥-elim (a≉ε
      (∙-cancelˡ b a ε
        (trans (x∙y⁻¹≈ε⇒x≈y (b ∙ a) b t≈ε)
               (sym (identityʳ b)))))
    choose (inj₂ t≈a) = t≈a
