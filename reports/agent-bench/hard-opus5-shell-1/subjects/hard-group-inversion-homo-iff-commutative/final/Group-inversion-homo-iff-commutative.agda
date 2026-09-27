-- Group-inversion-homo-iff-commutative.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-inversion-homo-iff-commutative.agda
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
open import Data.Product.Base         using ( _×_ ; _,_ )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupMorphisms rawGroup rawGroup using ( IsGroupHomomorphism )

  open import Algebra.Properties.Group G
    using ( ⁻¹-involutive ; ⁻¹-anti-homo-∙ ; ε⁻¹≈ε )
  open import Relation.Binary.Reasoning.Setoid setoid

  inversion-homo-iff-commutative
    :  (IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_) × (Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹)
  inversion-homo-iff-commutative = homo⇒comm , comm⇒homo
    where
    homo⇒comm : IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_
    homo⇒comm H x y = begin
      x ∙ y                  ≈⟨ ∙-cong (⁻¹-involutive x) (⁻¹-involutive y) ⟨
      x ⁻¹ ⁻¹ ∙ y ⁻¹ ⁻¹      ≈⟨ IsGroupHomomorphism.homo H (x ⁻¹) (y ⁻¹) ⟨
      (x ⁻¹ ∙ y ⁻¹) ⁻¹       ≈⟨ ⁻¹-anti-homo-∙ (x ⁻¹) (y ⁻¹) ⟩
      y ⁻¹ ⁻¹ ∙ x ⁻¹ ⁻¹      ≈⟨ ∙-cong (⁻¹-involutive y) (⁻¹-involutive x) ⟩
      y ∙ x                  ∎

    comm⇒homo : Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹
    comm⇒homo comm = record
      { isMonoidHomomorphism = record
        { isMagmaHomomorphism = record
          { isRelHomomorphism = record { cong = ⁻¹-cong }
          ; homo = λ x y → trans (⁻¹-anti-homo-∙ x y) (comm (y ⁻¹) (x ⁻¹))
          }
        ; ε-homo = ε⁻¹≈ε
        }
      ; ⁻¹-homo = λ x → refl
      }
