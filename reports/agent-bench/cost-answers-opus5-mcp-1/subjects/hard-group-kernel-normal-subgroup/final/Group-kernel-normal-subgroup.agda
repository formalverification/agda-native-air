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

-- Additional imports (helpers only; nothing above was changed).
open import Classical.Operations                     using ( pair )
open import Classical.Signatures.Group               using ( ∙-Op )
open import Classical.Structures.Group.Subgroups     using ( mkIsSubgroup ; interp-tuple-∙ )
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

  -- Extra views of the two setoids / the two group structures.
  open Setoid 𝔻[ 𝑮 ] using () renaming ( _≈_ to _≈ᴳ_ )
  open Setoid 𝔻[ proj₁ 𝓗 ] using ()
    renaming ( refl to reflᴴ ; sym to symᴴ ; trans to transᴴ )
  open Group-Op 𝒢 using ()
    renaming ( ε to εᴳ ; idˡ-law to idˡ-lawᴳ ; invˡ-law to invˡ-lawᴳ )
  open Group-Op 𝓗 using ()
    renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ ; ∙-cong to ∙-congᴴ ; ⁻¹-cong to ⁻¹-congᴴ
             ; assoc-law to assoc-lawᴴ ; idˡ-law to idˡ-lawᴴ ; idʳ-law to idʳ-lawᴴ
             ; invˡ-law to invˡ-lawᴴ ; invʳ-law to invʳ-lawᴴ )
  open SetoidReasoning 𝔻[ proj₁ 𝓗 ]

  private
    hcong : ∀ {x y} → x ≈ᴳ y → h x ≈ᴴ h y
    hcong = _⟶_.cong hmap

    -- The curried multiplicativity of h, read off from the tuple-indexed
    -- compatibility of the homomorphism.
    h-∙ : ∀ x y → h (x ∙ y) ≈ᴴ (h x) ∙ᴴ (h y)
    h-∙ x y =
      transᴴ (Setoid.Homomorphisms.Basic.IsHom.compatible hhom {∙-Op} {pair x y})
             (interp-tuple-∙ 𝓗 (λ i → h (pair x y i)))

    -- h ε ≈ ε, by cancelling the idempotent h ε.
    hε : h εᴳ ≈ᴴ εᴴ
    hε = symᴴ (begin
      εᴴ                               ≈˘⟨ invˡ-lawᴴ u ⟩
      ((u ⁻¹ᴴ) ∙ᴴ u)                   ≈˘⟨ ∙-congᴴ reflᴴ uu ⟩
      ((u ⁻¹ᴴ) ∙ᴴ (u ∙ᴴ u))            ≈˘⟨ assoc-lawᴴ (u ⁻¹ᴴ) u u ⟩
      (((u ⁻¹ᴴ) ∙ᴴ u) ∙ᴴ u)            ≈⟨ ∙-congᴴ (invˡ-lawᴴ u) reflᴴ ⟩
      (εᴴ ∙ᴴ u)                        ≈⟨ idˡ-lawᴴ u ⟩
      u                                ∎)
      where
      u : 𝕌[ proj₁ 𝓗 ]
      u = h εᴳ

      uu : (u ∙ᴴ u) ≈ᴴ u
      uu = transᴴ (symᴴ (h-∙ εᴳ εᴳ)) (hcong (idˡ-lawᴳ εᴳ))

    -- h is compatible with inversion, by uniqueness of inverses.
    h-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ ((h x) ⁻¹ᴴ)
    h-⁻¹ x = begin
      h (x ⁻¹)                                  ≈˘⟨ idʳ-lawᴴ (h (x ⁻¹)) ⟩
      ((h (x ⁻¹)) ∙ᴴ εᴴ)                        ≈˘⟨ ∙-congᴴ reflᴴ (invʳ-lawᴴ (h x)) ⟩
      ((h (x ⁻¹)) ∙ᴴ ((h x) ∙ᴴ ((h x) ⁻¹ᴴ)))    ≈˘⟨ assoc-lawᴴ (h (x ⁻¹)) (h x) ((h x) ⁻¹ᴴ) ⟩
      (((h (x ⁻¹)) ∙ᴴ (h x)) ∙ᴴ ((h x) ⁻¹ᴴ))    ≈⟨ ∙-congᴴ inv-eq reflᴴ ⟩
      (εᴴ ∙ᴴ ((h x) ⁻¹ᴴ))                       ≈⟨ idˡ-lawᴴ ((h x) ⁻¹ᴴ) ⟩
      ((h x) ⁻¹ᴴ)                               ∎
      where
      inv-eq : ((h (x ⁻¹)) ∙ᴴ (h x)) ≈ᴴ εᴴ
      inv-eq = transᴴ (symᴴ (h-∙ (x ⁻¹) x)) (transᴴ (hcong (invˡ-lawᴳ x)) hε)

    ε⁻¹ᴴ≈εᴴ : (εᴴ ⁻¹ᴴ) ≈ᴴ εᴴ
    ε⁻¹ᴴ≈εᴴ = transᴴ (symᴴ (idʳ-lawᴴ (εᴴ ⁻¹ᴴ))) (invˡ-lawᴴ εᴴ)

    ker-respects : Ker Respects _≈ᴳ_
    ker-respects x≈y hx = transᴴ (symᴴ (hcong x≈y)) hx

    ker-∙ : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
    ker-∙ {x} {y} hx hy = transᴴ (h-∙ x y) (transᴴ (∙-congᴴ hx hy) (idˡ-lawᴴ εᴴ))

    ker-⁻¹ : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
    ker-⁻¹ {x} hx = transᴴ (h-⁻¹ x) (transᴴ (⁻¹-congᴴ hx) ε⁻¹ᴴ≈εᴴ)

    ker-subgroup : IsSubgroup 𝒢 Ker
    ker-subgroup = mkIsSubgroup 𝒢 ker-respects ker-∙ hε ker-⁻¹

    ker-normal : Conjugate.IsNormal 𝒢 Ker
    ker-normal g {x} hx = begin
      h ((g ∙ x) ∙ (g ⁻¹))                      ≈⟨ h-∙ (g ∙ x) (g ⁻¹) ⟩
      ((h (g ∙ x)) ∙ᴴ (h (g ⁻¹)))               ≈⟨ ∙-congᴴ (h-∙ g x) (h-⁻¹ g) ⟩
      (((h g) ∙ᴴ (h x)) ∙ᴴ ((h g) ⁻¹ᴴ))         ≈⟨ ∙-congᴴ (∙-congᴴ reflᴴ hx) reflᴴ ⟩
      (((h g) ∙ᴴ εᴴ) ∙ᴴ ((h g) ⁻¹ᴴ))            ≈⟨ ∙-congᴴ (idʳ-lawᴴ (h g)) reflᴴ ⟩
      ((h g) ∙ᴴ ((h g) ⁻¹ᴴ))                    ≈⟨ invʳ-lawᴴ (h g) ⟩
      εᴴ                                        ∎

    ker-coset : ∀ x y → (((x ⁻¹) ∙ y) ∈ Ker → h x ≈ᴴ h y)
                      × (h x ≈ᴴ h y → ((x ⁻¹) ∙ y) ∈ Ker)
    ker-coset x y = fwd , bwd
      where
      r : h ((x ⁻¹) ∙ y) ≈ᴴ (((h x) ⁻¹ᴴ) ∙ᴴ (h y))
      r = transᴴ (h-∙ (x ⁻¹) y) (∙-congᴴ (h-⁻¹ x) reflᴴ)

      fwd : ((x ⁻¹) ∙ y) ∈ Ker → h x ≈ᴴ h y
      fwd p = begin
        h x                                       ≈˘⟨ idʳ-lawᴴ (h x) ⟩
        ((h x) ∙ᴴ εᴴ)                             ≈˘⟨ ∙-congᴴ reflᴴ q ⟩
        ((h x) ∙ᴴ (((h x) ⁻¹ᴴ) ∙ᴴ (h y)))         ≈˘⟨ assoc-lawᴴ (h x) ((h x) ⁻¹ᴴ) (h y) ⟩
        (((h x) ∙ᴴ ((h x) ⁻¹ᴴ)) ∙ᴴ (h y))         ≈⟨ ∙-congᴴ (invʳ-lawᴴ (h x)) reflᴴ ⟩
        (εᴴ ∙ᴴ (h y))                             ≈⟨ idˡ-lawᴴ (h y) ⟩
        h y                                       ∎
        where
        q : (((h x) ⁻¹ᴴ) ∙ᴴ (h y)) ≈ᴴ εᴴ
        q = transᴴ (symᴴ r) p

      bwd : h x ≈ᴴ h y → ((x ⁻¹) ∙ y) ∈ Ker
      bwd p = transᴴ r (transᴴ (∙-congᴴ reflᴴ (symᴴ p)) (invˡ-lawᴴ (h x)))

  kernel-normal-subgroup
    :  IsSubgroup 𝒢 Ker × Conjugate.IsNormal 𝒢 Ker
    ×  (∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker))
  kernel-normal-subgroup = ker-subgroup , ker-normal , ker-coset
