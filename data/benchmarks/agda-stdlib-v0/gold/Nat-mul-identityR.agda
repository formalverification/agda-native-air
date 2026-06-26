-- Nat-mul-identityR.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-mul-identityR.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-mul-identity-r
--
module Nat-mul-identityR where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

*-identityʳ : ∀ (n : ℕ) → n * 1 ≡ n
*-identityʳ zero    = refl
*-identityʳ (suc n) = cong suc (*-identityʳ n)
