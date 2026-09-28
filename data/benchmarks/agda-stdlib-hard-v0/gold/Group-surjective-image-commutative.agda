-- Group-surjective-image-commutative.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/gold/Group-surjective-image-commutative.agda
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

module _ {c₁ ℓ₁ c₂ ℓ₂ : Level} (G : Group c₁ ℓ₁) (H : Group c₂ ℓ₂) where
  open Group G renaming ( Carrier to A ; _≈_ to _≈₁_ ; _∙_ to _∙₁_ )
  open Group H renaming ( Carrier to B ; _≈_ to _≈₂_ ; _∙_ to _∙₂_ )
  open GroupMorphisms (Group.rawGroup G) (Group.rawGroup H) using ( IsGroupHomomorphism )

  surjective-image-commutative
    :  (f : A → B) → IsGroupHomomorphism f → Surjective _≈₁_ _≈₂_ f
    →  Commutative _≈₁_ _∙₁_ → Commutative _≈₂_ _∙₂_
  surjective-image-commutative f hom sur comm u v = begin
    u ∙₂ v      ≈⟨ H.∙-cong fa≈u fb≈v ⟨
    f a ∙₂ f b  ≈⟨ homo a b ⟨
    f (a ∙₁ b)  ≈⟨ ⟦⟧-cong (comm a b) ⟩
    f (b ∙₁ a)  ≈⟨ homo b a ⟩
    f b ∙₂ f a  ≈⟨ H.∙-cong fb≈v fa≈u ⟩
    v ∙₂ u      ∎
    where
    module G = Group G
    module H = Group H
    open IsGroupHomomorphism hom                  using  ( homo ; ⟦⟧-cong )
    open import Data.Product.Base                 using  ( proj₁ ; proj₂ )
    open import Relation.Binary.Reasoning.Setoid H.setoid

    -- Pull u and v back along the surjection f.
    a b : A
    a = proj₁ (sur u)
    b = proj₁ (sur v)

    fa≈u : f a ≈₂ u
    fa≈u = proj₂ (sur u) G.refl

    fb≈v : f b ≈₂ v
    fb≈v = proj₂ (sur v) G.refl
