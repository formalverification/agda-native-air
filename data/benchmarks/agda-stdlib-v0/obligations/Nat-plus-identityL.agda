-- Nat-plus-identityL.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-plus-identityL.agda
--
-- Benchmark obligation: stdlib-nat-plus-identity-l
-- Difficulty: routine (Tier 1)
-- Source: Data.Nat.Properties
-- Strategy: refl (0 + n reduces to n by definition of _+_)
--
module Nat-plus-identityL where

open import AgdaDojang.Debug

open import Data.Nat.Base   using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

+-identityˡ : ∀ (n : ℕ) → 0 + n ≡ n
+-identityˡ n = {!!}
