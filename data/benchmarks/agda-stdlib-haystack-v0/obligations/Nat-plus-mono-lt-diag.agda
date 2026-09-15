-- Nat-plus-mono-lt-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-plus-mono-lt-diag.agda
--
-- Benchmark obligation: haystack-nat-plus-mono-lt-diag
-- Difficulty: non-obvious (Tier 3)
-- Haystack: Data.Nat.Properties
-- Needle: Data.Nat.Properties.+-mono-<
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: the ≤ sibling is using-listed and insufficient; the goal displays as suc (m + m) ≤ n + n, so the needle's own < is a misfit token for the ranker.
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module Nat-plus-mono-lt-diag where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; suc ; _+_ ; _≤_ ; _<_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( ≤-trans ; +-mono-≤ )

+-mono-<-diag : ∀ {m n : ℕ} → m < n → m + m < n + n
+-mono-<-diag lt = {!!}
