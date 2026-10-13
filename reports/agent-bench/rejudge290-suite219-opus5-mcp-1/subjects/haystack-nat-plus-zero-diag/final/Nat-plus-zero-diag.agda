-- Nat-plus-zero-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-plus-zero-diag.agda
--
-- Benchmark obligation: haystack-nat-plus-zero-diag
-- Difficulty: non-obvious (Tier 3)
--
module Nat-plus-zero-diag where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( +-comm )

+-zero-diag : ∀ (m : ℕ) → m + m ≡ 0 → m ≡ 0
+-zero-diag ℕ.zero    eq = eq
+-zero-diag (ℕ.suc m) ()
