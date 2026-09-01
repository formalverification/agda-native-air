-- Subalgebras-sub-trans.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Subalgebras-sub-trans.agda
--
-- Benchmark obligation: algebras-subalgebras-sub-trans
-- Difficulty: non-obvious
-- Source: Setoid.Subalgebras.Properties (agda-algebras)
-- Import stratum: using
-- Strategy: pairing
--
module Subalgebras-sub-trans where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( _,_ ; proj₁ ; proj₂ )

open import Overture              using ( Signature )
open import Setoid.Algebras       using ( Algebra )
open import Setoid.Functions      using ( ⊙-injective )
open import Setoid.Homomorphisms  using ( ⊙-hom )
open import Setoid.Subalgebras    using ( _≤_ )

≤-trans′ : {𝓞 𝓥 α ρᵃ β ρᵇ γ ρᶜ : Level} {𝑆 : Signature 𝓞 𝓥}
           {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ} {𝑪 : Algebra γ ρᶜ}
  →  𝑨 ≤ 𝑩 → 𝑩 ≤ 𝑪 → 𝑨 ≤ 𝑪
≤-trans′ p q = {!!}
