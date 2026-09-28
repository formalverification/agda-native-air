-- Variety-image-of-product.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Variety-image-of-product.agda
--
-- Benchmark obligation: comp-variety-image-of-product
-- Difficulty: non-obvious
-- Source: Setoid.Varieties.Properties (⊧-H-invar, ⊧-P-invar), Setoid.Homomorphisms.HomomorphicImages (HomImage-≅)
-- Import stratum: composition
-- Strategy: the product models the identity; an isomorphic copy of a homomorphic image of the product is a homomorphic image of it; identities pass to homomorphic images
--
-- An identity true in every factor holds in every isomorphic copy of a homomorphic image of the product.
--
module Variety-image-of-product where

open import AgdaDojang.Debug

open import Level                                   using ( Level ; _⊔_ )
open import Overture                                using ( 𝓞 ; 𝓥 ; Signature )
open import Overture.Terms                          using ( Term )
open import Setoid.Algebras                         using ( Algebra ; ⨅ )
open import Setoid.Homomorphisms.Isomorphisms       using ( _≅_ )
open import Setoid.Homomorphisms.HomomorphicImages  using ( _IsHomImageOf_ )
open import Setoid.Varieties.Properties             using ( ⊧-I-invar )
open import Setoid.Varieties.SoundAndComplete       using ( _⊧_ ; _≈̇_ )

module _ {α ρᵃ β ρᵇ χ ι : Level} {𝑆 : Signature 𝓞 𝓥} {X : Set χ} {I : Set ι}
  {𝒜 : I → Algebra {𝑆 = 𝑆} α ρᵃ} {𝑨 : Algebra {𝑆 = 𝑆} (α ⊔ ι) (ρᵃ ⊔ ι)} {𝑩 : Algebra {𝑆 = 𝑆} β ρᵇ}
  {p q : Term X}
  where

  image-of-product-models : (∀ i → 𝒜 i ⊧ (p ≈̇ q)) → 𝑨 IsHomImageOf ⨅ 𝒜 → 𝑨 ≅ 𝑩 → 𝑩 ⊧ (p ≈̇ q)
  image-of-product-models 𝒜⊧ A◃⨅𝒜 A≅B = {!!}
