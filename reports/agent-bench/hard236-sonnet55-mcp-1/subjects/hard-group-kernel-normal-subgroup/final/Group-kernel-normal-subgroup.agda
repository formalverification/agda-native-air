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
  kernel-normal-subgroup = sub , nrm , coset
    where
    open Setoid 𝔻[ proj₁ 𝓗 ] using ()
      renaming ( refl to refᴴ ; sym to symᴴ ; trans to trᴴ )
    open Setoid 𝔻[ 𝑮 ] using ()
      renaming ( _≈_ to _≈ᴳ_ )
    open Group-Op 𝒢 using ( ε ; assoc-law ; idˡ-law ; idʳ-law ; invˡ-law ; invʳ-law )
    open Group-Op 𝓗 using ()
      renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ ; ∙-cong to ∙ᴴ-cong ; ⁻¹-cong to ⁻¹ᴴ-cong
               ; assoc-law to assocᴴ ; idˡ-law to idˡᴴ ; idʳ-law to idʳᴴ
               ; invˡ-law to invˡᴴ ; invʳ-law to invʳᴴ )
    open import Classical.Structures.Group.Subgroups using ( mkIsSubgroup )
    open import Classical.Signatures.Group using ( ∙-Op ; ε-Op ; ⁻¹-Op )
    open import Classical.Operations using ( pair )
    open import Classical.Structures.Interpret using ( interp-cong )
    open import Data.Fin.Patterns using ( 0F ; 1F )

    cmp = Setoid.Homomorphisms.Basic.IsHom.compatible hhom

    h-∙ : ∀ x y → h (x ∙ y) ≈ᴴ h x ∙ᴴ h y
    h-∙ x y = trᴴ (cmp {∙-Op} {pair x y})
                  (interp-cong (proj₁ 𝓗) ∙-Op λ { 0F → refᴴ ; 1F → refᴴ })

    h-ε : h ε ≈ᴴ εᴴ
    h-ε = trᴴ (cmp {ε-Op} {λ ()})
              (interp-cong (proj₁ 𝓗) ε-Op λ ())

    h-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ (h x) ⁻¹ᴴ
    h-⁻¹ x = trᴴ (cmp {⁻¹-Op} {λ _ → x})
                 (interp-cong (proj₁ 𝓗) ⁻¹-Op λ { 0F → refᴴ })

    ε⁻¹ᴴ : (εᴴ ⁻¹ᴴ) ≈ᴴ εᴴ
    ε⁻¹ᴴ = trᴴ (symᴴ (idʳᴴ (εᴴ ⁻¹ᴴ))) (invˡᴴ εᴴ)

    sub : IsSubgroup 𝒢 Ker
    sub = mkIsSubgroup 𝒢 resp ∙-c ε-c ⁻¹-c
      where
      resp : Ker Respects _≈ᴳ_
      resp x≈y p = trᴴ (symᴴ (_⟶_.cong hmap x≈y)) p
      ∙-c : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
      ∙-c px py = trᴴ (h-∙ _ _) (trᴴ (∙ᴴ-cong px py) (idˡᴴ εᴴ))
      ε-c : ε ∈ Ker
      ε-c = h-ε
      ⁻¹-c : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
      ⁻¹-c px = trᴴ (h-⁻¹ _) (trᴴ (⁻¹ᴴ-cong px) ε⁻¹ᴴ)

    nrm : Conjugate.IsNormal 𝒢 Ker
    nrm g {x} px =
      trᴴ (h-∙ (g ∙ x) (g ⁻¹))
      (trᴴ (∙ᴴ-cong (h-∙ g x) (h-⁻¹ g))
      (trᴴ (∙ᴴ-cong (∙ᴴ-cong refᴴ px) refᴴ)
      (trᴴ (∙ᴴ-cong (idʳᴴ (h g)) refᴴ)
           (invʳᴴ (h g)))))

    coset : ∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker)
    coset x y = fwd , bwd
      where
      lhs : h (x ⁻¹ ∙ y) ≈ᴴ (h x) ⁻¹ᴴ ∙ᴴ h y
      lhs = trᴴ (h-∙ (x ⁻¹) y) (∙ᴴ-cong (h-⁻¹ x) refᴴ)
      fwd : (x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y
      fwd p =
        trᴴ (symᴴ (idʳᴴ (h x)))
        (trᴴ (∙ᴴ-cong refᴴ (symᴴ (trᴴ (symᴴ lhs) p)))
        (trᴴ (symᴴ (assocᴴ (h x) ((h x) ⁻¹ᴴ) (h y)))
        (trᴴ (∙ᴴ-cong (invʳᴴ (h x)) refᴴ)
             (idˡᴴ (h y)))))
      bwd : h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker
      bwd e = trᴴ lhs (trᴴ (∙ᴴ-cong refᴴ (symᴴ e)) (invˡᴴ (h x)))
