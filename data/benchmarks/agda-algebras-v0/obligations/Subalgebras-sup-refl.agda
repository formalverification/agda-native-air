-- Subalgebras-sup-refl.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Subalgebras-sup-refl.agda
--
-- Benchmark obligation: algebras-subalgebras-sup-refl
-- Difficulty: compositional
-- Source: Setoid.Subalgebras.Properties (agda-algebras)
-- Import stratum: using
-- Strategy: composition
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
≥-refl′ = {!!}
