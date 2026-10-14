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
open import Classical.Signatures.Group using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Group.Subgroups using ( interp-tuple-∙ ; interp-tuple-ε ; interp-tuple-⁻¹ )
open import Data.Fin.Patterns using ( 0F ; 1F )
open import Setoid.Algebras.Basic using ( _^_ )
open import Classical.Operations using ( pair )
import Relation.Binary.Reasoning.Setoid as Reasoning

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
    open Setoid 𝔻[ proj₁ 𝓗 ] using ()
      renaming ( refl to r ; sym to s ; trans to t )
    open Reasoning 𝔻[ proj₁ 𝓗 ]

    mul : ∀ x y → h (x ∙ y) ≈ᴴ H._∙_ (h x) (h y)
    mul x y = t (IsHom.compatible hhom {f = ∙-Op})
      (interp-tuple-∙ 𝓗 (λ i → h (pair x y i)))

    inv : ∀ x → h (x ⁻¹) ≈ᴴ H._⁻¹ (h x)
    inv x = t (IsHom.compatible hhom {f = ⁻¹-Op})
      (interp-tuple-⁻¹ 𝓗 (λ _ → h x))

    inv-unit : H._⁻¹ εᴴ ≈ᴴ εᴴ
    inv-unit = t (s (H.idʳ-law (H._⁻¹ εᴴ))) (H.invˡ-law εᴴ)

    subgroup : IsSubgroup 𝒢 Ker
    subgroup = record
      { respects = λ eq k → t (s (_⟶_.cong hmap eq)) k
      ; isSubuniverse = closed
      }
      where
      closed : ∀ f a → (∀ i → Ker (a i)) → Ker ((f ^ 𝑮) a)
      closed ∙-Op a k = t (IsHom.compatible hhom {f = ∙-Op})
        (t (interp-tuple-∙ 𝓗 (λ i → h (a i)))
          (t (H.∙-cong (k 0F) (k 1F)) (H.idˡ-law εᴴ)))
      closed ε-Op a k = t (IsHom.compatible hhom {f = ε-Op})
        (interp-tuple-ε 𝓗 (λ i → h (a i)))
      closed ⁻¹-Op a k = t (IsHom.compatible hhom {f = ⁻¹-Op})
        (t (interp-tuple-⁻¹ 𝓗 (λ i → h (a i)))
          (t (H.⁻¹-cong (k 0F)) inv-unit))

    normal : Conjugate.IsNormal 𝒢 Ker
    normal g {x} k = begin
      h ((g ∙ x) ∙ g ⁻¹) ≈⟨ mul (g ∙ x) (g ⁻¹) ⟩
      H._∙_ (h (g ∙ x)) (h (g ⁻¹)) ≈⟨ H.∙-cong (mul g x) (inv g) ⟩
      H._∙_ (H._∙_ (h g) (h x)) (H._⁻¹ (h g)) ≈⟨ H.∙-cong (t (H.∙-cong r k) (H.idʳ-law (h g))) r ⟩
      H._∙_ (h g) (H._⁻¹ (h g)) ≈⟨ H.invʳ-law (h g) ⟩
      εᴴ ∎

    cosets : ∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker)
    cosets x y = forward , backward
      where
      bridge : h (x ⁻¹ ∙ y) ≈ᴴ H._∙_ (H._⁻¹ (h x)) (h y)
      bridge = t (mul (x ⁻¹) y) (H.∙-cong (inv x) r)

      forward : Ker (x ⁻¹ ∙ y) → h x ≈ᴴ h y
      forward k = begin
        h x ≈˘⟨ H.idʳ-law (h x) ⟩
        H._∙_ (h x) εᴴ ≈˘⟨ H.∙-cong r (t (s bridge) k) ⟩
        H._∙_ (h x) (H._∙_ (H._⁻¹ (h x)) (h y)) ≈˘⟨ H.assoc-law (h x) (H._⁻¹ (h x)) (h y) ⟩
        H._∙_ (H._∙_ (h x) (H._⁻¹ (h x))) (h y) ≈⟨ H.∙-cong (H.invʳ-law (h x)) r ⟩
        H._∙_ εᴴ (h y) ≈⟨ H.idˡ-law (h y) ⟩
        h y ∎

      backward : h x ≈ᴴ h y → Ker (x ⁻¹ ∙ y)
      backward eq = t bridge (t (H.∙-cong r (s eq)) (H.invˡ-law (h x)))
