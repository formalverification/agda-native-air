-- Homs-comp-hom.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Homs-comp-hom.agda
--
-- Gold solution for benchmark obligation: algebras-homs-comp-hom
--
module Homs-comp-hom where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( _,_ ; proj₁ ; proj₂ )

open import Overture              using ( Signature )
open import Setoid.Algebras       using ( Algebra )
open import Setoid.Functions      using ( _⊙_ )
open import Setoid.Homomorphisms  using ( hom ; ⊙-is-hom )

⊙-hom′ : {𝓞 𝓥 α ρᵃ β ρᵇ γ ρᶜ : Level} {𝑆 : Signature 𝓞 𝓥}
         {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ} {𝑪 : Algebra γ ρᶜ}
  →  hom 𝑨 𝑩 → hom 𝑩 𝑪 → hom 𝑨 𝑪
⊙-hom′ f g = proj₁ g ⊙ proj₁ f , ⊙-is-hom (proj₂ f) (proj₂ g)
