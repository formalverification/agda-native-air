-- Nat-plus-comm.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-plus-comm.agda
--
-- Benchmark obligation: stdlib-nat-plus-comm
-- Difficulty: compositional (Tier 2)
--
module Nat-plus-comm where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )

-- Prerequisites (provided, not to be proved here)
open import Data.Nat.Properties using ( +-identityʳ ; +-suc )

+-comm : ∀ (m n : ℕ) → m + n ≡ n + m
+-comm zero n rewrite +-identityʳ n = refl
+-comm (suc m) n rewrite +-comm m n | +-suc n m = refl
