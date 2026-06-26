-- Nat-mul-identityR.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-mul-identityR.agda
--
-- Benchmark obligation: stdlib-nat-mul-identity-r
-- Difficulty: compositional (Tier 2)
-- Source: Data.Nat.Properties
-- Strategy: induction on n; base refl, step cong suc IH
--
module Nat-mul-identityR where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

*-identityʳ : ∀ (n : ℕ) → n * 1 ≡ n
*-identityʳ n = {!!}
