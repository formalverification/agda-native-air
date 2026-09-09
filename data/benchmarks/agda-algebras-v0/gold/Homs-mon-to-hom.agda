-- Homs-mon-to-hom.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Homs-mon-to-hom.agda
--
-- Gold solution for benchmark obligation: algebras-homs-mon-to-hom
--
module Homs-mon-to-hom where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( proj₂ )

open import Overture             using ( Signature )
open import Setoid.Algebras      using ( Algebra )
open import Setoid.Homomorphisms

mon→hom′ : {𝓞 𝓥 α ρᵃ β ρᵇ : Level} {𝑆 : Signature 𝓞 𝓥}
           {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ}
  →  mon 𝑨 𝑩 → hom 𝑨 𝑩
mon→hom′ m = IsMon.HomReduct (proj₂ m)
