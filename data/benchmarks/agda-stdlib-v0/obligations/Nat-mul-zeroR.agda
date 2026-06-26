-- Nat-mul-zeroR.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-mul-zeroR.agda
--
-- Benchmark obligation: stdlib-nat-mul-zero-r
-- Difficulty: compositional (Tier 2)
-- Source: Data.Nat.Properties
-- Strategy: induction on n; base refl, step is the IH (0 + n * 0 reduces to n * 0)
--
module Nat-mul-zeroR where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

*-zeroʳ : ∀ (n : ℕ) → n * 0 ≡ 0
*-zeroʳ n = {!!}
