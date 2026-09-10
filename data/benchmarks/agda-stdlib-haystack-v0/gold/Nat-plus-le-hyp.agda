-- Nat-plus-le-hyp.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/gold/Nat-plus-le-hyp.agda
--
-- Benchmark obligation: haystack-nat-plus-le-hyp
-- Difficulty: non-obvious (Tier 3)
-- Haystack: Data.Nat.Properties
-- Needle: Data.Nat.Properties.m+n≤o⇒m≤o
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: the goal m ≤ n carries no signal; the two-step ≤-trans (m≤m+n m m) le is expressible from the decoys but not in term mode (m+n≤o⇒n≤o closes it too).
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module Nat-plus-le-hyp where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _+_ ; _≤_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( ≤-trans ; m≤m+n )

m+m≤n⇒m≤n : ∀ {m n : ℕ} → m + m ≤ n → m ≤ n
m+m≤n⇒m≤n {m} {n} le = Data.Nat.Properties.m+n≤o⇒m≤o m le
