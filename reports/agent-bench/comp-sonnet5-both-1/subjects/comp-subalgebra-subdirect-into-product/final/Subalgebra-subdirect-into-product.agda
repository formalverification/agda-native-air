-- Subalgebra-subdirect-into-product.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Subalgebra-subdirect-into-product.agda
--
-- Benchmark obligation: comp-subalgebra-subdirect-into-product
-- Difficulty: compositional
-- Import stratum: composition
--
-- An algebra subdirectly embedded in a product of subalgebras of the Aᵢ is a subalgebra of the product of the Aᵢ.
--
module Subalgebra-subdirect-into-product where

open import AgdaDojang.Debug

open import Data.Product                             using ( _,_ )
open import Level                                    using ( Level )
open import Overture                                 using ( 𝓞 ; 𝓥 ; Signature ; proj₁ ; proj₂ )
open import Setoid.Algebras                          using ( Algebra ; ⨅ )
open import Setoid.Subalgebras.Basic                 using ( _≤_ )
open import Setoid.Subalgebras.Properties            using ( ≤-reflexive )
open import Setoid.Subalgebras.Subdirect.Basic       using ( SubdirectEmbedding ; embed-inj )
open import Setoid.Homomorphisms.Products            using ( ⨅-hom )
open import Setoid.Homomorphisms.Properties          using ( ⊙-hom )
open import Setoid.Functions.Injective               using ( IsInjective ; ⊙-injective )

module _ {α ρ β ρᵇ ι : Level} {𝑆 : Signature 𝓞 𝓥} {I : Set ι}
  {𝑩 : Algebra {𝑆 = 𝑆} β ρᵇ} {ℬ 𝒜 : I → Algebra {𝑆 = 𝑆} α ρ}
  where

  subdirect-into-product : SubdirectEmbedding {𝑩 = 𝑩} ℬ → (∀ i → ℬ i ≤ 𝒜 i) → 𝑩 ≤ ⨅ 𝒜
  subdirect-into-product (h , emb) ℬ≤𝒜 = ⊙-hom h prodmap , ⊙-injective (proj₁ h) (proj₁ prodmap) (embed-inj emb) prod-inj
    where
    prodmap = ⨅-hom ℬ 𝒜 (λ i → proj₁ (ℬ≤𝒜 i))

    prod-inj : IsInjective (proj₁ prodmap)
    prod-inj xy = λ i → proj₂ (ℬ≤𝒜 i) (xy i)
