-- Subalgebra-subdirect-into-product.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Subalgebra-subdirect-into-product.agda
--
-- Benchmark obligation: comp-subalgebra-subdirect-into-product
-- Difficulty: compositional
-- Source: Setoid.Subalgebras.Subdirect.Basic (subdirect→≤), Setoid.Subalgebras.Properties (⨅-≤, ≤-trans)
-- Import stratum: composition
-- Strategy: a subdirect embedding makes B a subalgebra of the product of the Bᵢ, which is a subalgebra of the product of the Aᵢ; compose the two
--
-- An algebra subdirectly embedded in a product of subalgebras of the Aᵢ is a subalgebra of the product of the Aᵢ.
--
module Subalgebra-subdirect-into-product where

open import AgdaDojang.Debug

open import Level                                    using ( Level )
open import Overture                                 using ( 𝓞 ; 𝓥 ; Signature )
open import Setoid.Algebras                          using ( Algebra ; ⨅ )
open import Setoid.Subalgebras.Basic                 using ( _≤_ )
open import Setoid.Subalgebras.Properties            using ( ≤-reflexive )
open import Setoid.Subalgebras.Subdirect.Basic       using ( SubdirectEmbedding )

module _ {α ρ β ρᵇ ι : Level} {𝑆 : Signature 𝓞 𝓥} {I : Set ι}
  {𝑩 : Algebra {𝑆 = 𝑆} β ρᵇ} {ℬ 𝒜 : I → Algebra {𝑆 = 𝑆} α ρ}
  where

  subdirect-into-product : SubdirectEmbedding {𝑩 = 𝑩} ℬ → (∀ i → ℬ i ≤ 𝒜 i) → 𝑩 ≤ ⨅ 𝒜
  subdirect-into-product e ℬ≤𝒜 = {!!}
