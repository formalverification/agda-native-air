-- Nat-plus-identityL.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-plus-identityL.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-plus-identity-l
--
module Nat-plus-identityL where

open import AgdaDojang.Debug

open import Data.Nat.Base   using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

+-identityˡ : ∀ (n : ℕ) → 0 + n ≡ n
+-identityˡ n = refl
