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

open import Data.Fin.Patterns                        using ( 0F ; 1F )
open import Classical.Operations                     using ( pair )
open import Classical.Signatures.Group               using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Group.Subgroups     using ( mkIsSubgroup ; interp-tuple-∙
                                                           ; interp-tuple-ε ; interp-tuple-⁻¹ )
open import Setoid.Homomorphisms.Basic               using ( module IsHom )
open import Setoid.Algebras.Basic                    using ( _^_ )

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
    ker-sub , ker-normal , λ x y → ker→eq x y , eq→ker x y
    where
    open Setoid 𝔻[ 𝑮 ] using () renaming ( _≈_ to _≈ᴳ_ )
    open Setoid 𝔻[ proj₁ 𝓗 ] using () renaming ( sym to symᴴ ; trans to transᴴ ; refl to reflᴴ )
    open Group-Op 𝒢 using ( ε )
    open Group-Op 𝓗 using ()
      renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ ; ∙-cong to ∙-congᴴ ; ⁻¹-cong to ⁻¹-congᴴ
               ; assoc-law to assoc-lawᴴ ; idˡ-law to idˡ-lawᴴ ; idʳ-law to idʳ-lawᴴ
               ; invˡ-law to invˡ-lawᴴ ; invʳ-law to invʳ-lawᴴ )

    hcong : ∀ {x y} → x ≈ᴳ y → h x ≈ᴴ h y
    hcong = _⟶_.cong hmap

    hcompat : ∀ {f a} → h ((f ^ 𝑮) a) ≈ᴴ (f ^ proj₁ 𝓗) (λ i → h (a i))
    hcompat = IsHom.compatible hhom

    hom-∙ : ∀ x y → h (x ∙ y) ≈ᴴ h x ∙ᴴ h y
    hom-∙ x y = transᴴ (hcompat {∙-Op} {pair x y}) (interp-tuple-∙ 𝓗 _)

    hom-ε : h ε ≈ᴴ εᴴ
    hom-ε = transᴴ (hcompat {ε-Op} {λ ()}) (interp-tuple-ε 𝓗 _)

    hom-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ (h x) ⁻¹ᴴ
    hom-⁻¹ x = transᴴ (hcompat {⁻¹-Op} {λ _ → x}) (interp-tuple-⁻¹ 𝓗 _)

    ε⁻¹ᴴ≈εᴴ : εᴴ ⁻¹ᴴ ≈ᴴ εᴴ
    ε⁻¹ᴴ≈εᴴ = transᴴ (symᴴ (idʳ-lawᴴ (εᴴ ⁻¹ᴴ))) (invˡ-lawᴴ εᴴ)

    ker-resp : Ker Respects _≈ᴳ_
    ker-resp x≈y hx≈ε = transᴴ (symᴴ (hcong x≈y)) hx≈ε

    ker-∙ : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
    ker-∙ {x} {y} hx hy =
      transᴴ (hom-∙ x y) (transᴴ (∙-congᴴ hx hy) (idˡ-lawᴴ εᴴ))

    ker-⁻¹ : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
    ker-⁻¹ {x} hx = transᴴ (hom-⁻¹ x) (transᴴ (⁻¹-congᴴ hx) ε⁻¹ᴴ≈εᴴ)

    ker-sub : IsSubgroup 𝒢 Ker
    ker-sub = mkIsSubgroup 𝒢 ker-resp ker-∙ hom-ε ker-⁻¹

    ker-normal : Conjugate.IsNormal 𝒢 Ker
    ker-normal g {x} hx =
      transᴴ (hom-∙ (g ∙ x) (g ⁻¹))
        (transᴴ (∙-congᴴ (hom-∙ g x) (hom-⁻¹ g))
          (transᴴ (∙-congᴴ (∙-congᴴ reflᴴ hx) reflᴴ)
            (transᴴ (∙-congᴴ (idʳ-lawᴴ (h g)) reflᴴ) (invʳ-lawᴴ (h g)))))

    ker→eq : ∀ x y → (x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y
    ker→eq x y hk = symᴴ
      (transᴴ (symᴴ (idˡ-lawᴴ (h y)))
        (transᴴ (∙-congᴴ (symᴴ (invʳ-lawᴴ (h x))) reflᴴ)
          (transᴴ (assoc-lawᴴ (h x) ((h x) ⁻¹ᴴ) (h y))
            (transᴴ (∙-congᴴ reflᴴ step) (idʳ-lawᴴ (h x))))))
      where
      step : (h x) ⁻¹ᴴ ∙ᴴ h y ≈ᴴ εᴴ
      step = transᴴ (symᴴ (∙-congᴴ (hom-⁻¹ x) reflᴴ))
                    (transᴴ (symᴴ (hom-∙ (x ⁻¹) y)) hk)

    eq→ker : ∀ x y → h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker
    eq→ker x y hxy = transᴴ (hom-∙ (x ⁻¹) y)
      (transᴴ (∙-congᴴ (hom-⁻¹ x) (symᴴ hxy)) (invˡ-lawᴴ (h x)))
