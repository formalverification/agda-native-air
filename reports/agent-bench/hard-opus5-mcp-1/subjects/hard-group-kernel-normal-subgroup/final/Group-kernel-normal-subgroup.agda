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

-- Additional imports needed for the proof below.
open import Data.Fin.Patterns                        using ( 0F ; 1F )
open import Classical.Operations                     using ( pair )
open import Classical.Signatures.Group               using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Interpret           using ( interp-cong )
open import Classical.Structures.Group.Subgroups     using ( mkIsSubgroup )
open import Classical.Bundles.Group                  using ( ⟨_⟩ᵍᵖ )
open import Setoid.Homomorphisms.Basic               using ( IsHom )

import Algebra.Properties.Group as GroupProperties
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

  open Setoid 𝔻[ 𝑮 ] using () renaming ( _≈_ to _≈ᴳ_ )
  open Setoid 𝔻[ 𝑯 ] using ()
    renaming ( refl to ≈ᴴrefl ; sym to ≈ᴴsym ; trans to ≈ᴴtrans )
  open Group-Op 𝒢 using ( ε )
  open Group-Op 𝓗 using ()
    renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ ; ∙-cong to ∙ᴴ-cong ; ⁻¹-cong to ⁻¹ᴴ-cong
             ; idˡ-law to idˡᴴ-law ; idʳ-law to idʳᴴ-law
             ; invˡ-law to invˡᴴ-law ; invʳ-law to invʳᴴ-law )
  open GroupProperties ⟨ 𝓗 ⟩ᵍᵖ using ( ε⁻¹≈ε ; ⁻¹-involutive ; inverseʳ-unique )
  open SetoidReasoning 𝔻[ 𝑯 ]

  private
    hcomp = IsHom.compatible hhom

  -- The three curried homomorphism laws.
  h-∙ : ∀ x y → h (x ∙ y) ≈ᴴ (h x ∙ᴴ h y)
  h-∙ x y = ≈ᴴtrans hcomp (interp-cong 𝑯 ∙-Op λ { 0F → ≈ᴴrefl ; 1F → ≈ᴴrefl })

  h-ε : h ε ≈ᴴ εᴴ
  h-ε = ≈ᴴtrans hcomp (interp-cong 𝑯 ε-Op λ ())

  h-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ ((h x) ⁻¹ᴴ)
  h-⁻¹ x = ≈ᴴtrans hcomp (interp-cong 𝑯 ⁻¹-Op λ { 0F → ≈ᴴrefl })

  -- The kernel is a subgroup.
  Ker-respects : Ker Respects _≈ᴳ_
  Ker-respects x≈y hx≈ε = ≈ᴴtrans (≈ᴴsym (_⟶_.cong hmap x≈y)) hx≈ε

  Ker-∙-closed : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
  Ker-∙-closed {x} {y} hx hy = begin
    h (x ∙ y)       ≈⟨ h-∙ x y ⟩
    (h x ∙ᴴ h y)    ≈⟨ ∙ᴴ-cong hx hy ⟩
    (εᴴ ∙ᴴ εᴴ)      ≈⟨ idˡᴴ-law εᴴ ⟩
    εᴴ              ∎

  Ker-ε-closed : ε ∈ Ker
  Ker-ε-closed = h-ε

  Ker-⁻¹-closed : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
  Ker-⁻¹-closed {x} hx = begin
    h (x ⁻¹)        ≈⟨ h-⁻¹ x ⟩
    ((h x) ⁻¹ᴴ)     ≈⟨ ⁻¹ᴴ-cong hx ⟩
    (εᴴ ⁻¹ᴴ)        ≈⟨ ε⁻¹≈ε ⟩
    εᴴ              ∎

  Ker-isSubgroup : IsSubgroup 𝒢 Ker
  Ker-isSubgroup = mkIsSubgroup 𝒢 Ker-respects Ker-∙-closed Ker-ε-closed Ker-⁻¹-closed

  -- The kernel is normal.
  Ker-isNormal : Conjugate.IsNormal 𝒢 Ker
  Ker-isNormal g {x} hx = begin
    h (g ∙ x ∙ g ⁻¹)                    ≈⟨ h-∙ (g ∙ x) (g ⁻¹) ⟩
    (h (g ∙ x) ∙ᴴ h (g ⁻¹))             ≈⟨ ∙ᴴ-cong (h-∙ g x) (h-⁻¹ g) ⟩
    ((h g ∙ᴴ h x) ∙ᴴ ((h g) ⁻¹ᴴ))       ≈⟨ ∙ᴴ-cong (∙ᴴ-cong ≈ᴴrefl hx) ≈ᴴrefl ⟩
    ((h g ∙ᴴ εᴴ) ∙ᴴ ((h g) ⁻¹ᴴ))        ≈⟨ ∙ᴴ-cong (idʳᴴ-law (h g)) ≈ᴴrefl ⟩
    (h g ∙ᴴ ((h g) ⁻¹ᴴ))                ≈⟨ invʳᴴ-law (h g) ⟩
    εᴴ                                  ∎

  -- The fibers are the cosets.
  Ker-coset : ∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker)
  Ker-coset x y = fwd , bwd
    where
    key : h (x ⁻¹ ∙ y) ≈ᴴ (((h x) ⁻¹ᴴ) ∙ᴴ h y)
    key = ≈ᴴtrans (h-∙ (x ⁻¹) y) (∙ᴴ-cong (h-⁻¹ x) ≈ᴴrefl)

    fwd : (x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y
    fwd p = ≈ᴴsym (≈ᴴtrans (inverseʳ-unique ((h x) ⁻¹ᴴ) (h y) (≈ᴴtrans (≈ᴴsym key) p))
                           (⁻¹-involutive (h x)))

    bwd : h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker
    bwd p = ≈ᴴtrans key (≈ᴴtrans (∙ᴴ-cong ≈ᴴrefl (≈ᴴsym p)) (invˡᴴ-law (h x)))

  kernel-normal-subgroup
    :  IsSubgroup 𝒢 Ker × Conjugate.IsNormal 𝒢 Ker
    ×  (∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker))
  kernel-normal-subgroup = Ker-isSubgroup , Ker-isNormal , Ker-coset
