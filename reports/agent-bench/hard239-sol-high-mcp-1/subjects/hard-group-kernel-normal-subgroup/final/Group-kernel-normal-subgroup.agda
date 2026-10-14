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
open import Setoid.Homomorphisms.Basic using ( IsHom )
open import Data.Fin.Base using ( Fin )
open import Classical.Operations using ( pair )
open import Classical.Signatures.Group using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Group.Subgroups
  using ( mkIsSubgroup ; interp-tuple-∙ ; interp-tuple-ε ; interp-tuple-⁻¹ )

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
  kernel-normal-subgroup = subgroup , normal , cosets
    where
    open Setoid 𝔻[ 𝑮 ] using ( _≈_ )
    open Setoid 𝔻[ proj₁ 𝓗 ] using ()
      renaming ( refl to reflᴴ ; sym to symᴴ ; trans to transᴴ )
    module H = Group-Op 𝓗
    open Group-Op 𝒢 using ( ε )

    h-∙ : ∀ x y → h (x ∙ y) ≈ᴴ (h x H.∙ h y)
    h-∙ x y = transᴴ
      (IsHom.compatible hhom {f = ∙-Op} {a = pair x y})
      (interp-tuple-∙ 𝓗 (λ i → h (pair x y i)))

    empty : Fin 0 → G
    empty = λ ()

    h-ε : h ε ≈ᴴ εᴴ
    h-ε = transᴴ (IsHom.compatible hhom {f = ε-Op} {a = empty})
      (interp-tuple-ε 𝓗 (λ i → h (empty i)))

    h-inv : ∀ x → h (x ⁻¹) ≈ᴴ (h x H.⁻¹)
    h-inv x = transᴴ
      (IsHom.compatible hhom {f = ⁻¹-Op} {a = λ _ → x})
      (interp-tuple-⁻¹ 𝓗 (λ _ → h x))

    resp : Ker Respects _≈_
    resp eq p = transᴴ (symᴴ (_⟶_.cong hmap eq)) p

    mul-closed : ∀ {x y} → Ker x → Ker y → Ker (x ∙ y)
    mul-closed {x} {y} p q = transᴴ (h-∙ x y)
      (transᴴ (H.∙-cong p q) (H.idˡ-law εᴴ))

    inv-closed : ∀ {x} → Ker x → Ker (x ⁻¹)
    inv-closed {x} p = transᴴ (h-inv x)
      (transᴴ (H.⁻¹-cong p)
        (transᴴ (symᴴ (H.idʳ-law (εᴴ H.⁻¹))) (H.invˡ-law εᴴ)))

    subgroup : IsSubgroup 𝒢 Ker
    subgroup = mkIsSubgroup 𝒢 resp mul-closed h-ε inv-closed

    normal : Conjugate.IsNormal 𝒢 Ker
    normal g {x} p = transᴴ (h-∙ (g ∙ x) (g ⁻¹))
      (transᴴ (H.∙-cong (h-∙ g x) (h-inv g))
        (transᴴ (H.∙-cong (H.∙-cong reflᴴ p) reflᴴ)
          (transᴴ (H.∙-cong (H.idʳ-law (h g)) reflᴴ)
            (H.invʳ-law (h g)))))

    difference : ∀ x y → h (x ⁻¹ ∙ y) ≈ᴴ ((h x H.⁻¹) H.∙ h y)
    difference x y = transᴴ (h-∙ (x ⁻¹) y)
      (H.∙-cong (h-inv x) reflᴴ)

    forward : ∀ x y → Ker (x ⁻¹ ∙ y) → h x ≈ᴴ h y
    forward x y p = transᴴ (symᴴ (H.idʳ-law (h x)))
      (transᴴ (H.∙-cong reflᴴ
        (symᴴ (transᴴ (symᴴ (difference x y)) p)))
        (transᴴ (symᴴ (H.assoc-law (h x) (h x H.⁻¹) (h y)))
          (transᴴ (H.∙-cong (H.invʳ-law (h x)) reflᴴ)
            (H.idˡ-law (h y)))))

    backward : ∀ x y → h x ≈ᴴ h y → Ker (x ⁻¹ ∙ y)
    backward x y eq = transᴴ (difference x y)
      (transᴴ (H.∙-cong reflᴴ (symᴴ eq)) (H.invˡ-law (h x)))

    cosets : ∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y)
      × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker)
    cosets x y = forward x y , backward x y
