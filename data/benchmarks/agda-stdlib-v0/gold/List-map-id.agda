-- List-map-id.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/List-map-id.agda
--
-- Gold solution for benchmark obligation: stdlib-list-map-id
--
module List-map-id where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; [] ; _∷_ ; map )
open import Function.Base  using ( id )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

map-id : ∀ {A : Set} (xs : List A) → map id xs ≡ xs
map-id []       = refl
map-id (x ∷ xs) = cong (x ∷_) (map-id xs)
