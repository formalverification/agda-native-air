-- Group-normal-of-equivalent-congruence.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Group-normal-of-equivalent-congruence.agda
--
-- Benchmark obligation: comp-group-normal-of-equivalent-congruence
-- Difficulty: non-obvious
-- Import stratum: composition
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
  open GroupCongruences 𝒢
    using ( ≈ⁿ-trans ; normalOf-cong ; normalOf∘congruenceOf )

  normal-of-equivalent-congruence {θ} {φ} {𝑵} θ≑φ φ≑N =
    ≈ⁿ-trans {ℓ} {normalOf θ} {normalOf φ} {𝑵}
      (normalOf-cong θ φ θ≑φ)
      (≈ⁿ-trans {ℓ} {normalOf φ} {normalOf (congruenceOf 𝑵)} {𝑵}
        (normalOf-cong φ (congruenceOf 𝑵) φ≑N)
        (normalOf∘congruenceOf 𝑵))
