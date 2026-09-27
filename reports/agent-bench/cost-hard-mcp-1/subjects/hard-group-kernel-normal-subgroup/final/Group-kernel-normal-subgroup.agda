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

open import Data.Fin.Patterns                        using ( 0F ; 1F )
open import Classical.Operations                     using ( pair )
open import Classical.Signatures.Group               using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Interpret           using ( interp-cong )
open import Classical.Structures.Group.Subgroups     using ( mkIsSubgroup )
open import Setoid.Algebras.Basic                    using ( _^_ )
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

  private
    𝑯 = proj₁ 𝓗

  open Setoid 𝔻[ 𝑮 ] using ()
    renaming ( _≈_ to _≈ᴳ_ ; refl to reflᴳ ; sym to symᴳ ; trans to transᴳ )
  open Setoid 𝔻[ 𝑯 ] using ()
    renaming ( refl to reflᴴ ; sym to symᴴ ; trans to transᴴ )
  open Group-Op 𝒢 using ( ε )
  open Group-Op 𝓗 using ()
    renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to invᴴ ; ∙-cong to ∙-congᴴ ; ⁻¹-cong to ⁻¹-congᴴ
             ; assoc-law to assoc-lawᴴ ; idˡ-law to idˡ-lawᴴ ; idʳ-law to idʳ-lawᴴ
             ; invˡ-law to invˡ-lawᴴ ; invʳ-law to invʳ-lawᴴ )
  open SetoidReasoning 𝔻[ 𝑯 ]

  -- the underlying setoid map respects the setoid equality
  hcong : ∀ {x y} → x ≈ᴳ y → h x ≈ᴴ h y
  hcong = _⟶_.cong hmap

  -- the three homomorphism laws in curried form
  h-∙ : ∀ x y → h (x ∙ y) ≈ᴴ (h x ∙ᴴ h y)
  h-∙ x y = transᴴ  (IsHom.compatible hhom {∙-Op} {pair x y})
                    (interp-cong 𝑯 ∙-Op λ { 0F → reflᴴ ; 1F → reflᴴ })

  h-ε : h ε ≈ᴴ εᴴ
  h-ε = transᴴ (IsHom.compatible hhom {ε-Op}) (interp-cong 𝑯 ε-Op λ ())

  h-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ invᴴ (h x)
  h-⁻¹ x = transᴴ  (IsHom.compatible hhom {⁻¹-Op} {λ _ → x})
                   (interp-cong 𝑯 ⁻¹-Op λ { 0F → reflᴴ })

  -- ε is its own inverse in 𝓗
  ε⁻¹ᴴ : invᴴ εᴴ ≈ᴴ εᴴ
  ε⁻¹ᴴ = transᴴ (symᴴ (idʳ-lawᴴ (invᴴ εᴴ))) (invˡ-lawᴴ εᴴ)

  -- the kernel is a subgroup
  ker-respects : Ker Respects _≈ᴳ_
  ker-respects x≈y hx≈ε = transᴴ (hcong (symᴳ x≈y)) hx≈ε

  ker-∙ : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
  ker-∙ {x} {y} hx hy = begin
    h (x ∙ y)     ≈⟨ h-∙ x y ⟩
    (h x ∙ᴴ h y)  ≈⟨ ∙-congᴴ hx hy ⟩
    (εᴴ ∙ᴴ εᴴ)    ≈⟨ idˡ-lawᴴ εᴴ ⟩
    εᴴ            ∎

  ker-ε : ε ∈ Ker
  ker-ε = h-ε

  ker-⁻¹ : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
  ker-⁻¹ {x} hx = begin
    h (x ⁻¹)    ≈⟨ h-⁻¹ x ⟩
    invᴴ (h x)  ≈⟨ ⁻¹-congᴴ hx ⟩
    invᴴ εᴴ     ≈⟨ ε⁻¹ᴴ ⟩
    εᴴ          ∎

  -- the kernel is normal: conjugating by g sends ε to ε
  ker-normal : ∀ g {x} → x ∈ Ker → ((g ∙ x) ∙ g ⁻¹) ∈ Ker
  ker-normal g {x} hx = begin
    h ((g ∙ x) ∙ g ⁻¹)            ≈⟨ h-∙ (g ∙ x) (g ⁻¹) ⟩
    (h (g ∙ x) ∙ᴴ h (g ⁻¹))       ≈⟨ ∙-congᴴ (h-∙ g x) (h-⁻¹ g) ⟩
    ((h g ∙ᴴ h x) ∙ᴴ invᴴ (h g))  ≈⟨ ∙-congᴴ (∙-congᴴ reflᴴ hx) reflᴴ ⟩
    ((h g ∙ᴴ εᴴ) ∙ᴴ invᴴ (h g))   ≈⟨ ∙-congᴴ (idʳ-lawᴴ (h g)) reflᴴ ⟩
    (h g ∙ᴴ invᴴ (h g))           ≈⟨ invʳ-lawᴴ (h g) ⟩
    εᴴ                            ∎

  -- the fibers of h are the cosets of the kernel
  ker-coset-eq : ∀ x y → h (x ⁻¹ ∙ y) ≈ᴴ (invᴴ (h x) ∙ᴴ h y)
  ker-coset-eq x y = transᴴ (h-∙ (x ⁻¹) y) (∙-congᴴ (h-⁻¹ x) reflᴴ)

  ker-coset₁ : ∀ x y → (x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y
  ker-coset₁ x y k = symᴴ (begin
    h y                            ≈⟨ symᴴ (idˡ-lawᴴ (h y)) ⟩
    (εᴴ ∙ᴴ h y)                    ≈⟨ ∙-congᴴ (symᴴ (invʳ-lawᴴ (h x))) reflᴴ ⟩
    ((h x ∙ᴴ invᴴ (h x)) ∙ᴴ h y)   ≈⟨ assoc-lawᴴ (h x) (invᴴ (h x)) (h y) ⟩
    (h x ∙ᴴ (invᴴ (h x) ∙ᴴ h y))   ≈⟨ ∙-congᴴ reflᴴ (symᴴ (ker-coset-eq x y)) ⟩
    (h x ∙ᴴ h (x ⁻¹ ∙ y))          ≈⟨ ∙-congᴴ reflᴴ k ⟩
    (h x ∙ᴴ εᴴ)                    ≈⟨ idʳ-lawᴴ (h x) ⟩
    h x                            ∎)

  ker-coset₂ : ∀ x y → h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker
  ker-coset₂ x y e = begin
    h (x ⁻¹ ∙ y)         ≈⟨ ker-coset-eq x y ⟩
    (invᴴ (h x) ∙ᴴ h y)  ≈⟨ ∙-congᴴ (⁻¹-congᴴ e) reflᴴ ⟩
    (invᴴ (h y) ∙ᴴ h y)  ≈⟨ invˡ-lawᴴ (h y) ⟩
    εᴴ                   ∎

  kernel-normal-subgroup
    :  IsSubgroup 𝒢 Ker × Conjugate.IsNormal 𝒢 Ker
    ×  (∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker))
  kernel-normal-subgroup =
      mkIsSubgroup 𝒢 ker-respects ker-∙ ker-ε ker-⁻¹
    , ker-normal
    , λ x y → ker-coset₁ x y , ker-coset₂ x y
