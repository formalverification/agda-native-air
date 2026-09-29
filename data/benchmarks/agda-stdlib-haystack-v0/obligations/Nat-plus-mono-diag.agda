-- Nat-plus-mono-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-plus-mono-diag.agda
--
-- Benchmark obligation: haystack-nat-plus-mono-diag
-- Difficulty: compositional (Tier 2)
--
module Nat-plus-mono-diag where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _+_ ; _≤_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( ≤-refl ; ≤-trans )

+-mono-diag : ∀ {m n : ℕ} → m ≤ n → m + m ≤ n + n
+-mono-diag le = {!!}
