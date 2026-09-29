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
  surjective-image-commutative f hom sur comm x y = pf
    where
    open IsGroupHomomorphism hom using ( homo ; ⟦⟧-cong )

    a : A
    a = proj₁ (sur x)

    fa : f a ≈₂ x
    fa = proj₂ (sur x) (Group.refl G)

    b : A
    b = proj₁ (sur y)

    fb : f b ≈₂ y
    fb = proj₂ (sur y) (Group.refl G)

    step₁ : f a ∙₂ f b ≈₂ x ∙₂ y
    step₁ = Group.∙-cong H fa fb

    step₂ : f (a ∙₁ b) ≈₂ f a ∙₂ f b
    step₂ = homo a b

    step₃ : f (a ∙₁ b) ≈₂ f (b ∙₁ a)
    step₃ = ⟦⟧-cong (comm a b)

    step₄ : f (b ∙₁ a) ≈₂ f b ∙₂ f a
    step₄ = homo b a

    step₅ : f b ∙₂ f a ≈₂ y ∙₂ x
    step₅ = Group.∙-cong H fb fa

    pf : x ∙₂ y ≈₂ y ∙₂ x
    pf = Group.trans H (Group.sym H step₁)
           (Group.trans H (Group.sym H step₂)
             (Group.trans H step₃ (Group.trans H step₄ step₅)))
