-- Homs-comp-hom.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Homs-comp-hom.agda
--
-- Benchmark obligation: algebras-homs-comp-hom
-- Difficulty: compositional
-- Source: Setoid.Homomorphisms.Properties (agda-algebras)
-- Import stratum: using
-- Strategy: pairing
--
module Homs-comp-hom where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( _,_ ; proj₁ ; proj₂ )

open import Overture              using ( Signature )
open import Setoid.Algebras       using ( Algebra )
open import Setoid.Functions      using ( _⊙_ )
open import Setoid.Homomorphisms  using ( hom ; ⊙-is-hom )

⊙-hom′ : {𝓞 𝓥 α ρᵃ β ρᵇ γ ρᶜ : Level} {𝑆 : Signature 𝓞 𝓥}
         {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ} {𝑪 : Algebra γ ρᶜ}
  →  hom 𝑨 𝑩 → hom 𝑩 𝑪 → hom 𝑨 𝑪
⊙-hom′ f g = {!!}
