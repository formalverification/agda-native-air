-- Nat-plus-monus-assoc.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-plus-monus-assoc.agda
--
-- Benchmark obligation: haystack-nat-plus-monus-assoc
-- Difficulty: compositional (Tier 2)
--
module Nat-plus-monus-assoc where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _+_ ; _∸_ ; _≤_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( +-comm ; n∸n≡0 )

+-∸-assoc-diag : ∀ {m n : ℕ} → m ≤ n → n + n ∸ m ≡ n + (n ∸ m)
+-∸-assoc-diag {m} {n} le = Data.Nat.Properties.+-∸-assoc n le
