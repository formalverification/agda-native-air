-- Bool-and-distrib-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/Bool-and-distrib-diag.agda
--
-- Benchmark obligation: haystack-bool-and-distrib-diag
-- Difficulty: compositional (Tier 2)
--
module Bool-and-distrib-diag where

open import AgdaDojang.Debug

open import Data.Bool.Base using ( Bool ; _∧_ ; _∨_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )
open import Relation.Binary.PropositionalEquality using ( refl )
open import Data.Bool.Base using ( true ; false )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.Bool.Properties using ( ∧-comm ; ∨-comm )

∧-distrib-diag : ∀ (a b : Bool) → a ∧ (a ∨ b) ≡ a ∧ a ∨ a ∧ b
∧-distrib-diag true b = refl
∧-distrib-diag false b = refl
