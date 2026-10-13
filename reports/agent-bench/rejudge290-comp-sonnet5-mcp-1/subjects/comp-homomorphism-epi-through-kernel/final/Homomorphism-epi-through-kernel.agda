-- Homomorphism-epi-through-kernel.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Homomorphism-epi-through-kernel.agda
--
-- Benchmark obligation: comp-homomorphism-epi-through-kernel
-- Difficulty: compositional
-- Import stratum: composition
--
-- An epimorphism out of the kernel quotient of h yields an epimorphism out of the domain of h.
--
module Homomorphism-epi-through-kernel where

open import AgdaDojang.Debug

open import Level                           using ( Level )
open import Overture                        using ( 𝓞 ; 𝓥 ; Signature )
open import Setoid.Algebras                 using ( Algebra )
open import Setoid.Homomorphisms.Basic      using ( hom ; epi )
open import Setoid.Homomorphisms.Kernels    using ( ker[_⇒_]_ )
open import Setoid.Homomorphisms.Properties using ( ⊙-hom )
open import Setoid.Homomorphisms.Kernels    using ( πker )
open import Setoid.Homomorphisms.Properties using ( ⊙-epi )

module _ {α ρᵃ β ρᵇ γ ρᶜ : Level} {𝑆 : Signature 𝓞 𝓥}
  {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra {𝑆 = 𝑆} β ρᵇ} {𝑪 : Algebra {𝑆 = 𝑆} γ ρᶜ}
  where

  epi-through-kernel : (h : hom 𝑨 𝑩) → epi (ker[ 𝑨 ⇒ 𝑩 ] h) 𝑪 → epi 𝑨 𝑪
  epi-through-kernel h e = ⊙-epi (πker h) e
