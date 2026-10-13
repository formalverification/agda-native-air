-- List-length-append.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/List-length-append.agda
--
-- Benchmark obligation: stdlib-list-length-append
-- Difficulty: compositional (Tier 2)
--
module List-length-append where

open import AgdaDojang.Debug

open import Data.Nat.Base  using ( ℕ ; suc ; _+_ )
open import Data.List.Base using ( List ; [] ; _∷_ ; _++_ ; length )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

length-++ : ∀ {A : Set} (xs ys : List A) → length (xs ++ ys) ≡ length xs + length ys
length-++ [] ys = refl
length-++ (x ∷ xs) ys = cong suc (length-++ xs ys)
