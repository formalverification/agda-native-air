-- Nat-plus-suc-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-plus-suc-diag.agda
--
-- Benchmark obligation: haystack-nat-plus-suc-diag
-- Difficulty: routine (Tier 1)
--
module Nat-plus-suc-diag where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( +-comm )

+-suc-diag : ∀ (m : ℕ) → m + suc m ≡ suc (m + m)
+-suc-diag m = Data.Nat.Properties.+-suc m m
