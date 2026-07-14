-- Maybe-map-nothing.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Maybe-map-nothing.agda
--
-- Benchmark obligation: stdlib-maybe-map-nothing
-- Difficulty: routine (Tier 1)
-- Source: Data.Maybe.Base
-- Strategy: refl (map f nothing reduces to nothing)
--
module Maybe-map-nothing where

open import AgdaDojang.Debug

open import Data.Maybe.Base using ( Maybe ; nothing ; map )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

map-nothing : {A B : Set} {f : A → B} → map f nothing ≡ nothing
map-nothing = {!!}
