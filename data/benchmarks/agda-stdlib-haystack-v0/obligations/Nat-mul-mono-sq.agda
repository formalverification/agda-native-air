-- Nat-mul-mono-sq.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-mul-mono-sq.agda
--
-- Benchmark obligation: haystack-nat-mul-mono-sq
-- Difficulty: compositional (Tier 2)
--
module Nat-mul-mono-sq where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _*_ ; _≤_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( ≤-trans ; *-comm )

*-mono-sq : ∀ {m n : ℕ} → m ≤ n → m * m ≤ n * n
*-mono-sq le = {!!}
