-- Nat-mul-comm.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-mul-comm.agda
--
-- Benchmark obligation: stdlib-nat-mul-comm
-- Difficulty: non-obvious (Tier 3)
--
module Nat-mul-comm where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )

-- Prerequisites (provided, not to be proved here)
open import Data.Nat.Properties using ( *-zeroʳ ; *-suc )

open import Relation.Binary.PropositionalEquality using ( trans )

*-comm : ∀ (m n : ℕ) → m * n ≡ n * m
*-comm zero n = sym (*-zeroʳ n)
*-comm (suc m) n = trans (cong (n +_) (*-comm m n)) (sym (*-suc n m))
