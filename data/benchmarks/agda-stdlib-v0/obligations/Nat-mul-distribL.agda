-- Nat-mul-distribL.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-mul-distribL.agda
--
-- Benchmark obligation: stdlib-nat-mul-distrib-l
-- Difficulty: non-obvious (Tier 3)
-- Source: Data.Nat.Properties
-- Strategy: reduce to right-distributivity via commutativity (no induction here)
--
-- Note: *-comm and *-distribʳ-+ are provided; the non-obvious move is to use
-- commutativity to convert the goal into the right-distributive form.
--
module Nat-mul-distribL where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _+_ ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; cong₂ )

-- Prerequisites (provided, not to be proved here)
open import Data.Nat.Properties using ( *-comm ; *-distribʳ-+ )

*-distribˡ-+ : ∀ (m n p : ℕ) → m * (n + p) ≡ m * n + m * p
*-distribˡ-+ m n p = {!!}
