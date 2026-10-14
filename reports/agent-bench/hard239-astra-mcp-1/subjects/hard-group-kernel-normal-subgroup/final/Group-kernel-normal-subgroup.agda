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
open import Classical.Structures.Group.Subgroups using ( mkIsSubgroup )
open import Classical.Structures.Group.Subgroups using ( interp-tuple-∙ ; interp-tuple-ε ; interp-tuple-⁻¹ )
open import Classical.Signatures.Group using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Operations using ( pair )
open import Classical.Bundles.Group using ( ⟨_⟩ᵍᵖ )
import Algebra.Properties.Group as GP
open import Data.Fin.Base using ( Fin )

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
    module H = Group-Op 𝓗
    open Setoid 𝔻[ proj₁ 𝓗 ] using ( refl ; sym ; trans )
    open GP ⟨ 𝓗 ⟩ᵍᵖ using ( ε⁻¹≈ε )

    mul : ∀ x y → h (x ∙ y) ≈ᴴ (h x H.∙ h y)
    mul x y = trans (IsHom.compatible hhom {f = ∙-Op} {a = pair x y})
      (interp-tuple-∙ 𝓗 (λ i → h (pair x y i)))

    inv : ∀ x → h (x ⁻¹) ≈ᴴ ((h x) H.⁻¹)
    inv x = trans (IsHom.compatible hhom {f = ⁻¹-Op} {a = λ _ → x})
      (interp-tuple-⁻¹ 𝓗 (λ _ → h x))

    unit : h (Group-Op.ε 𝒢) ≈ᴴ εᴴ
    unit = trans (_⟶_.cong hmap (Setoid.sym 𝔻[ 𝑮 ] (interp-tuple-ε 𝒢 empty)))
      (trans (IsHom.compatible hhom {f = ε-Op} {a = empty})
        (interp-tuple-ε 𝓗 (λ i → h (empty i))))
      where
      empty : Fin 0 → G
      empty ()

    subgroup : IsSubgroup 𝒢 Ker
    subgroup = mkIsSubgroup 𝒢
      (λ eq k → trans (sym (_⟶_.cong hmap eq)) k)
      (λ {x} {y} k l → trans (mul x y)
        (trans (H.∙-cong k l) (H.idˡ-law εᴴ)))
      unit
      (λ {x} k → trans (inv x) (trans (H.⁻¹-cong k) ε⁻¹≈ε))

    normal : Conjugate.IsNormal 𝒢 Ker
    normal g {x} k = trans (mul (g ∙ x) (g ⁻¹))
      (trans (H.∙-cong (trans (mul g x) (H.∙-cong refl k)) (inv g))
        (trans (H.∙-cong (H.idʳ-law (h g)) refl) (H.invʳ-law (h g))))

    cosets : ∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) ×
                         (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker)
    cosets x y = forward , backward
      where
      bridge : h (x ⁻¹ ∙ y) ≈ᴴ ((h x H.⁻¹) H.∙ h y)
      bridge = trans (mul (x ⁻¹) y) (H.∙-cong (inv x) refl)

      forward : Ker (x ⁻¹ ∙ y) → h x ≈ᴴ h y
      forward k = trans (sym (H.idʳ-law (h x)))
        (trans (H.∙-cong refl (sym (trans (sym bridge) k)))
          (trans (sym (H.assoc-law (h x) (h x H.⁻¹) (h y)))
            (trans (H.∙-cong (H.invʳ-law (h x)) refl) (H.idˡ-law (h y)))))

      backward : h x ≈ᴴ h y → Ker (x ⁻¹ ∙ y)
      backward eq = trans bridge
        (trans (H.∙-cong refl (sym eq)) (H.invˡ-law (h x)))
