-- Group-surjective-image-commutative.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-surjective-image-commutative.agda
--
-- Benchmark obligation: hard-group-surjective-image-commutative
-- Difficulty: compositional
-- Source: exam genre; Algebra.Morphism.Structures, Function.Definitions
-- Import stratum: novel
-- Strategy: pull two elements of H back along the surjection and push commutativity through the homomorphism law
--
-- The image of a commutative group under a surjective homomorphism is commutative.
--
module Group-surjective-image-commutative where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )
open import Algebra.Morphism.Structures using ( module GroupMorphisms )
open import Function.Definitions      using ( Surjective )
open import Data.Product.Base         using ( proj₁ ; proj₂ )

module _ {c₁ ℓ₁ c₂ ℓ₂ : Level} (G : Group c₁ ℓ₁) (H : Group c₂ ℓ₂) where
  open Group G renaming ( Carrier to A ; _≈_ to _≈₁_ ; _∙_ to _∙₁_ )
  open Group H renaming ( Carrier to B ; _≈_ to _≈₂_ ; _∙_ to _∙₂_ )
  open GroupMorphisms (Group.rawGroup G) (Group.rawGroup H) using ( IsGroupHomomorphism )

  surjective-image-commutative
    :  (f : A → B) → IsGroupHomomorphism f → Surjective _≈₁_ _≈₂_ f
    →  Commutative _≈₁_ _∙₁_ → Commutative _≈₂_ _∙₂_
  surjective-image-commutative f hom sur comm x y =
      trans₂ (sym₂ (∙-cong₂ pa pb))
        (trans₂ (sym₂ (homo a b))
          (trans₂ (⟦⟧-cong (comm a b))
            (trans₂ (homo b a) (∙-cong₂ pb pa))))
    where
    open Group G using () renaming ( refl to refl₁ )
    open Group H using () renaming ( sym to sym₂ ; trans to trans₂ ; ∙-cong to ∙-cong₂ )
    open IsGroupHomomorphism hom using ( homo ; ⟦⟧-cong )

    a : A
    a = proj₁ (sur x)

    pa : f a ≈₂ x
    pa = proj₂ (sur x) refl₁

    b : A
    b = proj₁ (sur y)

    pb : f b ≈₂ y
    pb = proj₂ (sur y) refl₁
