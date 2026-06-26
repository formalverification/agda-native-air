-- List-map-compose.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/List-map-compose.agda
--
-- Benchmark obligation: stdlib-list-map-compose
-- Difficulty: compositional (Tier 2)
-- Source: Data.List.Properties
-- Strategy: induction on xs; base refl, step cong (f (g x) ∷_) IH
--
module List-map-compose where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; [] ; _∷_ ; map )
open import Function.Base  using ( _∘_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

map-compose : ∀ {A B C : Set} (f : B → C) (g : A → B) (xs : List A) →
              map (f ∘ g) xs ≡ map f (map g xs)
map-compose f g xs = {!!}
