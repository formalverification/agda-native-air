-- Nat-plus-identityR.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-plus-identityR.agda
--
-- Benchmark obligation: stdlib-nat-plus-identity-r
-- Difficulty: compositional (Tier 2)
-- Source: Data.Nat.Properties
-- Strategy: induction on n; base refl, step cong suc IH
--
module Nat-plus-identityR where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

+-identityʳ : ∀ (n : ℕ) → n + 0 ≡ n
+-identityʳ n = {!!}
