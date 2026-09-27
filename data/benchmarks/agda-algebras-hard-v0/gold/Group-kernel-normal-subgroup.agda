-- Group-kernel-normal-subgroup.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/gold/Group-kernel-normal-subgroup.agda
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

  kernel-normal-subgroup
    :  IsSubgroup 𝒢 Ker × Conjugate.IsNormal 𝒢 Ker
    ×  (∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker))
  kernel-normal-subgroup =
    Ker-isSubgroup , Ker-normal , λ x y → coset⇒ker x y , ker⇒coset x y
    where
    open import Classical.Bundles.Group               using ( ⟨_⟩ᵍᵖ )
    open import Classical.Operations                  using ( pair )
    open import Classical.Signatures.Group            using ( ∙-Op ; ε-Op ; ⁻¹-Op )
    open import Classical.Structures.Group.Subgroups  using ( mkIsSubgroup
                                                            ; interp-tuple-∙ ; interp-tuple-ε )
    open import Setoid.Homomorphisms.Basic            using ( IsHom )
    open import Algebra.Properties.Group ⟨ 𝓗 ⟩ᵍᵖ      using ( ε⁻¹≈ε ; inverseˡ-unique
                                                            ; ⁻¹-injective )
    open import Relation.Binary.Reasoning.Setoid 𝔻[ proj₁ 𝓗 ]

    open Setoid 𝔻[ 𝑮 ]        using ( _≈_ ) renaming ( sym to ≈sym )
    open Setoid 𝔻[ proj₁ 𝓗 ]  using () renaming ( refl to ≈ᴴrefl ; trans to ≈ᴴtrans )
    open Group-Op 𝒢           using ( ε )
    open Group-Op 𝓗           using () renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ
                                                ; ∙-cong to ∙ᴴ-cong ; ⁻¹-cong to ⁻¹ᴴ-cong
                                                ; idˡ-law to idˡᴴ ; invˡ-law to invˡᴴ )
    open Conjugate 𝒢          using ( conj-syntax )
    open Conjugate 𝓗          using () renaming ( conj-cong to conjᴴ-cong ; conj-ε to conjᴴ-ε )
    open _⟶_ hmap             using () renaming ( cong to h-cong )
    open IsHom hhom           using ( compatible )

    -- The compatible field at ∙, ε and ⁻¹, restated for the curried operations.
    h-∙ : ∀ x y → h (x ∙ y) ≈ᴴ h x ∙ᴴ h y
    h-∙ x y = ≈ᴴtrans (compatible {∙-Op} {pair x y}) (interp-tuple-∙ 𝓗 _)

    h-ε : h ε ≈ᴴ εᴴ
    h-ε = ≈ᴴtrans (compatible {ε-Op} {λ ()}) (interp-tuple-ε 𝓗 _)

    h-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ h x ⁻¹ᴴ
    h-⁻¹ x = compatible {⁻¹-Op} {λ _ → x}

    -- Ker respects ≈ because h does.
    Ker-respects : Ker Respects _≈_
    Ker-respects x≈y hx≈ε = ≈ᴴtrans (h-cong (≈sym x≈y)) hx≈ε

    Ker-∙ : ∀ {x y} → x ∈ Ker → y ∈ Ker → x ∙ y ∈ Ker
    Ker-∙ {x} {y} hx≈ε hy≈ε = begin
      h (x ∙ y)   ≈⟨ h-∙ x y ⟩
      h x ∙ᴴ h y  ≈⟨ ∙ᴴ-cong hx≈ε hy≈ε ⟩
      εᴴ ∙ᴴ εᴴ    ≈⟨ idˡᴴ εᴴ ⟩
      εᴴ          ∎

    Ker-⁻¹ : ∀ {x} → x ∈ Ker → x ⁻¹ ∈ Ker
    Ker-⁻¹ {x} hx≈ε = begin
      h (x ⁻¹)  ≈⟨ h-⁻¹ x ⟩
      h x ⁻¹ᴴ   ≈⟨ ⁻¹ᴴ-cong hx≈ε ⟩
      εᴴ ⁻¹ᴴ    ≈⟨ ε⁻¹≈ε ⟩
      εᴴ        ∎

    Ker-isSubgroup : IsSubgroup 𝒢 Ker
    Ker-isSubgroup = mkIsSubgroup 𝒢 Ker-respects Ker-∙ h-ε Ker-⁻¹

    -- h (g ∙ x ∙ g ⁻¹) is the conjugate of h x by h g, and conjugation fixes εᴴ.
    Ker-normal : Conjugate.IsNormal 𝒢 Ker
    Ker-normal g {x} hx≈ε = begin
      h (x ^ g)               ≈⟨ h-∙ (g ∙ x) (g ⁻¹) ⟩
      h (g ∙ x) ∙ᴴ h (g ⁻¹)   ≈⟨ ∙ᴴ-cong (h-∙ g x) (h-⁻¹ g) ⟩
      h g ∙ᴴ h x ∙ᴴ h g ⁻¹ᴴ   ≈⟨ conjᴴ-cong (h g) hx≈ε ⟩
      h g ∙ᴴ εᴴ ∙ᴴ h g ⁻¹ᴴ    ≈⟨ conjᴴ-ε (h g) ⟩
      εᴴ                      ∎

    -- h carries the left quotient x ⁻¹ ∙ y to the left quotient of the images.
    h-quot : ∀ x y → h (x ⁻¹ ∙ y) ≈ᴴ h x ⁻¹ᴴ ∙ᴴ h y
    h-quot x y = ≈ᴴtrans (h-∙ (x ⁻¹) y) (∙ᴴ-cong (h-⁻¹ x) ≈ᴴrefl)

    -- (h x) ⁻¹ ∙ h y ≈ εᴴ makes (h x) ⁻¹ the inverse of h y, so h x ≈ h y.
    coset⇒ker : ∀ x y → x ⁻¹ ∙ y ∈ Ker → h x ≈ᴴ h y
    coset⇒ker x y x⁻¹y∈Ker = ⁻¹-injective (inverseˡ-unique (h x ⁻¹ᴴ) (h y) (begin
      h x ⁻¹ᴴ ∙ᴴ h y  ≈⟨ h-quot x y ⟨
      h (x ⁻¹ ∙ y)    ≈⟨ x⁻¹y∈Ker ⟩
      εᴴ              ∎))

    ker⇒coset : ∀ x y → h x ≈ᴴ h y → x ⁻¹ ∙ y ∈ Ker
    ker⇒coset x y hx≈hy = begin
      h (x ⁻¹ ∙ y)    ≈⟨ h-quot x y ⟩
      h x ⁻¹ᴴ ∙ᴴ h y  ≈⟨ ∙ᴴ-cong (⁻¹ᴴ-cong hx≈hy) ≈ᴴrefl ⟩
      h y ⁻¹ᴴ ∙ᴴ h y  ≈⟨ invˡᴴ (h y) ⟩
      εᴴ              ∎
