-- Group-kernel-normal-subgroup.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/obligations/Group-kernel-normal-subgroup.agda
--
-- Benchmark obligation: hard-group-kernel-normal-subgroup
-- Difficulty: non-obvious
-- Source: Classical.Structures.Group with Setoid.Homomorphisms (kernels exist only as congruences, Setoid.Homomorphisms.Kernels)
-- Import stratum: novel
-- Strategy: the kernel predicate respects ≈ by cong; closure by the homomorphism law; normality by conjugating ε; the fibers are the cosets because h (x ⁻¹ ∙ y) ≈ (h x) ⁻¹ ∙ h y
--
-- The kernel of a group homomorphism, as the predicate { x ∣ h x ≈ ε }, is a normal subgroup, and its coset relation is the kernel congruence: x ⁻¹ ∙ y lies in the kernel exactly when h x ≈ h y.
--
module Group-kernel-normal-subgroup where

open import AgdaDojang.Debug

open import Data.Product                  using ( _,_ ; _×_ ; Σ-syntax ; proj₁ ; proj₂ )
open import Level                         using ( Level ; _⊔_ )
open import Relation.Binary               using ( Setoid )
open import Relation.Binary.Definitions   using ( _Respects_ )
open import Relation.Unary                using ( Pred ; _∈_ ; _⊆_ )

open import Classical.Structures.Group.Basic         using ( Group ; module Group-Op )
open import Classical.Structures.Group.Subgroups     using ( IsSubgroup )
open import Classical.Structures.Group.Conjugation   using ( module Conjugate )
open import Setoid.Algebras.Basic                    using ( 𝕌[_] ; 𝔻[_] )
open import Function.Bundles              using () renaming ( Func to _⟶_ )
open import Setoid.Homomorphisms.Basic               using ( hom )

-- Additional imports used by the proof below --------------------------------------
open import Classical.Operations                     using ( pair )
open import Classical.Signatures.Group               using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Group.Subgroups     using ( mkIsSubgroup ; interp-tuple-∙
                                                           ; interp-tuple-ε ; interp-tuple-⁻¹ )
open import Setoid.Homomorphisms.Basic               using ( IsHom )

import Relation.Binary.Reasoning.Setoid as SetoidReasoning

