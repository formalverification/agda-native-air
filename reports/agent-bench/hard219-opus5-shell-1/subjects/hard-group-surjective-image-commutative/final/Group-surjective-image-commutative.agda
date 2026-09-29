-- Group-surjective-image-commutative.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-surjective-image-commutative.agda
--
-- Benchmark obligation: hard-group-surjective-image-commutative
-- Difficulty: compositional
-- Import stratum: novel
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
    GH.trans (GH.∙-cong (GH.sym fa≈x) (GH.sym fb≈y))
      (GH.trans (GH.sym (homo a b))
        (GH.trans (⟦⟧-cong (comm a b))
          (GH.trans (homo b a) (GH.∙-cong fb≈y fa≈x))))
    where
    module GH = Group H
    module GG = Group G
    open IsGroupHomomorphism hom using ( homo ; ⟦⟧-cong )

    a : A
    a = proj₁ (sur x)

    b : A
    b = proj₁ (sur y)

    fa≈x : f a ≈₂ x
    fa≈x = proj₂ (sur x) GG.refl

    fb≈y : f b ≈₂ y
    fb≈y = proj₂ (sur y) GG.refl
