-- Group-normal-of-smaller-congruence.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Group-normal-of-smaller-congruence.agda
--
-- Benchmark obligation: comp-group-normal-of-smaller-congruence
-- Difficulty: compositional
-- Import stratum: composition
--
-- If θ ⊆ φ and the normal subgroup of φ lies in N, the normal subgroup of θ lies in N.
--
module Group-normal-of-smaller-congruence where

open import AgdaDojang.Debug

open import Data.Product                            using ( proj₁ )
open import Level                                   using ( Level )
open import Classical.Structures.Group.Basic        using ( Group )
open import Classical.Structures.Group.Congruences  using ( module GroupCongruences )
open import Setoid.Congruences.Basic                using ( Con )
open import Setoid.Congruences.Lattice              using ( _⊆_ ; ⊆-refl )

module _ {α ρ ℓ : Level} (𝒢 : Group α ρ) where

  open GroupCongruences 𝒢  using ( NormalSubgroup ; normalOf ; _≤ⁿ_ ; ≤ⁿ-refl )

  normal-of-smaller-congruence : {θ φ : Con (proj₁ 𝒢) ℓ} {𝑵 : NormalSubgroup ℓ}
    → θ ⊆ φ → normalOf φ ≤ⁿ 𝑵 → normalOf θ ≤ⁿ 𝑵
  normal-of-smaller-congruence {θ} {φ} {𝑵} θ⊆φ φ≤N = {!!}
