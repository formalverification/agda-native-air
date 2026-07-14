-- Nat-mul-comm.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-mul-comm.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-mul-comm
--
module Nat-mul-comm where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )
open import Relation.Binary.PropositionalEquality.Properties using ( module ≡-Reasoning )
open ≡-Reasoning

-- Prerequisites (provided, not to be proved here)
open import Data.Nat.Properties using ( *-zeroʳ ; *-suc )

*-comm : ∀ (m n : ℕ) → m * n ≡ n * m
*-comm zero    n = sym (*-zeroʳ n)
*-comm (suc m) n = begin
  suc m * n   ≡⟨⟩
  n + m * n   ≡⟨ cong (n +_) (*-comm m n) ⟩
  n + n * m   ≡⟨ sym (*-suc n m) ⟩
  n * suc m   ∎
