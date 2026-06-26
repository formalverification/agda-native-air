-- List-length-append.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/List-length-append.agda
--
-- Gold solution for benchmark obligation: stdlib-list-length-append
--
module List-length-append where

open import AgdaDojang.Debug

open import Data.Nat.Base  using ( ℕ ; suc ; _+_ )
open import Data.List.Base using ( List ; [] ; _∷_ ; _++_ ; length )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

length-++ : ∀ {A : Set} (xs ys : List A) → length (xs ++ ys) ≡ length xs + length ys
length-++ []       ys = refl
length-++ (x ∷ xs) ys = cong suc (length-++ xs ys)
