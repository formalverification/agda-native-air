-- Nat-plus-comm.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Nat-plus-comm.agda
--
-- Gold solution for benchmark obligation: stdlib-nat-plus-comm
--
module Nat-plus-comm where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )

open import Data.Nat.Properties using ( +-identityʳ ; +-suc )

+-comm : ∀ (m n : ℕ) → m + n ≡ n + m
+-comm zero    n = sym (+-identityʳ n)
+-comm (suc m) n = begin
  suc m + n     ≡⟨⟩
  suc (m + n)   ≡⟨ cong suc (+-comm m n) ⟩
  suc (n + m)   ≡⟨ sym (+-suc n m) ⟩
  n + suc m     ∎
  where open import Relation.Binary.PropositionalEquality.Properties
              using ( module ≡-Reasoning )
        open ≡-Reasoning
