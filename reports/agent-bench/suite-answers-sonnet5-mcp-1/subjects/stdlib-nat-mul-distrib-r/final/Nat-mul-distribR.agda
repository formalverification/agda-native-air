-- Nat-mul-distribR.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Nat-mul-distribR.agda
--
-- Benchmark obligation: stdlib-nat-mul-distrib-r
-- Difficulty: non-obvious (Tier 3)
--
module Nat-mul-distribR where

open import AgdaDojang.Debug

open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ ; _*_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )

-- Prerequisite (provided, not to be proved here)
open import Data.Nat.Properties using ( +-assoc )

*-distribʳ-+ : ∀ (m n p : ℕ) → (n + p) * m ≡ n * m + p * m
*-distribʳ-+ m n p = go n
  where
    trans′ : ∀ {A : Set} {x y z : A} → x ≡ y → y ≡ z → x ≡ z
    trans′ refl eq = eq

    go : ∀ n → (n + p) * m ≡ n * m + p * m
    go zero = refl
    go (suc n) = trans′ (cong (m +_) (go n)) (sym (+-assoc m (n * m) (p * m)))
