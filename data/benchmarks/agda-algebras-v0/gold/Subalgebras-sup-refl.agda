-- Subalgebras-sup-refl.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Subalgebras-sup-refl.agda
--
-- Gold solution for benchmark obligation: algebras-subalgebras-sup-refl
--
module Subalgebras-sup-refl where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Function.Base    using ( _∘_ )

open import Overture              using ( Signature )
open import Setoid.Algebras       using ( Algebra )
open import Setoid.Homomorphisms  using ( _≅_ ; ≅-sym )
open import Setoid.Subalgebras    using ( _≥_ ; ≅→≤ )

≥-refl′ : {𝓞 𝓥 α ρᵃ : Level} {𝑆 : Signature 𝓞 𝓥}
          {𝑨 𝑩 : Algebra {𝑆 = 𝑆} α ρᵃ}
  →  𝑨 ≅ 𝑩 → 𝑨 ≥ 𝑩
≥-refl′ = ≅→≤ ∘ ≅-sym
