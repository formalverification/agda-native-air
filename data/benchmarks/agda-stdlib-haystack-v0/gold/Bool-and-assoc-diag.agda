-- Bool-and-assoc-diag.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/gold/Bool-and-assoc-diag.agda
--
-- Benchmark obligation: haystack-bool-and-assoc-diag
-- Difficulty: routine (Tier 1)
-- Haystack: Data.Bool.Properties
-- Needle: Data.Bool.Properties.∧-assoc
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: an instance of the alias-typed ∧-assoc (Associative) with its outer variables identified.
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module Bool-and-assoc-diag where

open import AgdaDojang.Debug

open import Data.Bool.Base using ( Bool ; _∧_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Bool.Properties using ( ∧-comm )

∧-assoc-diag : ∀ (a b : Bool) → (a ∧ b) ∧ a ≡ a ∧ (b ∧ a)
∧-assoc-diag a b = Data.Bool.Properties.∧-assoc a b a
