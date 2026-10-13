-- Nat-mul-assoc.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-mul-assoc.agda
--
-- Benchmark obligation: stdlib-nat-mul-assoc
-- Difficulty: non-obvious (Tier 3)
--
module Nat-mul-assoc where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

-- Prerequisite (provided, not to be proved here)
open import Data.Nat.Properties using ( *-distribʳ-+ )

*-assoc : ∀ (m n p : ℕ) → (m * n) * p ≡ m * (n * p)
*-assoc zero n p = refl
*-assoc (suc m) n p rewrite *-distribʳ-+ p n (m * n) | *-assoc m n p = refl
