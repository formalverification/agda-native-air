-- Congruence-monolith-below-member.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Congruence-monolith-below-member.agda
--
-- Benchmark obligation: comp-congruence-monolith-below-member
-- Difficulty: non-obvious
-- Import stratum: composition
--
-- The monolith of an algebra lies below every member of a family of congruences whose meet is nonzero.
--
module Congruence-monolith-below-member where

open import AgdaDojang.Debug

open import Level                        using ( Level )
open import Overture                     using ( 𝓞 ; 𝓥 ; Signature )
open import Setoid.Algebras              using ( Algebra )
open import Setoid.Congruences.Basic     using ( Con )
open import Setoid.Congruences.Lattice   using ( _⊆_ ; ⊆-refl ; ⊆-trans )
open import Setoid.Congruences.Monolith  using ( IsMonolith ; Nonzero ; ⋂ ; ⋂-lower )

module _ {α ρ : Level} {𝑆 : Signature 𝓞 𝓥} {𝑨 : Algebra {𝑆 = 𝑆} α ρ}
  {I : Set ρ} {μ : Con 𝑨 ρ} {θ : I → Con 𝑨 ρ}
  where

  monolith-below-member : IsMonolith 𝑨 μ → Nonzero 𝑨 (⋂ 𝑨 θ) → (i : I) → μ ⊆ θ i
  monolith-below-member mono nz i {x} {y} pxy =
    ⋂-lower 𝑨 θ i (IsMonolith.mono-least mono (⋂ 𝑨 θ) nz pxy)
