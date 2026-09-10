-- Nat-plus-mono-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-plus-mono-diag.agda
--
-- Benchmark obligation: haystack-nat-plus-mono-diag
-- Difficulty: compositional (Tier 2)
-- Haystack: Data.Nat.Properties
-- Needle: Data.Nat.Properties.+-mono-≤
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: alias-typed needle (Monotonic₂) instantiated twice at the one hypothesis.
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module Nat-plus-mono-diag where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _+_ ; _≤_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( ≤-refl ; ≤-trans )

+-mono-diag : ∀ {m n : ℕ} → m ≤ n → m + m ≤ n + n
+-mono-diag le = {!!}
