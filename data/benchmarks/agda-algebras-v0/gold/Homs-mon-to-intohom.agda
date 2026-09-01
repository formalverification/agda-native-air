-- Homs-mon-to-intohom.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Homs-mon-to-intohom.agda
--
-- Gold solution for benchmark obligation: algebras-homs-mon-to-intohom
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
mon→intohom′ m = (proj₁ m , IsMon.isHom (proj₂ m)) , IsMon.isInjective (proj₂ m)
