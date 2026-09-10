-- Nat-plus-zero-diag.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/gold/Nat-plus-zero-diag.agda
--
-- Benchmark obligation: haystack-nat-plus-zero-diag
-- Difficulty: compositional (Tier 2)
-- Haystack: Data.Nat.Properties
-- Needle: Data.Nat.Properties.m+n≡0⇒m≡0
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: the goal is a Π-type; the needle's implicit n is solved by unification (m+n≡0⇒n≡0 closes it too).
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module Nat-plus-zero-diag where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Nat.Properties using ( +-comm )

+-zero-diag : ∀ (m : ℕ) → m + m ≡ 0 → m ≡ 0
+-zero-diag m = Data.Nat.Properties.m+n≡0⇒m≡0 m
