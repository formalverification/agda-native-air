-- Bool-and-distrib-diag.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/gold/Bool-and-distrib-diag.agda
--
-- Benchmark obligation: haystack-bool-and-distrib-diag
-- Difficulty: compositional (Tier 2)
-- Haystack: Data.Bool.Properties
-- Needle: Data.Bool.Properties.∧-distribˡ-∨
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: an instance of the alias-typed ∧-distribˡ-∨ (DistributesOverˡ) with two variables identified.
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module Bool-and-distrib-diag where

open import AgdaDojang.Debug

open import Data.Bool.Base using ( Bool ; _∧_ ; _∨_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Bool.Properties using ( ∧-comm ; ∨-comm )

∧-distrib-diag : ∀ (a b : Bool) → a ∧ (a ∨ b) ≡ a ∧ a ∨ a ∧ b
∧-distrib-diag a b = Data.Bool.Properties.∧-distribˡ-∨ a a b
