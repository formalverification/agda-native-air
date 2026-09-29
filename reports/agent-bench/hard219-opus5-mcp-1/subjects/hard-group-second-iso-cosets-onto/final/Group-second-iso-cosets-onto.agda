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

module _ {α ρ ℓ : Level} (𝒢 : Group α ρ)
  (H : Pred 𝕌[ proj₁ 𝒢 ] ℓ) (H-sub : IsSubgroup 𝒢 H)
  (K : Pred 𝕌[ proj₁ 𝒢 ] ℓ) (K-sub : IsSubgroup 𝒢 K) (K-normal : Conjugate.IsNormal 𝒢 K)
  where
  private
    𝑮 = proj₁ 𝒢
    G = 𝕌[ 𝑮 ]
  open Complex 𝒢 using ( _∙ᶜ_ )
  open Coset 𝒢 K K-sub using ( _∼_ )

  private
    open Setoid 𝔻[ 𝑮 ] using ( _≈_ )
                       renaming ( refl to ≈refl ; sym to ≈sym ; trans to ≈trans )
    open Group-Op 𝒢 using  ( _∙_ ; ε ; _⁻¹ ; ∙-cong ; assoc-law
                           ; idˡ-law ; idʳ-law ; invˡ-law ; invʳ-law )
    open IsSubgroup K-sub using () renaming ( respects to K-respects
                                            ; ⁻¹-closed to K-⁻¹-closed )

    -- If x ≈ p ∙ q then x ∙ q ⁻¹ ≈ p.
    cancelʳ : ∀ {x} p q → x ≈ p ∙ q → x ∙ q ⁻¹ ≈ p
    cancelʳ p q x≈pq =
      ≈trans (∙-cong x≈pq ≈refl)
        (≈trans (assoc-law p q (q ⁻¹))
          (≈trans (∙-cong ≈refl (invʳ-law q)) (idʳ-law p)))

    -- Hence q ⁻¹ ≈ x ⁻¹ ∙ p, by inserting x ⁻¹ ∙ x for ε on the left.
    witness-eq : ∀ {x} p q → x ≈ p ∙ q → q ⁻¹ ≈ x ⁻¹ ∙ p
    witness-eq {x} p q x≈pq =
      ≈trans (≈sym (idˡ-law (q ⁻¹)))
        (≈trans (∙-cong (≈sym (invˡ-law x)) ≈refl)
          (≈trans (assoc-law (x ⁻¹) x (q ⁻¹))
            (∙-cong ≈refl (cancelʳ p q x≈pq))))

  second-iso-cosets-onto : ∀ {x} → x ∈ (H ∙ᶜ K) → Σ[ h ∈ G ] (h ∈ H × x ∼ h)
  second-iso-cosets-onto (p , q , p∈H , q∈K , x≈pq) =
    p , p∈H , K-respects (witness-eq p q x≈pq) (K-⁻¹-closed q∈K)
