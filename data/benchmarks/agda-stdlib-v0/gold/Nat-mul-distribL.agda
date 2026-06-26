-- Nat-mul-distribL.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-mul-distribL.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-mul-distrib-l
--
module Nat-mul-distribL where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; _+_ ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; cong₂ )
open import Relation.Binary.PropositionalEquality.Properties using ( module ≡-Reasoning )
open ≡-Reasoning

-- Prerequisites (provided, not to be proved here)
open import Data.Nat.Properties using ( *-comm ; *-distribʳ-+ )

*-distribˡ-+ : ∀ (m n p : ℕ) → m * (n + p) ≡ m * n + m * p
*-distribˡ-+ m n p = begin
  m * (n + p)     ≡⟨ *-comm m (n + p) ⟩
  (n + p) * m     ≡⟨ *-distribʳ-+ m n p ⟩
  n * m + p * m   ≡⟨ cong₂ _+_ (*-comm n m) (*-comm p m) ⟩
  m * n + m * p   ∎
