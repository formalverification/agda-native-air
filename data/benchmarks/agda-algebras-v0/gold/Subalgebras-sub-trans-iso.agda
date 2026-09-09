-- Subalgebras-sub-trans-iso.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Subalgebras-sub-trans-iso.agda
--
-- Gold solution for benchmark obligation: algebras-subalgebras-sub-trans-iso
--
module Subalgebras-sub-trans-iso where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( _,_ ; proj₁ ; proj₂ )

open import Overture              using ( Signature )
open import Setoid.Algebras       using ( Algebra )
open import Setoid.Functions
open import Setoid.Homomorphisms
open import Setoid.Subalgebras

≤-trans-≅′ : {𝓞 𝓥 α ρᵃ β ρᵇ γ ρᶜ : Level} {𝑆 : Signature 𝓞 𝓥}
             {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ} {𝑪 : Algebra γ ρᶜ}
  →  𝑨 ≤ 𝑩 → 𝑩 ≅ 𝑪 → 𝑨 ≤ 𝑪
≤-trans-≅′ p B≅C =
  ⊙-hom (proj₁ p) (_≅_.to B≅C) ,
  ⊙-injective (proj₁ (proj₁ p)) (proj₁ (_≅_.to B≅C)) (proj₂ p) (≅toInjective B≅C)
