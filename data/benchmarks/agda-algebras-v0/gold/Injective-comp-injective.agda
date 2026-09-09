-- Injective-comp-injective.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Injective-comp-injective.agda
--
-- Gold solution for benchmark obligation: algebras-injective-comp-injective
--
module Injective-comp-injective where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Relation.Binary  using ( Setoid )
open import Function.Base    using ( _∘_ )
open import Function.Bundles using ( Func )

open import Setoid.Functions using ( IsInjective ; _⊙_ )

⊙-injective′ : {α ρᵃ β ρᵇ γ ρᶜ : Level}
               {𝑨 : Setoid α ρᵃ} {𝑩 : Setoid β ρᵇ} {𝑪 : Setoid γ ρᶜ}
               (f : Func 𝑨 𝑩) (g : Func 𝑩 𝑪)
  →  IsInjective f → IsInjective g → IsInjective (g ⊙ f)
⊙-injective′ f g finj ginj = finj ∘ ginj
