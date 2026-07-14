-- Nat-mul-distribR.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-mul-distribR.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-mul-distrib-r
--
module Nat-mul-distribR where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )
open import Relation.Binary.PropositionalEquality.Properties using ( module ≡-Reasoning )
open ≡-Reasoning

-- Prerequisite (provided, not to be proved here)
open import Data.Nat.Properties using ( +-assoc )

*-distribʳ-+ : ∀ (m n p : ℕ) → (n + p) * m ≡ n * m + p * m
*-distribʳ-+ m zero    p = refl
*-distribʳ-+ m (suc n) p = begin
  (suc n + p) * m       ≡⟨⟩
  m + (n + p) * m       ≡⟨ cong (m +_) (*-distribʳ-+ m n p) ⟩
  m + (n * m + p * m)   ≡⟨ sym (+-assoc m (n * m) (p * m)) ⟩
  m + n * m + p * m     ≡⟨⟩
  suc n * m + p * m     ∎
