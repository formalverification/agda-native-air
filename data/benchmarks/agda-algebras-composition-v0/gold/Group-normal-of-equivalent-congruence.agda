-- Group-normal-of-equivalent-congruence.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/gold/Group-normal-of-equivalent-congruence.agda
--
-- Benchmark obligation: comp-group-normal-of-equivalent-congruence
-- Difficulty: non-obvious
-- Source: Classical.Structures.Group.Congruences (GroupCongruences.≈ⁿ-trans, normalOf-cong, normalOf∘congruenceOf), Setoid.Congruences.Lattice (≑-trans)
-- Import stratum: composition
-- Strategy: θ ≑ congruenceOf N, so normalOf θ ≈ⁿ normalOf (congruenceOf N) ≈ⁿ N
--
-- The normal subgroup of a congruence equivalent (through φ) to the congruence of a normal subgroup N is N.
--
module Group-normal-of-equivalent-congruence where

open import AgdaDojang.Debug

open import Data.Product                            using ( proj₁ )
open import Level                                   using ( Level )
open import Classical.Structures.Group.Basic        using ( Group )
open import Classical.Structures.Group.Congruences  using ( module GroupCongruences )
open import Setoid.Congruences.Basic                using ( Con )
open import Setoid.Congruences.Lattice              using ( _≑_ ; ≑-refl )

module _ {α ρ ℓ : Level} (𝒢 : Group α ρ) where

  open GroupCongruences 𝒢  using ( NormalSubgroup ; normalOf ; congruenceOf ; _≈ⁿ_ ; ≈ⁿ-refl )

  normal-of-equivalent-congruence : {θ φ : Con (proj₁ 𝒢) ℓ} {𝑵 : NormalSubgroup ℓ}
    → θ ≑ φ → φ ≑ congruenceOf 𝑵 → normalOf θ ≈ⁿ 𝑵
  normal-of-equivalent-congruence {θ} {φ} {𝑵} θ≑φ φ≑N =
    GroupCongruences.≈ⁿ-trans 𝒢 {𝑳 = normalOf θ} {𝑴 = normalOf (congruenceOf 𝑵)} {𝑵 = 𝑵}
      (GroupCongruences.normalOf-cong 𝒢 θ (congruenceOf 𝑵)
        (Setoid.Congruences.Lattice.≑-trans {θ = θ} {φ = φ} {ψ = congruenceOf 𝑵} θ≑φ φ≑N))
      (GroupCongruences.normalOf∘congruenceOf 𝒢 𝑵)
