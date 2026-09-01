-- Inverses-range-to-image.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Inverses-range-to-image.agda
--
-- Benchmark obligation: algebras-inverses-range-to-image
-- Difficulty: compositional
-- Source: Setoid.Functions.Inverses (agda-algebras)
-- Import stratum: wholesale
-- Strategy: constructor
--
module Inverses-range-to-image where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( proj₁ ; proj₂ )
open import Relation.Binary  using ( Setoid )
open import Function.Bundles using ( Func )

open import Setoid.Functions

IsInRange→IsInImage′ : {α ρᵃ β ρᵇ : Level} {𝑨 : Setoid α ρᵃ} {𝑩 : Setoid β ρᵇ}
                       {F : Func 𝑨 𝑩} {b : Setoid.Carrier 𝑩}
  →  IsInRange F b → Image F ∋ b
IsInRange→IsInImage′ {𝑩 = 𝑩} w = {!!}
