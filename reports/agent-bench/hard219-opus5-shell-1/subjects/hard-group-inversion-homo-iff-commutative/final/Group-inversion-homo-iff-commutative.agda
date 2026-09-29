-- Group-inversion-homo-iff-commutative.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-inversion-homo-iff-commutative.agda
--
-- Benchmark obligation: hard-group-inversion-homo-iff-commutative
-- Difficulty: non-obvious
-- Import stratum: novel
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

open import Data.Product.Base         using ( _,_ )
import Algebra.Properties.Group
import Relation.Binary.Reasoning.Setoid

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupMorphisms rawGroup rawGroup using ( IsGroupHomomorphism )

  private
    open Algebra.Properties.Group G
      using ( ⁻¹-involutive ; ⁻¹-anti-homo-∙ ; ε⁻¹≈ε )
    open Relation.Binary.Reasoning.Setoid setoid

    forward : IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_
    forward hom x y = begin
      x ∙ y                      ≈⟨ ∙-cong (sym (⁻¹-involutive x)) (sym (⁻¹-involutive y)) ⟩
      (x ⁻¹) ⁻¹ ∙ (y ⁻¹) ⁻¹      ≈⟨ ⁻¹-anti-homo-∙ (y ⁻¹) (x ⁻¹) ⟨
      (y ⁻¹ ∙ x ⁻¹) ⁻¹           ≈⟨ IsGroupHomomorphism.homo hom (y ⁻¹) (x ⁻¹) ⟩
      (y ⁻¹) ⁻¹ ∙ (x ⁻¹) ⁻¹      ≈⟨ ∙-cong (⁻¹-involutive y) (⁻¹-involutive x) ⟩
      y ∙ x                      ∎

    backward : Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹
    backward comm = record
      { isMonoidHomomorphism = record
        { isMagmaHomomorphism = record
          { isRelHomomorphism = record { cong = ⁻¹-cong }
          ; homo = λ x y → trans (⁻¹-anti-homo-∙ x y) (comm (y ⁻¹) (x ⁻¹))
          }
        ; ε-homo = ε⁻¹≈ε
        }
      ; ⁻¹-homo = λ _ → refl
      }

  inversion-homo-iff-commutative
    :  (IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_) × (Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹)
  inversion-homo-iff-commutative = forward , backward
