-- Nat-plus-assoc.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-plus-assoc.agda
--
-- Benchmark obligation: stdlib-nat-plus-assoc
-- Difficulty: compositional (Tier 2)
-- Source: Data.Nat.Properties
-- Strategy: induction on m; base refl, step cong suc IH
--
module Nat-plus-assoc where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

+-assoc : ∀ (m n p : ℕ) → (m + n) + p ≡ m + (n + p)
+-assoc m n p = {!!}
