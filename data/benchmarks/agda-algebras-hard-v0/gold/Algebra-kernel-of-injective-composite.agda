-- Algebra-kernel-of-injective-composite.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/gold/Algebra-kernel-of-injective-composite.agda
--
-- Benchmark obligation: hard-algebra-kernel-of-injective-composite
-- Difficulty: compositional
-- Import stratum: novel
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

module _ {α ρᵃ β ρ : Level} {𝑆 : Signature 𝓞 𝓥}
  {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρ} {𝑪 : Algebra β ρ}
  (f : hom 𝑨 𝑩) (g : hom 𝑩 𝑪)
  where

  kernel-of-injective-composite : IsInjective (proj₁ g) → kercon (⊙-hom f g) ≑ kercon f
  kernel-of-injective-composite g-inj = g-inj , Func.cong (proj₁ g)
    where
    open import Function using ( Func )
