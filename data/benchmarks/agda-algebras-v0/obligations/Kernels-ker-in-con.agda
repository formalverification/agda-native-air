-- Kernels-ker-in-con.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Kernels-ker-in-con.agda
--
-- Benchmark obligation: algebras-kernels-ker-in-con
-- Difficulty: non-obvious
-- Source: Setoid.Homomorphisms.Kernels (agda-algebras)
-- Import stratum: wholesale
-- Strategy: identity-function
--
module Kernels-ker-in-con where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( proj₁ )
open import Function.Base    using ( id )
open import Relation.Binary  using ( Setoid )

open import Overture              using ( Signature )
open import Setoid.Algebras       using ( Algebra ; 𝔻[_] )
open import Setoid.Congruences    using ( Con )
open import Setoid.Homomorphisms

ker-in-con′ : {𝓞 𝓥 α ρᵃ β ρᵇ ℓ : Level} {𝑆 : Signature 𝓞 𝓥}
              {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ}
              (h : hom 𝑨 𝑩) {θ : Con 𝑨 ℓ}
              {x y : Setoid.Carrier 𝔻[ 𝑨 ]}
  →  proj₁ (kercon (πhom h θ)) x y → proj₁ θ x y
ker-in-con′ h = {!!}
