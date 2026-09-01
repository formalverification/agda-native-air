-- Inverses-image-f-f.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Inverses-image-f-f.agda
--
-- Benchmark obligation: algebras-inverses-image-f-f
-- Difficulty: routine
-- Source: Setoid.Functions.Inverses (agda-algebras)
-- Import stratum: wholesale
-- Strategy: constructor
--
module Inverses-image-f-f where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Relation.Binary  using ( Setoid )
open import Function.Bundles using ( Func )

open import Setoid.Functions

Imagef∋f′ : {α ρᵃ β ρᵇ : Level} {𝑨 : Setoid α ρᵃ} {𝑩 : Setoid β ρᵇ}
           (F : Func 𝑨 𝑩) (a : Setoid.Carrier 𝑨)
  →  Image F ∋ (Func.to F a)
Imagef∋f′ {𝑩 = 𝑩} F a = {!!}
