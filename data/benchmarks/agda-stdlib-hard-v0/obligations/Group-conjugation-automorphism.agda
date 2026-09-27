-- Group-conjugation-automorphism.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-conjugation-automorphism.agda
--
-- Benchmark obligation: hard-group-conjugation-automorphism
-- Difficulty: compositional
-- Source: exam genre; Algebra.Morphism.Structures (IsGroupIsomorphism over rawGroup)
-- Import stratum: novel
-- Strategy: the three morphism laws are equational; injective by cancellation, surjective by the inverse conjugate
--
-- Conjugation by a fixed g is an automorphism of the group.
--
module Group-conjugation-automorphism where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )
open import Algebra.Morphism.Structures using ( module GroupMorphisms )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G
  open GroupMorphisms rawGroup rawGroup using ( IsGroupIsomorphism )

  conjugation-automorphism : (g : Carrier) → IsGroupIsomorphism (λ x → (g ∙ x) ∙ g ⁻¹)
  conjugation-automorphism g = {!!}
