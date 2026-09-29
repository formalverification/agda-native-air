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
import Relation.Binary.Reasoning.Setoid as ≈-Reasoning

module _ {c₁ ℓ₁ c₂ ℓ₂ : Level} (G : Group c₁ ℓ₁) (H : Group c₂ ℓ₂) where
  open Group G renaming ( Carrier to A ; _≈_ to _≈₁_ ; _∙_ to _∙₁_ )
  open Group H renaming ( Carrier to B ; _≈_ to _≈₂_ ; _∙_ to _∙₂_ )
  open GroupMorphisms (Group.rawGroup G) (Group.rawGroup H) using ( IsGroupHomomorphism )

  surjective-image-commutative
    :  (f : A → B) → IsGroupHomomorphism f → Surjective _≈₁_ _≈₂_ f
    →  Commutative _≈₁_ _∙₁_ → Commutative _≈₂_ _∙₂_
  surjective-image-commutative f hom sur comm x y = begin
    x ∙₂ y      ≈⟨ Group.∙-cong H (Group.sym H fa≈x) (Group.sym H fb≈y) ⟩
    f a ∙₂ f b  ≈⟨ IsGroupHomomorphism.homo hom a b ⟨
    f (a ∙₁ b)  ≈⟨ IsGroupHomomorphism.⟦⟧-cong hom (comm a b) ⟩
    f (b ∙₁ a)  ≈⟨ IsGroupHomomorphism.homo hom b a ⟩
    f b ∙₂ f a  ≈⟨ Group.∙-cong H fb≈y fa≈x ⟩
    y ∙₂ x      ∎
    where
      open ≈-Reasoning (Group.setoid H)

      a : A
      a = proj₁ (sur x)

      b : A
      b = proj₁ (sur y)

      fa≈x : f a ≈₂ x
      fa≈x = proj₂ (sur x) (Group.refl G)

      fb≈y : f b ≈₂ y
      fb≈y = proj₂ (sur y) (Group.refl G)
