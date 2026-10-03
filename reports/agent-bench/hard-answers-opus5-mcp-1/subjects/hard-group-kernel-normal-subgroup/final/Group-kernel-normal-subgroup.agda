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
open import Data.Fin.Patterns                        using ( 0F ; 1F )
open import Classical.Operations                     using ( pair )
open import Classical.Signatures.Group               using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Interpret           using ( interp-cong )
open import Classical.Structures.Group.Subgroups     using ( mkIsSubgroup )
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
    renaming ( refl to ≈ᴴrefl ; sym to ≈ᴴsym ; trans to ≈ᴴtrans )
  open Group-Op 𝒢 using () renaming ( ε to εᴳ )
  open Group-Op 𝓗 using ()
    renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ ; ∙-cong to ∙ᴴ-cong ; ⁻¹-cong to ⁻¹ᴴ-cong
             ; assoc-law to assocᴴ ; idˡ-law to idˡᴴ ; idʳ-law to idʳᴴ
             ; invˡ-law to invˡᴴ ; invʳ-law to invʳᴴ )
  open SetoidReasoning 𝔻[ proj₁ 𝓗 ]

  Ker : Pred G ρᵇ
  Ker x = h x ≈ᴴ εᴴ

  -- `h` respects the setoid equality of the domain.
  private
    hcong : ∀ {x y} → x ≈ᴳ y → h x ≈ᴴ h y
    hcong = _⟶_.cong hmap

    -- The curried homomorphism laws, obtained from the tuple-indexed
    -- compatibility witness by the interpretation-congruence bridge.
    hom-∙ : ∀ x y → h (x ∙ y) ≈ᴴ h x ∙ᴴ h y
    hom-∙ x y = ≈ᴴtrans  (IsHom.compatible hhom {∙-Op} {pair x y})
                         (interp-cong (proj₁ 𝓗) ∙-Op λ { 0F → ≈ᴴrefl ; 1F → ≈ᴴrefl })

    hom-ε : h εᴳ ≈ᴴ εᴴ
    hom-ε = ≈ᴴtrans  (IsHom.compatible hhom {ε-Op} {λ ()})
                     (interp-cong (proj₁ 𝓗) ε-Op λ ())

    hom-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ (h x) ⁻¹ᴴ
    hom-⁻¹ x = ≈ᴴtrans  (IsHom.compatible hhom {⁻¹-Op} {λ _ → x})
                        (interp-cong (proj₁ 𝓗) ⁻¹-Op λ { 0F → ≈ᴴrefl })

    -- The identity of 𝓗 is its own inverse.
    ε⁻¹ᴴ : εᴴ ⁻¹ᴴ ≈ᴴ εᴴ
    ε⁻¹ᴴ = ≈ᴴtrans (≈ᴴsym (idʳᴴ (εᴴ ⁻¹ᴴ))) (invˡᴴ εᴴ)

  -- The kernel is a subgroup.
  ker-isSubgroup : IsSubgroup 𝒢 Ker
  ker-isSubgroup = mkIsSubgroup 𝒢 resp ∙-c ε-c ⁻¹-c
    where
    resp : Ker Respects _≈ᴳ_
    resp x≈y x∈Ker = ≈ᴴtrans (≈ᴴsym (hcong x≈y)) x∈Ker

    ∙-c : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
    ∙-c {x} {y} x∈Ker y∈Ker = begin
      h (x ∙ y)      ≈⟨ hom-∙ x y ⟩
      h x ∙ᴴ h y     ≈⟨ ∙ᴴ-cong x∈Ker y∈Ker ⟩
      εᴴ ∙ᴴ εᴴ       ≈⟨ idˡᴴ εᴴ ⟩
      εᴴ             ∎

    ε-c : εᴳ ∈ Ker
    ε-c = hom-ε

    ⁻¹-c : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
    ⁻¹-c {x} x∈Ker = begin
      h (x ⁻¹)       ≈⟨ hom-⁻¹ x ⟩
      (h x) ⁻¹ᴴ      ≈⟨ ⁻¹ᴴ-cong x∈Ker ⟩
      εᴴ ⁻¹ᴴ         ≈⟨ ε⁻¹ᴴ ⟩
      εᴴ             ∎

  -- The kernel is normal.
  ker-isNormal : Conjugate.IsNormal 𝒢 Ker
  ker-isNormal g {x} x∈Ker = begin
    h (g ∙ x ∙ g ⁻¹)                ≈⟨ hom-∙ (g ∙ x) (g ⁻¹) ⟩
    h (g ∙ x) ∙ᴴ h (g ⁻¹)           ≈⟨ ∙ᴴ-cong (hom-∙ g x) (hom-⁻¹ g) ⟩
    h g ∙ᴴ h x ∙ᴴ (h g) ⁻¹ᴴ         ≈⟨ ∙ᴴ-cong (∙ᴴ-cong ≈ᴴrefl x∈Ker) ≈ᴴrefl ⟩
    h g ∙ᴴ εᴴ ∙ᴴ (h g) ⁻¹ᴴ          ≈⟨ ∙ᴴ-cong (idʳᴴ (h g)) ≈ᴴrefl ⟩
    h g ∙ᴴ (h g) ⁻¹ᴴ                ≈⟨ invʳᴴ (h g) ⟩
    εᴴ                              ∎

  -- The coset relation of the kernel is the kernel congruence.
  ker-coset : ∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker)
  ker-coset x y = fwd , bwd
    where
    expand : h (x ⁻¹ ∙ y) ≈ᴴ (h x) ⁻¹ᴴ ∙ᴴ h y
    expand = ≈ᴴtrans (hom-∙ (x ⁻¹) y) (∙ᴴ-cong (hom-⁻¹ x) ≈ᴴrefl)

    fwd : (x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y
    fwd k = ≈ᴴsym (begin
      h y                              ≈⟨ ≈ᴴsym (idˡᴴ (h y)) ⟩
      εᴴ ∙ᴴ h y                        ≈⟨ ∙ᴴ-cong (≈ᴴsym (invʳᴴ (h x))) ≈ᴴrefl ⟩
      h x ∙ᴴ (h x) ⁻¹ᴴ ∙ᴴ h y          ≈⟨ assocᴴ (h x) ((h x) ⁻¹ᴴ) (h y) ⟩
      h x ∙ᴴ ((h x) ⁻¹ᴴ ∙ᴴ h y)        ≈⟨ ∙ᴴ-cong ≈ᴴrefl (≈ᴴtrans (≈ᴴsym expand) k) ⟩
      h x ∙ᴴ εᴴ                        ≈⟨ idʳᴴ (h x) ⟩
      h x                              ∎)

    bwd : h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker
    bwd e = begin
      h (x ⁻¹ ∙ y)                     ≈⟨ expand ⟩
      (h x) ⁻¹ᴴ ∙ᴴ h y                 ≈⟨ ∙ᴴ-cong ≈ᴴrefl (≈ᴴsym e) ⟩
      (h x) ⁻¹ᴴ ∙ᴴ h x                 ≈⟨ invˡᴴ (h x) ⟩
      εᴴ                               ∎

  kernel-normal-subgroup
    :  IsSubgroup 𝒢 Ker × Conjugate.IsNormal 𝒢 Ker
    ×  (∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker))
  kernel-normal-subgroup = ker-isSubgroup , ker-isNormal , ker-coset
