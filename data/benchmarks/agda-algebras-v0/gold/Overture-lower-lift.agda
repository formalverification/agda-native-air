-- Overture-lower-lift.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Overture-lower-lift.agda
--
-- Gold solution for benchmark obligation: algebras-overture-lower-lift
--
module Overture-lower-lift where

open import AgdaDojang.Debug

open import Agda.Primitive  using ( Level )
open import Level           using ( lift ; lower )
open import Function.Base   using ( _∘_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

open import Overture.Basic  using ( 𝑖𝑑 )

lower∼lift : {a b : Level} {A : Set a} → lower {a}{b} ∘ lift ≡ 𝑖𝑑 A
lower∼lift = refl
