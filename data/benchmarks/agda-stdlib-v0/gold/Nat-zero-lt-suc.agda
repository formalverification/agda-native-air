-- Nat-zero-lt-suc.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-zero-lt-suc.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-zero-lt-suc
--
module Nat-zero-lt-suc where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _<_ ; _≤_ ; z≤n ; s≤s )

0<1+n : ∀ {n : ℕ} → 0 < suc n
0<1+n = s≤s z≤n
