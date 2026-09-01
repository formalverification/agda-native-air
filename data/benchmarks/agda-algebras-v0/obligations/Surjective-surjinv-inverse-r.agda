-- Surjective-surjinv-inverse-r.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Surjective-surjinv-inverse-r.agda
--
-- Benchmark obligation: algebras-surjective-surjinv-inverse-r
-- Difficulty: compositional
-- Source: Setoid.Functions.Surjective (agda-algebras)
-- Import stratum: using
-- Strategy: application
--
module Surjective-surjinv-inverse-r where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Relation.Binary  using ( Setoid )
open import Function.Bundles using ( Func )

open import Setoid.Functions using ( IsSurjective ; SurjInv ; InvIsInverseʳ )

SurjInvIsInverseʳ′ : {α ρᵃ β ρᵇ : Level} {𝑨 : Setoid α ρᵃ} {𝑩 : Setoid β ρᵇ}
                     (f : Func 𝑨 𝑩) (fE : IsSurjective f) {b : Setoid.Carrier 𝑩}
  →  Setoid._≈_ 𝑩 (Func.to f (SurjInv f fE b)) b
SurjInvIsInverseʳ′ f fE = {!!}
