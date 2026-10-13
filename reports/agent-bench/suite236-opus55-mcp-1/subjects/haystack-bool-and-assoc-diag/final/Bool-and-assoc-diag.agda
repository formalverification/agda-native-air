-- Bool-and-assoc-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Bool-and-assoc-diag.agda
--
-- Benchmark obligation: haystack-bool-and-assoc-diag
-- Difficulty: routine (Tier 1)
--
module Bool-and-assoc-diag where

open import AgdaDojang.Debug

open import Data.Bool.Base using ( Bool ; _∧_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Bool.Properties using ( ∧-comm )

∧-assoc-diag : ∀ (a b : Bool) → (a ∧ b) ∧ a ≡ a ∧ (b ∧ a)
∧-assoc-diag a b = Data.Bool.Properties.∧-assoc a b a
