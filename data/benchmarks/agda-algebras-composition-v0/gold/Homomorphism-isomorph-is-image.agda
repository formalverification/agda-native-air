-- Homomorphism-isomorph-is-image.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/gold/Homomorphism-isomorph-is-image.agda
--
-- Benchmark obligation: comp-homomorphism-isomorph-is-image
-- Difficulty: compositional
-- Source: Setoid.Homomorphisms.HomomorphicImages (HomImage-≅', IdHomImage)
-- Import stratum: composition
-- Strategy: A is a homomorphic image of itself, and A ≅ B carries the source of that image across to B
--
-- An algebra isomorphic to B is a homomorphic image of B.
--
module Homomorphism-isomorph-is-image where

open import AgdaDojang.Debug

open import Level                                   using ( Level )
open import Overture                                using ( 𝓞 ; 𝓥 ; Signature )
open import Setoid.Algebras                         using ( Algebra )
open import Setoid.Homomorphisms.Isomorphisms       using ( _≅_ ; ≅-refl )
open import Setoid.Homomorphisms.HomomorphicImages  using ( _IsHomImageOf_ )

module _ {α ρᵃ : Level} {𝑆 : Signature 𝓞 𝓥} {𝑨 𝑩 : Algebra {𝑆 = 𝑆} α ρᵃ} where

  isomorph-is-image : 𝑨 ≅ 𝑩 → 𝑨 IsHomImageOf 𝑩
  isomorph-is-image A≅B =
    Setoid.Homomorphisms.HomomorphicImages.HomImage-≅'
      Setoid.Homomorphisms.HomomorphicImages.IdHomImage A≅B
