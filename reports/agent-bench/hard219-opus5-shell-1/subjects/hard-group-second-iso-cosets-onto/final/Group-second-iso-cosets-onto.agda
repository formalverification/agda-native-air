-- Group-second-iso-cosets-onto.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/obligations/Group-second-iso-cosets-onto.agda
--
-- Benchmark obligation: hard-group-second-iso-cosets-onto
-- Difficulty: non-obvious
-- Import stratum: novel
--
-- The inclusion H → HK is onto the cosets of K in HK: every element of the complex product H ∙ᶜ K lies in the K-coset of some element of H.
--
module Group-second-iso-cosets-onto where

open import AgdaDojang.Debug

open import Data.Product                  using ( _,_ ; _×_ ; Σ-syntax ; proj₁ ; proj₂ )
open import Level                         using ( Level )
open import Relation.Binary               using ( Setoid )
open import Relation.Unary                using ( Pred ; _∈_ )

open import Classical.Structures.Group.Basic         using ( Group ; module Group-Op )
open import Classical.Structures.Group.Subgroups     using ( IsSubgroup )
open import Classical.Structures.Group.Conjugation   using ( module Conjugate )
open import Setoid.Algebras.Basic                    using ( 𝕌[_] ; 𝔻[_] )
open import Classical.Structures.Group.Complexes     using ( module Complex )
open import Classical.Structures.Group.Cosets        using ( module Coset )

open import Classical.Bundles.Group                  using ( ⟨_⟩ᵍᵖ )
import Algebra.Properties.Group as GroupProperties
import Relation.Binary.Reasoning.Setoid as SetoidReasoning

module _ {α ρ ℓ : Level} (𝒢 : Group α ρ)
  (H : Pred 𝕌[ proj₁ 𝒢 ] ℓ) (H-sub : IsSubgroup 𝒢 H)
  (K : Pred 𝕌[ proj₁ 𝒢 ] ℓ) (K-sub : IsSubgroup 𝒢 K) (K-normal : Conjugate.IsNormal 𝒢 K)
  where
  private
    𝑮 = proj₁ 𝒢
    G = 𝕌[ 𝑮 ]
  open Complex 𝒢 using ( _∙ᶜ_ )
  open Coset 𝒢 K K-sub using ( _∼_ )

  open Setoid 𝔻[ 𝑮 ]            using ( _≈_ )
                                renaming ( refl to ≈refl ; sym to ≈sym )
  open SetoidReasoning 𝔻[ 𝑮 ]
  open Group-Op 𝒢               using ( _∙_ ; ε ; _⁻¹ ; ∙-cong ; ⁻¹-cong
                                      ; assoc-law ; invˡ-law ; idʳ-law )
  open GroupProperties ⟨ 𝒢 ⟩ᵍᵖ  using ( ⁻¹-anti-homo-∙ )
  open IsSubgroup K-sub         using () renaming ( respects  to K-respects
                                                  ; ⁻¹-closed to K-⁻¹-closed )

  second-iso-cosets-onto : ∀ {x} → x ∈ (H ∙ᶜ K) → Σ[ h ∈ G ] (h ∈ H × x ∼ h)
  second-iso-cosets-onto {x} (p , q , p∈H , q∈K , x≈pq) =
    p , p∈H , K-respects coset-eq (K-⁻¹-closed q∈K)
    where
    coset-eq : q ⁻¹ ≈ x ⁻¹ ∙ p
    coset-eq = ≈sym (begin
      x ⁻¹ ∙ p            ≈⟨ ∙-cong (⁻¹-cong x≈pq) ≈refl ⟩
      (p ∙ q) ⁻¹ ∙ p      ≈⟨ ∙-cong (⁻¹-anti-homo-∙ p q) ≈refl ⟩
      q ⁻¹ ∙ p ⁻¹ ∙ p     ≈⟨ assoc-law (q ⁻¹) (p ⁻¹) p ⟩
      q ⁻¹ ∙ (p ⁻¹ ∙ p)   ≈⟨ ∙-cong ≈refl (invˡ-law p) ⟩
      q ⁻¹ ∙ ε            ≈⟨ idʳ-law (q ⁻¹) ⟩
      q ⁻¹                ∎)
