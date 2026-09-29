-- Bool-and-distrib-diag.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/gold/Bool-and-distrib-diag.agda
--
-- Benchmark obligation: haystack-bool-and-distrib-diag
-- Difficulty: compositional (Tier 2)
--
module Bool-and-distrib-diag where

open import AgdaDojang.Debug

open import Data.Bool.Base using ( Bool ; _∧_ ; _∨_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Bool.Properties using ( ∧-comm ; ∨-comm )

∧-distrib-diag : ∀ (a b : Bool) → a ∧ (a ∨ b) ≡ a ∧ a ∨ a ∧ b
∧-distrib-diag a b = Data.Bool.Properties.∧-distribˡ-∨ a a b
