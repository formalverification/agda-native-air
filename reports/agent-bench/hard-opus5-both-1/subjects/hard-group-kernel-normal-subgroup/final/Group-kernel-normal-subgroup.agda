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

-- Additional imports used by the proof below.
open import Data.Fin.Patterns                        using ( 0F ; 1F )
open import Classical.Operations                     using ( pair )
open import Classical.Signatures.Group               using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Interpret           using ( interp-cong )
open import Classical.Structures.Group.Subgroups     using ( mkIsSubgroup )
open import Setoid.Homomorphisms.Basic               using ( IsHom )

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
  kernel-normal-subgroup = isSub , isNrm , λ x y → fwd x y , bwd x y
    where
    𝑯 = proj₁ 𝓗

    open Setoid 𝔻[ 𝑮 ] using () renaming ( _≈_ to _≈ᴳ_ ; sym to ≈ᴳsym )
    open Setoid 𝔻[ 𝑯 ] using ()
      renaming ( refl to ≈ᴴrefl ; sym to ≈ᴴsym ; trans to ≈ᴴtrans )
    open Group-Op 𝒢 using ( ε )
    open Group-Op 𝓗 using ()
      renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ
               ; ∙-cong to ∙-congᴴ ; ⁻¹-cong to ⁻¹-congᴴ
               ; assoc-law to assoc-lawᴴ
               ; idˡ-law to idˡ-lawᴴ ; idʳ-law to idʳ-lawᴴ
               ; invˡ-law to invˡ-lawᴴ ; invʳ-law to invʳ-lawᴴ )

    -- h is a setoid function, hence ≈-preserving.
    hcong : ∀ {x y} → x ≈ᴳ y → h x ≈ᴴ h y
    hcong = _⟶_.cong hmap

    -- The three curried homomorphism laws, read off the tuple-indexed
    -- compatibility witness through the interpretation congruence.
    h-∙ : ∀ x y → h (x ∙ y) ≈ᴴ ((h x) ∙ᴴ (h y))
    h-∙ x y = ≈ᴴtrans  (IsHom.compatible hhom {∙-Op} {pair x y})
                       (interp-cong 𝑯 ∙-Op λ { 0F → ≈ᴴrefl ; 1F → ≈ᴴrefl })

    h-ε : h ε ≈ᴴ εᴴ
    h-ε = ≈ᴴtrans  (IsHom.compatible hhom {ε-Op} {λ ()})
                   (interp-cong 𝑯 ε-Op λ ())

    h-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ ((h x) ⁻¹ᴴ)
    h-⁻¹ x = ≈ᴴtrans  (IsHom.compatible hhom {⁻¹-Op} {λ _ → x})
                      (interp-cong 𝑯 ⁻¹-Op λ { 0F → ≈ᴴrefl })

    -- In any group the identity is its own inverse.
    ε⁻¹≈ε : ((εᴴ ⁻¹ᴴ)) ≈ᴴ εᴴ
    ε⁻¹≈ε = ≈ᴴtrans (≈ᴴsym (idʳ-lawᴴ (εᴴ ⁻¹ᴴ))) (invˡ-lawᴴ εᴴ)

    -- (1)  Ker is a subgroup.
    resp : Ker Respects _≈ᴳ_
    resp x≈y x∈Ker = ≈ᴴtrans (hcong (≈ᴳsym x≈y)) x∈Ker

    ∙-closed : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
    ∙-closed {x} {y} x∈ y∈ =
      ≈ᴴtrans (h-∙ x y) (≈ᴴtrans (∙-congᴴ x∈ y∈) (idˡ-lawᴴ εᴴ))

    ⁻¹-closed : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
    ⁻¹-closed {x} x∈ = ≈ᴴtrans (h-⁻¹ x) (≈ᴴtrans (⁻¹-congᴴ x∈) ε⁻¹≈ε)

    isSub : IsSubgroup 𝒢 Ker
    isSub = mkIsSubgroup 𝒢 resp ∙-closed h-ε ⁻¹-closed

    -- (2)  Ker is normal: conjugating a kernel element by g gives h g ∙ᴴ ε ∙ᴴ (h g)⁻¹.
    isNrm : Conjugate.IsNormal 𝒢 Ker
    isNrm g {x} x∈ =
      ≈ᴴtrans  (h-∙ (g ∙ x) (g ⁻¹))
      (≈ᴴtrans  (∙-congᴴ (h-∙ g x) (h-⁻¹ g))
      (≈ᴴtrans  (∙-congᴴ (∙-congᴴ ≈ᴴrefl x∈) ≈ᴴrefl)
      (≈ᴴtrans  (∙-congᴴ (idʳ-lawᴴ (h g)) ≈ᴴrefl)
                (invʳ-lawᴴ (h g)))))

    -- (3)  The fibers of h are the cosets of Ker.
    h-div : ∀ x y → h ((x ⁻¹) ∙ y) ≈ᴴ (((h x) ⁻¹ᴴ) ∙ᴴ (h y))
    h-div x y = ≈ᴴtrans (h-∙ (x ⁻¹) y) (∙-congᴴ (h-⁻¹ x) ≈ᴴrefl)

    fwd : ∀ x y → ((x ⁻¹) ∙ y) ∈ Ker → h x ≈ᴴ h y
    fwd x y x⁻¹y∈ =
      ≈ᴴtrans  (≈ᴴsym (idʳ-lawᴴ (h x)))
      (≈ᴴtrans  (∙-congᴴ ≈ᴴrefl (≈ᴴsym (≈ᴴtrans (≈ᴴsym (h-div x y)) x⁻¹y∈)))
      (≈ᴴtrans  (≈ᴴsym (assoc-lawᴴ (h x) ((h x) ⁻¹ᴴ) (h y)))
      (≈ᴴtrans  (∙-congᴴ (invʳ-lawᴴ (h x)) ≈ᴴrefl)
                (idˡ-lawᴴ (h y)))))

    bwd : ∀ x y → h x ≈ᴴ h y → ((x ⁻¹) ∙ y) ∈ Ker
    bwd x y hx≈hy =
      ≈ᴴtrans  (h-div x y)
      (≈ᴴtrans  (∙-congᴴ ≈ᴴrefl (≈ᴴsym hx≈hy))
                (invˡ-lawᴴ (h x)))
