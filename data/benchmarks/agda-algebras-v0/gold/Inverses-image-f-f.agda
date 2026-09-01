-- Inverses-image-f-f.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Inverses-image-f-f.agda
--
-- Gold solution for benchmark obligation: algebras-inverses-image-f-f
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
Imagef∋f′ {𝑩 = 𝑩} F a = eq a (Setoid.refl 𝑩)
