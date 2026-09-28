-- Congruence-meet-below-join.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/gold/Congruence-meet-below-join.agda
--
-- Benchmark obligation: comp-congruence-meet-below-join
-- Difficulty: compositional
-- Import stratum: composition
--
-- In the congruence lattice, the meet of a family member with any congruence lies below the join of the family.
--
module Congruence-meet-below-join where

open import AgdaDojang.Debug

open import Level                                using ( Level ; _⊔_ )
open import Overture                             using ( 𝓞 ; 𝓥 ; Signature )
open import Setoid.Algebras                      using ( Algebra )
open import Setoid.Congruences.Basic             using ( Con )
open import Setoid.Congruences.Lattice           using ( _⊆_ ; _∧_ )
open import Setoid.Congruences.CompleteLattice   using ( ⋁ )

module _ {α ρ ℓ₀ : Level} {𝑆 : Signature 𝓞 𝓥} (𝑨 : Algebra {𝑆 = 𝑆} α ρ) {I : Set ℓ₀}
  (f : I → Con 𝑨 (𝓞 ⊔ 𝓥 ⊔ α ⊔ ρ ⊔ ℓ₀))
  where

  meet-below-join : (φ : Con 𝑨 (𝓞 ⊔ 𝓥 ⊔ α ⊔ ρ ⊔ ℓ₀)) (i : I) → (f i ∧ φ) ⊆ ⋁ 𝑨 ℓ₀ f
  meet-below-join φ i =
    Setoid.Congruences.Lattice.⊆-trans {θ = f i ∧ φ} {φ = f i} {ψ = ⋁ 𝑨 ℓ₀ f}
      (Setoid.Congruences.Lattice.∧-lowerˡ {θ = f i} {φ = φ})
      (Setoid.Congruences.CompleteLattice.⋁-upper 𝑨 ℓ₀ f i)
