-- Nat-plus-zero-diag.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/gold/Nat-plus-zero-diag.agda
--
-- Benchmark obligation: haystack-nat-plus-zero-diag
-- Difficulty: non-obvious (Tier 3)
-- Haystack: Data.Nat.Properties
-- Needle: Data.Nat.Properties.m+n≡0⇒m≡0
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: a hypothesis-consuming instance; the goal m ≡ 0 carries no signal, the
-- hypothesis does (m+n≡0⇒n≡0 closes it too).  The hypothesis is bound in the
-- clause because the proposer saturates every visible binder of a lemma, so a
-- Π-typed goal could only be closed by a partial application, which is not one
-- of the three committed candidate shapes (found on the retrieve-k 32 ledger).
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
+-zero-diag m eq = Data.Nat.Properties.m+n≡0⇒m≡0 m eq
