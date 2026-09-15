-- Nat-plus-suc-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Nat-plus-suc-diag.agda
--
-- Benchmark obligation: haystack-nat-plus-suc-diag
-- Difficulty: routine (Tier 1)
-- Haystack: Data.Nat.Properties
-- Needle: Data.Nat.Properties.+-suc
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: the diagonal instance of +-suc; the goal's operators spell the needle.
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module Nat-plus-suc-diag where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( +-comm )

+-suc-diag : ∀ (m : ℕ) → m + suc m ≡ suc (m + m)
+-suc-diag m = {!!}
