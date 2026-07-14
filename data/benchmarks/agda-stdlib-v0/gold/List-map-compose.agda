-- List-map-compose.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/List-map-compose.agda
--
-- Gold solution for benchmark obligation: stdlib-list-map-compose
--
module List-map-compose where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; [] ; _∷_ ; map )
open import Function.Base  using ( _∘_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

map-compose : ∀ {A B C : Set} (f : B → C) (g : A → B) (xs : List A) →
              map (f ∘ g) xs ≡ map f (map g xs)
map-compose f g []       = refl
map-compose f g (x ∷ xs) = cong (f (g x) ∷_) (map-compose f g xs)
