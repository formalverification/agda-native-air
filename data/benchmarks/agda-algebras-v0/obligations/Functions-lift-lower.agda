-- Functions-lift-lower.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Functions-lift-lower.agda
--
-- Benchmark obligation: algebras-functions-lift-lower
-- Difficulty: routine
-- Source: Setoid.Functions.Basic (agda-algebras)
-- Import stratum: wholesale
-- Strategy: refl
--
module Functions-lift-lower where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Level            using ( Lift ; lift ; lower )
open import Relation.Binary  using ( Setoid )

open import Setoid.Functions

lift∼lower′ : {α ρᵃ β : Level} (𝑨 : Setoid α ρᵃ) (a : Lift β (Setoid.Carrier 𝑨))
  →  Setoid._≈_ (𝑙𝑖𝑓𝑡 {𝑨 = 𝑨} β) (lift (lower a)) a
lift∼lower′ 𝑨 a = {!!}
