-- Variety-subdirect-product-models.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Variety-subdirect-product-models.agda
--
-- Benchmark obligation: comp-variety-subdirect-product-models
-- Difficulty: non-obvious
-- Import stratum: composition
--
-- An identity true in every factor holds in any algebra subdirectly embedded in their product.
--
module Variety-subdirect-product-models where

open import AgdaDojang.Debug

open import Level                                 using ( Level )
open import Overture                              using ( 𝓞 ; 𝓥 ; Signature )
open import Overture.Terms                        using ( Term )
open import Setoid.Algebras                       using ( Algebra )
open import Setoid.Subalgebras.Subdirect.Basic    using ( SubdirectEmbedding )
open import Setoid.Varieties.Properties           using ( ⊧-I-invar )
open import Setoid.Varieties.SoundAndComplete     using ( _⊧_ ; _≈̇_ )

open import Setoid.Subalgebras.Subdirect.Basic    using ( subdirect→≤ )
open import Setoid.Varieties.Properties           using ( ⊧-S-invar ; ⊧-P-invar )

module _ {α ρ β ρᵇ χ ι : Level} {𝑆 : Signature 𝓞 𝓥} {X : Set χ} {I : Set ι}
  {𝑩 : Algebra {𝑆 = 𝑆} β ρᵇ} {𝒜 : I → Algebra {𝑆 = 𝑆} α ρ} {p q : Term X}
  where

  subdirect-product-models : (∀ i → 𝒜 i ⊧ (p ≈̇ q)) → SubdirectEmbedding {𝑩 = 𝑩} 𝒜 → 𝑩 ⊧ (p ≈̇ q)
  subdirect-product-models 𝒜⊧ e = ⊧-S-invar {p = p} {q} (⊧-P-invar {p = p} {q} 𝒜 𝒜⊧) (subdirect→≤ 𝒜 e)
