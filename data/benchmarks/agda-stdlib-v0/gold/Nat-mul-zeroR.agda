-- Nat-mul-zeroR.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-mul-zeroR.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-mul-zero-r
--
module Nat-mul-zeroR where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

*-zeroʳ : ∀ (n : ℕ) → n * 0 ≡ 0
*-zeroʳ zero    = refl
*-zeroʳ (suc n) = *-zeroʳ n
