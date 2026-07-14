-- Nat-plus-comm.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-plus-comm.agda
--
-- Benchmark obligation: stdlib-nat-plus-comm
-- Difficulty: compositional (Tier 2)
-- Source: Data.Nat.Properties
-- Strategy: induction on m, using +-identityʳ (base) and +-suc (step)
--
-- Note: the obligation provides +-identityʳ and +-suc as imports so
-- the agent has access to the key lemmas.  The challenge is composing
-- them correctly in the inductive proof.
--
module Nat-plus-comm where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )

-- Prerequisites (provided, not to be proved here)
open import Data.Nat.Properties using ( +-identityʳ ; +-suc )

+-comm : ∀ (m n : ℕ) → m + n ≡ n + m
+-comm m n = {!!}
