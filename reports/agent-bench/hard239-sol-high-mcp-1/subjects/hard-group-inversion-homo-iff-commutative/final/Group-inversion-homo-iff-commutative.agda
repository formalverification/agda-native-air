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

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupMorphisms rawGroup rawGroup using ( IsGroupHomomorphism )
  open import Algebra.Properties.Group G
    using ( ⁻¹-injective; ⁻¹-anti-homo-∙; ε⁻¹≈ε )

  inversion-homo-iff-commutative
    :  (IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_) × (Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹)
  inversion-homo-iff-commutative =
    (λ h x y → ⁻¹-injective
      (trans (IsGroupHomomorphism.homo h x y)
             (sym (⁻¹-anti-homo-∙ y x))))
    ,
    (λ comm → record
      { isMonoidHomomorphism = record
        { isMagmaHomomorphism = record
          { isRelHomomorphism = record { cong = ⁻¹-cong }
          ; homo = λ x y → trans (⁻¹-anti-homo-∙ x y)
                                 (comm (y ⁻¹) (x ⁻¹))
          }
        ; ε-homo = ε⁻¹≈ε
        }
      ; ⁻¹-homo = λ x → refl
      })
