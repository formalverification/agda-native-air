-- Group-inversion-homo-iff-commutative.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/gold/Group-inversion-homo-iff-commutative.agda
--
-- Benchmark obligation: hard-group-inversion-homo-iff-commutative
-- Difficulty: non-obvious
-- Source: exam genre; Algebra.Morphism.Structures
-- Import stratum: novel
-- Strategy: both directions; the homomorphism law for _⁻¹ is exactly (x ∙ y) ⁻¹ ≈ x ⁻¹ ∙ y ⁻¹
--
-- Inversion is a group homomorphism G → G if and only if the group is commutative.
--
-- GOLD WANTED
module Group-inversion-homo-iff-commutative where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )
open import Algebra.Morphism.Structures using ( module GroupMorphisms )
open import Data.Product.Base         using ( _×_ )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupMorphisms rawGroup rawGroup using ( IsGroupHomomorphism )

  inversion-homo-iff-commutative
    :  (IsGroupHomomorphism _⁻¹ → Commutative _≈_ _∙_) × (Commutative _≈_ _∙_ → IsGroupHomomorphism _⁻¹)
  inversion-homo-iff-commutative = {!!}
