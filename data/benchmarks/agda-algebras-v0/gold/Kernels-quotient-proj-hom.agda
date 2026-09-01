-- Kernels-quotient-proj-hom.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Kernels-quotient-proj-hom.agda
--
-- Gold solution for benchmark obligation: algebras-kernels-quotient-proj-hom
--
module Kernels-quotient-proj-hom where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )

open import Overture              using ( Signature )
open import Setoid.Algebras       using ( Algebra )
open import Setoid.Congruences    using ( Con ; _╱_ )
open import Setoid.Homomorphisms  using ( hom ; epi→hom ; πepi )

πhom′ : {𝓞 𝓥 α ρᵃ β ρᵇ ℓ : Level} {𝑆 : Signature 𝓞 𝓥}
        {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ}
        (h : hom 𝑨 𝑩) (θ : Con 𝑨 ℓ)
  →  hom 𝑨 (𝑨 ╱ θ)
πhom′ {𝑨 = 𝑨} h θ = epi→hom 𝑨 (𝑨 ╱ θ) (πepi h θ)
