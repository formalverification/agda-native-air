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

  inversion-homo-iff-commutative
    :  (IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_) × (Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹)
  inversion-homo-iff-commutative = to , from
    where
    open import Algebra.Properties.Group G using ( ⁻¹-anti-homo-∙ ; ⁻¹-involutive ; ε⁻¹≈ε )
    open import Relation.Binary.Reasoning.Setoid setoid
    open IsGroupHomomorphism

    to : IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_
    to h x y = begin
      x ∙ y                 ≈⟨ ∙-cong (sym (⁻¹-involutive x)) (sym (⁻¹-involutive y)) ⟩
      x ⁻¹ ⁻¹ ∙ y ⁻¹ ⁻¹     ≈⟨ sym (homo h (x ⁻¹) (y ⁻¹)) ⟩
      (x ⁻¹ ∙ y ⁻¹) ⁻¹      ≈⟨ ⁻¹-anti-homo-∙ (x ⁻¹) (y ⁻¹) ⟩
      y ⁻¹ ⁻¹ ∙ x ⁻¹ ⁻¹     ≈⟨ ∙-cong (⁻¹-involutive y) (⁻¹-involutive x) ⟩
      y ∙ x                 ∎

    from : Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹
    from comm = record
      { isMonoidHomomorphism = record
        { isMagmaHomomorphism = record
          { isRelHomomorphism = record { cong = ⁻¹-cong }
          ; homo = λ x y → trans (⁻¹-anti-homo-∙ x y) (comm (y ⁻¹) (x ⁻¹))
          }
        ; ε-homo = ε⁻¹≈ε
        }
      ; ⁻¹-homo = λ x → refl
      }
