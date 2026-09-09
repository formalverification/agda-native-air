-- Overture-lower-lift.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Overture-lower-lift.agda
--
-- Benchmark obligation: algebras-overture-lower-lift
-- Difficulty: routine
-- Source: Overture.Basic (agda-algebras)
-- Import stratum: using
-- Strategy: refl
--
module Overture-lower-lift where

open import AgdaDojang.Debug

open import Agda.Primitive  using ( Level )
open import Level           using ( lift ; lower )
open import Function.Base   using ( _∘_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

open import Overture.Basic  using ( 𝑖𝑑 )

lower∼lift : {a b : Level} {A : Set a} → lower {a}{b} ∘ lift ≡ 𝑖𝑑 A
lower∼lift = {!!}
