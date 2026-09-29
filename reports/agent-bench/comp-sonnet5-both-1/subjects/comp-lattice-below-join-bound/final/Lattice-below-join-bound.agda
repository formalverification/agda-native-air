-- Lattice-below-join-bound.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Lattice-below-join-bound.agda
--
-- Benchmark obligation: comp-lattice-below-join-bound
-- Difficulty: compositional
-- Import stratum: composition
--
-- In a lattice, anything below a join lies below every common upper bound of the joinands.
--
module Lattice-below-join-bound where

open import AgdaDojang.Debug

open import Data.Product                        using ( proj₁ )
open import Level                               using ( Level )
open import Classical.Structures.Lattice.Basic  using ( Lattice ; module Lattice-Op )
open import Classical.Properties.Lattice        using ( module Lattice-Order )
open import Setoid.Algebras.Basic               using ( 𝕌[_] )

module _ {α ρ : Level} (𝑳 : Lattice α ρ) where

  open Lattice-Op 𝑳     using ( _∨_ )
  open Lattice-Order 𝑳  using ( _≤_ ; ≤-refl ; ≤-trans ; ∨-least )

  below-join-bound : ∀ {x y z w : 𝕌[ proj₁ 𝑳 ]} → x ≤ (y ∨ z) → y ≤ w → z ≤ w → x ≤ w
  below-join-bound x≤y∨z y≤w z≤w = ≤-trans x≤y∨z (∨-least y≤w z≤w)
