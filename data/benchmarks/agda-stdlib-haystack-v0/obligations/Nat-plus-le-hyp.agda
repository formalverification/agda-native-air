-- Nat-plus-le-hyp.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-plus-le-hyp.agda
--
-- Benchmark obligation: haystack-nat-plus-le-hyp
-- Difficulty: non-obvious (Tier 3)
--
module Nat-plus-le-hyp where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _+_ ; _≤_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( ≤-trans ; m≤m+n )

m+m≤n⇒m≤n : ∀ {m n : ℕ} → m + m ≤ n → m ≤ n
m+m≤n⇒m≤n {m} {n} le = {!!}
