-- Nat-plus-suc.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-plus-suc.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-plus-suc
--
module Nat-plus-suc where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

+-suc : ∀ (m n : ℕ) → m + suc n ≡ suc (m + n)
+-suc zero    n = refl
+-suc (suc m) n = cong suc (+-suc m n)
