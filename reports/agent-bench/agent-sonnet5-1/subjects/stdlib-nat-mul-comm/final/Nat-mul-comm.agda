-- Nat-mul-comm.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-mul-comm.agda
--
-- Benchmark obligation: stdlib-nat-mul-comm
-- Difficulty: non-obvious (Tier 3)
-- Source: Data.Nat.Properties
-- Strategy: induction on m; base sym (*-zeroʳ n), step an equational chain using *-suc
--
-- Note: *-zeroʳ and *-suc are provided as imports; the challenge is the
-- non-obvious composition (the recursive call sits under cong, and the final
-- step rewrites with *-suc backwards).
--
module Nat-mul-comm where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym ; trans )

-- Prerequisites (provided, not to be proved here)
open import Data.Nat.Properties using ( *-zeroʳ ; *-suc )

*-comm : ∀ (m n : ℕ) → m * n ≡ n * m
*-comm zero n = sym (*-zeroʳ n)
*-comm (suc m) n = trans (cong (n +_) (*-comm m n)) (sym (*-suc n m))
