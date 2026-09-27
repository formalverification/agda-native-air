-- Group-injective-iff-trivial-kernel.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/gold/Group-injective-iff-trivial-kernel.agda
--
-- Benchmark obligation: hard-group-injective-iff-trivial-kernel
-- Difficulty: non-obvious
-- Source: exam genre; Algebra.Morphism.Structures, Function.Definitions
-- Import stratum: novel
-- Strategy: kernel trivial ⇒ injective: f (x ∙ y ⁻¹) ≈ ε; injective ⇒ kernel trivial: f x ≈ ε ≈ f ε
--
-- A group homomorphism is injective if and only if its kernel is trivial.
--
-- GOLD WANTED
module Group-injective-iff-trivial-kernel where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )
open import Algebra.Morphism.Structures using ( module GroupMorphisms )
open import Function.Definitions      using ( Injective )
open import Data.Product.Base         using ( _×_ )

module _ {c₁ ℓ₁ c₂ ℓ₂ : Level} (G : Group c₁ ℓ₁) (H : Group c₂ ℓ₂) where
  open Group G renaming ( Carrier to A ; _≈_ to _≈₁_ ; ε to ε₁ )
  open Group H renaming ( Carrier to B ; _≈_ to _≈₂_ ; ε to ε₂ )
  open GroupMorphisms (Group.rawGroup G) (Group.rawGroup H) using ( IsGroupHomomorphism )

  injective-iff-trivial-kernel
    :  (f : A → B) → IsGroupHomomorphism f
    →  (Injective _≈₁_ _≈₂_ f → ∀ x → f x ≈₂ ε₂ → x ≈₁ ε₁) × ((∀ x → f x ≈₂ ε₂ → x ≈₁ ε₁) → Injective _≈₁_ _≈₂_ f)
  injective-iff-trivial-kernel f hom = {!!}
