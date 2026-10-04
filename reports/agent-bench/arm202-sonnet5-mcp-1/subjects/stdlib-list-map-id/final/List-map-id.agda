-- List-map-id.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/List-map-id.agda
--
-- Benchmark obligation: stdlib-list-map-id
-- Difficulty: compositional (Tier 2)
--
module List-map-id where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; [] ; _∷_ ; map )
open import Function.Base  using ( id )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

map-id : ∀ {A : Set} (xs : List A) → map id xs ≡ xs
map-id [] = refl
map-id (x ∷ xs) = cong (x ∷_) (map-id xs)
