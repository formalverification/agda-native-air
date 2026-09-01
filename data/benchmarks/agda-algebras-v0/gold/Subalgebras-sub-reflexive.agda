-- Subalgebras-sub-reflexive.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Subalgebras-sub-reflexive.agda
--
-- Gold solution for benchmark obligation: algebras-subalgebras-sub-reflexive
--
module Subalgebras-sub-reflexive where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( _,_ )

open import Overture              using ( Signature )
open import Setoid.Algebras       using ( Algebra ; 𝔻[_] )
open import Setoid.Functions
open import Setoid.Homomorphisms
open import Setoid.Subalgebras

≤-reflexive′ : {𝓞 𝓥 α ρᵃ : Level} {𝑆 : Signature 𝓞 𝓥}
               {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ}
  →  𝑨 ≤ 𝑨
≤-reflexive′ {𝑨 = 𝑨} = 𝒾𝒹 , id-is-injective {𝑨 = 𝔻[ 𝑨 ]}
