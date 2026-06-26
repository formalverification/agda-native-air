-- Nat-zero-lt-suc.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-zero-lt-suc.agda
--
-- Benchmark obligation: stdlib-nat-zero-lt-suc
-- Difficulty: routine (Tier 1)
-- Source: Data.Nat.Base
-- Strategy: apply the _≤_ constructors (s≤s, z≤n)
--
module Nat-zero-lt-suc where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _<_ ; _≤_ ; z≤n ; s≤s )

0<1+n : ∀ {n : ℕ} → 0 < suc n
0<1+n = {!!}
