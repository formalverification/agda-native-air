-- Nat-plus-suc.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-plus-suc.agda
--
-- Benchmark obligation: stdlib-nat-plus-suc
-- Difficulty: compositional (Tier 2)
-- Source: Data.Nat.Properties
-- Strategy: induction on m; base refl, step cong suc IH
--
module Nat-plus-suc where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

+-suc : ∀ (m n : ℕ) → m + suc n ≡ suc (m + n)
+-suc m n = {!!}
