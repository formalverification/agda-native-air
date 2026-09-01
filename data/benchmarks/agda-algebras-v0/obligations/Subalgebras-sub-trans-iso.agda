-- Subalgebras-sub-trans-iso.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Subalgebras-sub-trans-iso.agda
--
-- Benchmark obligation: algebras-subalgebras-sub-trans-iso
-- Difficulty: non-obvious
-- Source: Setoid.Subalgebras.Properties (agda-algebras)
-- Import stratum: wholesale
-- Strategy: pairing
--
module Subalgebras-sub-trans-iso where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( _,_ ; proj₁ ; proj₂ )

open import Overture              using ( Signature )
open import Setoid.Algebras       using ( Algebra )
open import Setoid.Functions
open import Setoid.Homomorphisms
open import Setoid.Subalgebras

≤-trans-≅′ : {𝓞 𝓥 α ρᵃ β ρᵇ γ ρᶜ : Level} {𝑆 : Signature 𝓞 𝓥}
             {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ} {𝑪 : Algebra γ ρᶜ}
  →  𝑨 ≤ 𝑩 → 𝑩 ≅ 𝑪 → 𝑨 ≤ 𝑪
≤-trans-≅′ p B≅C = {!!}
