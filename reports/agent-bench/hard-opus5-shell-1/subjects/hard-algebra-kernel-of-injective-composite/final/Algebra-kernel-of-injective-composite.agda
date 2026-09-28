-- Algebra-kernel-of-injective-composite.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/obligations/Algebra-kernel-of-injective-composite.agda
--
-- Benchmark obligation: hard-algebra-kernel-of-injective-composite
-- Difficulty: compositional
-- Source: Setoid.Homomorphisms.Kernels with Setoid.Congruences.Lattice (the congruence order _≑_); Setoid.Homomorphisms.Properties has ⊙-hom
-- Import stratum: novel
-- Strategy: one direction is cong of g; the other is injectivity of g
--
-- The kernel congruence of a composite g ⊙ f equals the kernel congruence of f when g is injective, in the congruence order ≑ of Setoid.Congruences.Lattice.
--
module Algebra-kernel-of-injective-composite where

open import AgdaDojang.Debug

open import Data.Product                  using ( _,_ ; proj₁ )
open import Level                         using ( Level )

open import Overture                                 using ( 𝓞 ; 𝓥 ; Signature )
open import Setoid.Algebras                          using ( Algebra )
open import Setoid.Functions                         using ( IsInjective )
open import Setoid.Homomorphisms.Basic               using ( hom )
open import Setoid.Homomorphisms.Kernels             using ( kercon )
open import Setoid.Homomorphisms.Properties          using ( ⊙-hom )
open import Setoid.Congruences.Lattice               using ( _≑_ )

open import Function                                 using ( Func )
open import Setoid.Congruences.Lattice               using ( _⊆_ )

module _ {α ρᵃ β ρ : Level} {𝑆 : Signature 𝓞 𝓥}
  {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρ} {𝑪 : Algebra β ρ}
  (f : hom 𝑨 𝑩) (g : hom 𝑩 𝑪)
  where

  kernel-of-injective-composite : IsInjective (proj₁ g) → kercon (⊙-hom f g) ≑ kercon f
  kernel-of-injective-composite g-inj = gfx≈gfy→fx≈fy , fx≈fy→gfx≈gfy
    where
    gfx≈gfy→fx≈fy : kercon (⊙-hom f g) ⊆ kercon f
    gfx≈gfy→fx≈fy p = g-inj p

    fx≈fy→gfx≈gfy : kercon f ⊆ kercon (⊙-hom f g)
    fx≈fy→gfx≈gfy p = Func.cong (proj₁ g) p
