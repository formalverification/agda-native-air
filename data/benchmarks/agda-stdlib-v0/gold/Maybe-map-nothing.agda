-- Maybe-map-nothing.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Maybe-map-nothing.agda
--
-- Gold solution for benchmark obligation: stdlib-maybe-map-nothing
--
module Maybe-map-nothing where

open import AgdaDojang.Debug

open import Data.Maybe.Base using ( Maybe ; nothing ; map )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

map-nothing : {A B : Set} {f : A → B} → map f nothing ≡ nothing
map-nothing = refl
