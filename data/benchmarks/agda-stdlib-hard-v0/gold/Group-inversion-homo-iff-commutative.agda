-- Group-inversion-homo-iff-commutative.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/gold/Group-inversion-homo-iff-commutative.agda
--
-- Benchmark obligation: hard-group-inversion-homo-iff-commutative
-- Difficulty: non-obvious
-- Source: exam genre; Algebra.Morphism.Structures
-- Import stratum: novel
-- Strategy: both directions; the homomorphism law for _⁻¹ is exactly (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹
--
-- Inversion is a group homomorphism G → G if and only if the group is commutative.
--
module Group-inversion-homo-iff-commutative where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )
open import Algebra.Morphism.Structures using ( module GroupMorphisms )
open import Data.Product.Base         using ( _×_ )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupMorphisms rawGroup rawGroup using ( IsGroupHomomorphism )

  inversion-homo-iff-commutative
    :  (IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_) × (Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹)
  inversion-homo-iff-commutative = homo⇒comm , comm⇒homo
    where
    open import Algebra.Properties.Group G using ( ε⁻¹≈ε ; ⁻¹-injective ; ⁻¹-anti-homo-∙ )
    open import Data.Product.Base          using ( _,_ )
    open import Relation.Binary.Reasoning.Setoid setoid

    -- (x ∙ y) ⁻¹ ≈ y ⁻¹ ∙ x ⁻¹ ≈ (y ∙ x) ⁻¹, and inversion is injective.
    homo⇒comm : IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_
    homo⇒comm h x y = ⁻¹-injective (begin
      (x ∙ y) ⁻¹   ≈⟨ ⁻¹-anti-homo-∙ x y ⟩
      y ⁻¹ ∙ x ⁻¹  ≈⟨ IsGroupHomomorphism.homo h y x ⟨
      (y ∙ x) ⁻¹   ∎)

    -- In a commutative group the anti-homomorphism law is the homomorphism law.
    ⁻¹-homo-∙ : Commutative _≈_ _∙_ → ∀ x y → (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹
    ⁻¹-homo-∙ comm x y = begin
      (x ∙ y) ⁻¹   ≈⟨ ⁻¹-anti-homo-∙ x y ⟩
      y ⁻¹ ∙ x ⁻¹  ≈⟨ comm (y ⁻¹) (x ⁻¹) ⟩
      x ⁻¹ ∙ y ⁻¹  ∎

    comm⇒homo : Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹
    comm⇒homo comm = record
      { isMonoidHomomorphism = record
        { isMagmaHomomorphism = record
          { isRelHomomorphism = record { cong = ⁻¹-cong }
          ; homo              = ⁻¹-homo-∙ comm
          }
        ; ε-homo = ε⁻¹≈ε
        }
      ; ⁻¹-homo = λ _ → refl
      }
