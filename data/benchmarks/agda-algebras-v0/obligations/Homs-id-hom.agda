-- Homs-id-hom.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Homs-id-hom.agda
--
-- Benchmark obligation: algebras-homs-id-hom
-- Difficulty: compositional
-- Source: Setoid.Homomorphisms.Basic (agda-algebras)
-- Import stratum: wholesale
-- Strategy: pairing
--
module Homs-id-hom where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Relation.Binary  using ( Setoid )
open import Data.Product     using ( _,_ )
open import Relation.Binary.PropositionalEquality using ( refl )

open import Overture             using ( Signature )
open import Setoid.Algebras      using ( Algebra ; 𝔻[_] )
open import Setoid.Functions
open import Setoid.Homomorphisms

𝒾𝒹′ : {𝓞 𝓥 α ρᵃ : Level} {𝑆 : Signature 𝓞 𝓥} {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} → hom 𝑨 𝑨
𝒾𝒹′ {𝑨 = 𝑨} = {!!}
