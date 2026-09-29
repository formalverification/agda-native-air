-- Group-kernel-normal-subgroup.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/obligations/Group-kernel-normal-subgroup.agda
--
-- Benchmark obligation: hard-group-kernel-normal-subgroup
-- Difficulty: non-obvious
-- Import stratum: novel
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

-- Additional imports used by the proof below.
open import Classical.Operations                     using ( pair )
open import Classical.Signatures.Group               using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Group.Subgroups
  using ( mkIsSubgroup ; interp-tuple-∙ ; interp-tuple-ε ; interp-tuple-⁻¹ )
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

  open Setoid 𝔻[ 𝑮 ] using () renaming ( _≈_ to _≈ᴳ_ )
  open Setoid 𝔻[ proj₁ 𝓗 ] using ()
    renaming ( refl to reflᴴ ; sym to symᴴ ; trans to transᴴ )
  open Group-Op 𝒢 using ( ε )
  open Group-Op 𝓗 using ()
    renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ ; ∙-cong to ∙-congᴴ ; ⁻¹-cong to ⁻¹-congᴴ
             ; assoc-law to assoc-lawᴴ ; idˡ-law to idˡ-lawᴴ ; idʳ-law to idʳ-lawᴴ
             ; invˡ-law to invˡ-lawᴴ ; invʳ-law to invʳ-lawᴴ )
  open SetoidReasoning 𝔻[ proj₁ 𝓗 ]

  Ker : Pred G ρᵇ
  Ker x = h x ≈ᴴ εᴴ

  private
    -- The underlying setoid map of the homomorphism respects ≈.
    hcong : ∀ {x y} → x ≈ᴳ y → h x ≈ᴴ h y
    hcong = _⟶_.cong hmap

    -- The three curried homomorphism laws, obtained from the tuple-indexed
    -- compatibility condition via the interpretation bridges.
    h∙ : ∀ x y → h (x ∙ y) ≈ᴴ (h x ∙ᴴ h y)
    h∙ x y = transᴴ (IsHom.compatible hhom {∙-Op} {pair x y})
                    (interp-tuple-∙ 𝓗 (λ i → h (pair x y i)))

    hε : h ε ≈ᴴ εᴴ
    hε = transᴴ (IsHom.compatible hhom) (interp-tuple-ε 𝓗 _)

    h⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ ((h x) ⁻¹ᴴ)
    h⁻¹ x = transᴴ (IsHom.compatible hhom {⁻¹-Op} {λ _ → x})
                   (interp-tuple-⁻¹ 𝓗 (λ i → h x))

    -- The identity of 𝓗 is its own inverse.
    ε⁻¹ᴴ≈εᴴ : (εᴴ ⁻¹ᴴ) ≈ᴴ εᴴ
    ε⁻¹ᴴ≈εᴴ = transᴴ (symᴴ (idʳ-lawᴴ (εᴴ ⁻¹ᴴ))) (invˡ-lawᴴ εᴴ)

  kernel-normal-subgroup
    :  IsSubgroup 𝒢 Ker × Conjugate.IsNormal 𝒢 Ker
    ×  (∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker))
  kernel-normal-subgroup = subgrp , normal , λ x y → fwd x y , bwd x y
    where
    resp : Ker Respects _≈ᴳ_
    resp x≈y hx = transᴴ (symᴴ (hcong x≈y)) hx

    ∙-c : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
    ∙-c {x} {y} hx hy = begin
      h (x ∙ y)     ≈⟨ h∙ x y ⟩
      (h x ∙ᴴ h y)  ≈⟨ ∙-congᴴ hx hy ⟩
      (εᴴ ∙ᴴ εᴴ)    ≈⟨ idˡ-lawᴴ εᴴ ⟩
      εᴴ            ∎

    ⁻¹-c : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
    ⁻¹-c {x} hx = begin
      h (x ⁻¹)     ≈⟨ h⁻¹ x ⟩
      ((h x) ⁻¹ᴴ)  ≈⟨ ⁻¹-congᴴ hx ⟩
      (εᴴ ⁻¹ᴴ)     ≈⟨ ε⁻¹ᴴ≈εᴴ ⟩
      εᴴ           ∎

    subgrp : IsSubgroup 𝒢 Ker
    subgrp = mkIsSubgroup 𝒢 resp ∙-c hε ⁻¹-c

    normal : Conjugate.IsNormal 𝒢 Ker
    normal g {x} hx = begin
      h (g ∙ x ∙ g ⁻¹)                ≈⟨ h∙ (g ∙ x) (g ⁻¹) ⟩
      (h (g ∙ x) ∙ᴴ h (g ⁻¹))         ≈⟨ ∙-congᴴ (h∙ g x) (h⁻¹ g) ⟩
      ((h g ∙ᴴ h x) ∙ᴴ ((h g) ⁻¹ᴴ))   ≈⟨ ∙-congᴴ (∙-congᴴ reflᴴ hx) reflᴴ ⟩
      ((h g ∙ᴴ εᴴ) ∙ᴴ ((h g) ⁻¹ᴴ))    ≈⟨ ∙-congᴴ (idʳ-lawᴴ (h g)) reflᴴ ⟩
      (h g ∙ᴴ ((h g) ⁻¹ᴴ))            ≈⟨ invʳ-lawᴴ (h g) ⟩
      εᴴ                              ∎

    -- h (x ⁻¹ ∙ y) is the "difference" (h x) ⁻¹ ∙ h y.
    diff : ∀ x y → h (x ⁻¹ ∙ y) ≈ᴴ (((h x) ⁻¹ᴴ) ∙ᴴ h y)
    diff x y = transᴴ (h∙ (x ⁻¹) y) (∙-congᴴ (h⁻¹ x) reflᴴ)

    fwd : ∀ x y → (x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y
    fwd x y k = begin
      h x                                  ≈˘⟨ idʳ-lawᴴ (h x) ⟩
      (h x ∙ᴴ εᴴ)                          ≈˘⟨ ∙-congᴴ reflᴴ k' ⟩
      (h x ∙ᴴ (((h x) ⁻¹ᴴ) ∙ᴴ h y))        ≈˘⟨ assoc-lawᴴ (h x) ((h x) ⁻¹ᴴ) (h y) ⟩
      ((h x ∙ᴴ ((h x) ⁻¹ᴴ)) ∙ᴴ h y)        ≈⟨ ∙-congᴴ (invʳ-lawᴴ (h x)) reflᴴ ⟩
      (εᴴ ∙ᴴ h y)                          ≈⟨ idˡ-lawᴴ (h y) ⟩
      h y                                  ∎
      where
      k' : (((h x) ⁻¹ᴴ) ∙ᴴ h y) ≈ᴴ εᴴ
      k' = transᴴ (symᴴ (diff x y)) k

    bwd : ∀ x y → h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker
    bwd x y e = begin
      h (x ⁻¹ ∙ y)          ≈⟨ diff x y ⟩
      (((h x) ⁻¹ᴴ) ∙ᴴ h y)  ≈˘⟨ ∙-congᴴ reflᴴ e ⟩
      (((h x) ⁻¹ᴴ) ∙ᴴ h x)  ≈⟨ invˡ-lawᴴ (h x) ⟩
      εᴴ                    ∎
