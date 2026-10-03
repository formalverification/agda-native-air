-- Nat-plus-mono-lt-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-plus-mono-lt-diag.agda
--
-- Benchmark obligation: haystack-nat-plus-mono-lt-diag
-- Difficulty: non-obvious (Tier 3)
--
module Nat-plus-mono-lt-diag where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; suc ; _+_ ; _≤_ ; _<_ )
open import Data.Nat.Base using ( z≤n ; s≤s )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( ≤-trans ; +-mono-≤ )

private
  ≤-step : ∀ {m n} → m ≤ n → m ≤ suc n
  ≤-step z≤n     = z≤n
  ≤-step (s≤s p) = s≤s (≤-step p)

  <⇒≤ : ∀ {m n} → m < n → m ≤ n
  <⇒≤ (s≤s p) = ≤-step p

+-mono-<-diag : ∀ {m n : ℕ} → m < n → m + m < n + n
+-mono-<-diag lt = +-mono-≤ lt (<⇒≤ lt)
