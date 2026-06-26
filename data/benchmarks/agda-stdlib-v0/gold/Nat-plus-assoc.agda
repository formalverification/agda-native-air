-- Nat-plus-assoc.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-plus-assoc.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-plus-assoc
--
module Nat-plus-assoc where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

+-assoc : ∀ (m n p : ℕ) → (m + n) + p ≡ m + (n + p)
+-assoc zero    n p = refl
+-assoc (suc m) n p = cong suc (+-assoc m n p)
