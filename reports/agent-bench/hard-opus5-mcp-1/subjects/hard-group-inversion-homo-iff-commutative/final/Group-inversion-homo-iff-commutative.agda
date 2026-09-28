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
open import Data.Product.Base         using ( _×_ )

open import Data.Product.Base         using ( _,_ )
import Algebra.Properties.Group as GroupProperties

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupMorphisms rawGroup rawGroup using ( IsGroupHomomorphism )

  open GroupProperties G using ( ⁻¹-anti-homo-∙ ; ⁻¹-involutive ; ε⁻¹≈ε )

  private
    homo⇒comm : IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_
    homo⇒comm h x y =
      trans (sym (trans (homo (x ⁻¹) (y ⁻¹))
                        (∙-cong (⁻¹-involutive x) (⁻¹-involutive y))))
            (trans (⁻¹-anti-homo-∙ (x ⁻¹) (y ⁻¹))
                   (∙-cong (⁻¹-involutive y) (⁻¹-involutive x)))
      where open IsGroupHomomorphism h using ( homo )

    comm⇒homo : Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹
    comm⇒homo comm = record
      { isMonoidHomomorphism = record
          { isMagmaHomomorphism = record
              { isRelHomomorphism = record { cong = ⁻¹-cong }
              ; homo              = λ x y →
                  trans (⁻¹-anti-homo-∙ x y) (comm (y ⁻¹) (x ⁻¹))
              }
          ; ε-homo = ε⁻¹≈ε
          }
      ; ⁻¹-homo = λ _ → refl
      }

  inversion-homo-iff-commutative
    :  (IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_) × (Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹)
  inversion-homo-iff-commutative = homo⇒comm , comm⇒homo
