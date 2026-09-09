-- Homs-mon-to-intohom.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Homs-mon-to-intohom.agda
--
-- Benchmark obligation: algebras-homs-mon-to-intohom
-- Difficulty: compositional
-- Source: Setoid.Homomorphisms.Basic (agda-algebras)
-- Import stratum: wholesale
-- Strategy: pairing
--
module Homs-mon-to-intohom where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( _,_ ; proj₁ ; proj₂ ; Σ-syntax )

open import Overture             using ( Signature )
open import Setoid.Algebras      using ( Algebra )
open import Setoid.Functions     using ( IsInjective )
open import Setoid.Homomorphisms

mon→intohom′ : {𝓞 𝓥 α ρᵃ β ρᵇ : Level} {𝑆 : Signature 𝓞 𝓥}
               {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ}
  →  mon 𝑨 𝑩 → Σ[ h ∈ hom 𝑨 𝑩 ] IsInjective (proj₁ h)
mon→intohom′ m = {!!}
