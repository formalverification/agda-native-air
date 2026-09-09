-- Overture-lift-lower.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Overture-lift-lower.agda
--
-- Benchmark obligation: algebras-overture-lift-lower
-- Difficulty: routine (Tier 1)
-- Source: Overture.Basic (agda-algebras)
-- Strategy: refl (lift and lower cancel definitionally)
--
module Overture-lift-lower where

open import AgdaDojang.Debug

open import Agda.Primitive  using ( Level )
open import Level           using ( Lift ; lift ; lower )
open import Function.Base   using ( _∘_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

open import Overture.Basic  using ( 𝑖𝑑 )

lift∼lower : {a b : Level} {A : Set a} → lift ∘ lower ≡ 𝑖𝑑 (Lift b A)
lift∼lower = refl
