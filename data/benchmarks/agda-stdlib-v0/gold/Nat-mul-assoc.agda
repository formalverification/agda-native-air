-- Nat-mul-assoc.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-mul-assoc.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-mul-assoc
--
module Nat-mul-assoc where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )
open import Relation.Binary.PropositionalEquality.Properties using ( module ≡-Reasoning )
open ≡-Reasoning

-- Prerequisite (provided, not to be proved here)
open import Data.Nat.Properties using ( *-distribʳ-+ )

*-assoc : ∀ (m n p : ℕ) → (m * n) * p ≡ m * (n * p)
*-assoc zero    n p = refl
*-assoc (suc m) n p = begin
  (suc m * n) * p       ≡⟨⟩
  (n + m * n) * p       ≡⟨ *-distribʳ-+ p n (m * n) ⟩
  n * p + (m * n) * p   ≡⟨ cong (n * p +_) (*-assoc m n p) ⟩
  n * p + m * (n * p)   ≡⟨⟩
  suc m * (n * p)       ∎
