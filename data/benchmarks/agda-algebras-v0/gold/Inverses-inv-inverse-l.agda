-- Inverses-inv-inverse-l.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Inverses-inv-inverse-l.agda
--
-- Gold solution for benchmark obligation: algebras-inverses-inv-inverse-l
--
module Inverses-inv-inverse-l where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Relation.Binary  using ( Setoid )
open import Function.Bundles using ( Func )

open import Setoid.Functions

InvIsInverseˡ′ : {α ρᵃ β ρᵇ : Level} {𝑨 : Setoid α ρᵃ} {𝑩 : Setoid β ρᵇ}
                {F : Func 𝑨 𝑩} {a : Setoid.Carrier 𝑨}
  →  Setoid._≈_ 𝑨 (Inv F {b = Func.to F a} Imagef∋f) a
InvIsInverseˡ′ {𝑨 = 𝑨} = Setoid.refl 𝑨