module _ {α ρ β ρᵇ : Level} (𝒢 : Group α ρ) (𝓗 : Group β ρᵇ)
  ((hmap , hhom) : hom (proj₁ 𝒢) (proj₁ 𝓗))
  where
  private
    𝑮 = proj₁ 𝒢
    G = 𝕌[ 𝑮 ]
    h = _⟶_.to hmap
  open Setoid 𝔻[ proj₁ 𝓗 ] using () renaming ( _≈_ to _≈ᴴ_ )
  open Group-Op 𝒢 using ( _∙_ ; _⁻¹ )
  open Group-Op 𝓗 using () renaming ( ε to εᴴ )

  Ker : Pred G ρᵇ
  Ker x = h x ≈ᴴ εᴴ

  -- Extra accessors for the two groups and the codomain setoid.
  open Setoid 𝔻[ 𝑮 ] using ( _≈_ )
  open Setoid 𝔻[ proj₁ 𝓗 ] using ()
    renaming ( refl to ≈ᴴrefl ; sym to ≈ᴴsym ; trans to ≈ᴴtrans )
  open Group-Op 𝒢 using ( ε )
  open Group-Op 𝓗 using ()
    renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ ; ∙-cong to ∙ᴴ-cong ; ⁻¹-cong to ⁻¹ᴴ-cong
             ; assoc-law to assocᴴ ; idˡ-law to idˡᴴ ; idʳ-law to idʳᴴ
             ; invˡ-law to invˡᴴ ; invʳ-law to invʳᴴ )
  open SetoidReasoning 𝔻[ proj₁ 𝓗 ]

  private
    -- The three curried homomorphism laws, obtained from `compatible` by
    -- bridging the tuple-indexed interpretations of the codomain.
    hom-∙ : ∀ x y → h (x ∙ y) ≈ᴴ (h x ∙ᴴ h y)
    hom-∙ x y = ≈ᴴtrans (IsHom.compatible hhom {∙-Op} {pair x y}) (interp-tuple-∙ 𝓗 _)

    hom-ε : h ε ≈ᴴ εᴴ
    hom-ε = ≈ᴴtrans (IsHom.compatible hhom {ε-Op} {λ ()}) (interp-tuple-ε 𝓗 _)

    hom-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ (h x) ⁻¹ᴴ
    hom-⁻¹ x = ≈ᴴtrans (IsHom.compatible hhom {⁻¹-Op} {λ _ → x}) (interp-tuple-⁻¹ 𝓗 _)

    ε⁻¹ᴴ≈εᴴ : (εᴴ ⁻¹ᴴ) ≈ᴴ εᴴ
    ε⁻¹ᴴ≈εᴴ = ≈ᴴtrans (≈ᴴsym (idʳᴴ (εᴴ ⁻¹ᴴ))) (invˡᴴ εᴴ)

    -- The kernel respects the setoid equality, by congruence of h.
    Ker-respects : Ker Respects _≈_
    Ker-respects x≈y hx≈ε = ≈ᴴtrans (≈ᴴsym (_⟶_.cong hmap x≈y)) hx≈ε

    Ker-∙ : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
    Ker-∙ {x} {y} kx ky = begin
      h (x ∙ y)      ≈⟨ hom-∙ x y ⟩
      (h x ∙ᴴ h y)   ≈⟨ ∙ᴴ-cong kx ky ⟩
      (εᴴ ∙ᴴ εᴴ)     ≈⟨ idˡᴴ εᴴ ⟩
      εᴴ             ∎

    Ker-ε : ε ∈ Ker
    Ker-ε = hom-ε

    Ker-⁻¹ : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
    Ker-⁻¹ {x} kx = begin
      h (x ⁻¹)      ≈⟨ hom-⁻¹ x ⟩
      (h x) ⁻¹ᴴ     ≈⟨ ⁻¹ᴴ-cong kx ⟩
      (εᴴ ⁻¹ᴴ)      ≈⟨ ε⁻¹ᴴ≈εᴴ ⟩
      εᴴ            ∎

    Ker-isSubgroup : IsSubgroup 𝒢 Ker
    Ker-isSubgroup = mkIsSubgroup 𝒢 Ker-respects Ker-∙ Ker-ε Ker-⁻¹

    -- Normality: conjugating an element of the kernel by g sends it to
    -- h g ∙ εᴴ ∙ (h g)⁻¹, which collapses to εᴴ.
    Ker-normal : Conjugate.IsNormal 𝒢 Ker
    Ker-normal g {x} kx = begin
      h ((g ∙ x) ∙ g ⁻¹)                    ≈⟨ hom-∙ (g ∙ x) (g ⁻¹) ⟩
      (h (g ∙ x) ∙ᴴ h (g ⁻¹))               ≈⟨ ∙ᴴ-cong (hom-∙ g x) (hom-⁻¹ g) ⟩
      ((h g ∙ᴴ h x) ∙ᴴ ((h g) ⁻¹ᴴ))         ≈⟨ ∙ᴴ-cong (∙ᴴ-cong ≈ᴴrefl kx) ≈ᴴrefl ⟩
      ((h g ∙ᴴ εᴴ) ∙ᴴ ((h g) ⁻¹ᴴ))          ≈⟨ ∙ᴴ-cong (idʳᴴ (h g)) ≈ᴴrefl ⟩
      (h g ∙ᴴ ((h g) ⁻¹ᴴ))                  ≈⟨ invʳᴴ (h g) ⟩
      εᴴ                                    ∎

    -- The fibers of h are the cosets of the kernel.
    Ker→eq : ∀ x y → (x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y
    Ker→eq x y k = begin
      h x                                   ≈⟨ ≈ᴴsym (idʳᴴ (h x)) ⟩
      (h x ∙ᴴ εᴴ)                           ≈⟨ ∙ᴴ-cong ≈ᴴrefl (≈ᴴsym step) ⟩
      (h x ∙ᴴ (((h x) ⁻¹ᴴ) ∙ᴴ h y))         ≈⟨ ≈ᴴsym (assocᴴ (h x) ((h x) ⁻¹ᴴ) (h y)) ⟩
      ((h x ∙ᴴ ((h x) ⁻¹ᴴ)) ∙ᴴ h y)         ≈⟨ ∙ᴴ-cong (invʳᴴ (h x)) ≈ᴴrefl ⟩
      (εᴴ ∙ᴴ h y)                           ≈⟨ idˡᴴ (h y) ⟩
      h y                                   ∎
      where
      step : (((h x) ⁻¹ᴴ) ∙ᴴ h y) ≈ᴴ εᴴ
      step = begin
        (((h x) ⁻¹ᴴ) ∙ᴴ h y)   ≈⟨ ∙ᴴ-cong (≈ᴴsym (hom-⁻¹ x)) ≈ᴴrefl ⟩
        (h (x ⁻¹) ∙ᴴ h y)      ≈⟨ ≈ᴴsym (hom-∙ (x ⁻¹) y) ⟩
        h (x ⁻¹ ∙ y)           ≈⟨ k ⟩
        εᴴ                     ∎

    eq→Ker : ∀ x y → h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker
    eq→Ker x y hx≈hy = begin
      h (x ⁻¹ ∙ y)                 ≈⟨ hom-∙ (x ⁻¹) y ⟩
      (h (x ⁻¹) ∙ᴴ h y)            ≈⟨ ∙ᴴ-cong (hom-⁻¹ x) ≈ᴴrefl ⟩
      (((h x) ⁻¹ᴴ) ∙ᴴ h y)         ≈⟨ ∙ᴴ-cong (⁻¹ᴴ-cong hx≈hy) ≈ᴴrefl ⟩
      (((h y) ⁻¹ᴴ) ∙ᴴ h y)         ≈⟨ invˡᴴ (h y) ⟩
      εᴴ                           ∎

  kernel-normal-subgroup
    :  IsSubgroup 𝒢 Ker × Conjugate.IsNormal 𝒢 Ker
    ×  (∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker))
  kernel-normal-subgroup =
    Ker-isSubgroup , Ker-normal , λ x y → Ker→eq x y , eq→Ker x y
