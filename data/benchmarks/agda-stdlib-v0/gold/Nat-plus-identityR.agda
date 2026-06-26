-- Nat-plus-identityR.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-plus-identityR.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-plus-identity-r
--
module Nat-plus-identityR where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

+-identityʳ : ∀ (n : ℕ) → n + 0 ≡ n
+-identityʳ zero    = refl
+-identityʳ (suc n) = cong suc (+-identityʳ n)
