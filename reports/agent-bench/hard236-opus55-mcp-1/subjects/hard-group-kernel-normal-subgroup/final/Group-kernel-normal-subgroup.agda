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
open import Setoid.Homomorphisms.Basic               using ( IsHom )
open import Classical.Structures.Group.Subgroups     using ( mkIsSubgroup ; interp-tuple-∙ ; interp-tuple-ε ; interp-tuple-⁻¹ )
open import Classical.Signatures.Group               using ( ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Bundles.Group                  using ( ⟨_⟩ᵍᵖ )
open import Classical.Operations                     using ( pair )
import Algebra.Properties.Group as GroupProperties

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
    open Setoid 𝔻[ proj₁ 𝓗 ] using () renaming ( refl to reflᴴ ; sym to symᴴ ; trans to transᴴ )
    open Group-Op 𝓗 using () renaming ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ ; ∙-cong to ∙ᴴ-cong
      ; ⁻¹-cong to ⁻¹ᴴ-cong ; idˡ-law to idˡᴴ ; idʳ-law to idʳᴴ ; invˡ-law to invˡᴴ ; invʳ-law to invʳᴴ )
    open GroupProperties ⟨ 𝓗 ⟩ᵍᵖ using ( ε⁻¹≈ε ; ⁻¹-involutive ; inverseʳ-unique )
    open IsHom hhom using ( compatible )

    hom-∙ : ∀ x y → h (x ∙ y) ≈ᴴ (h x ∙ᴴ h y)
    hom-∙ x y = transᴴ (compatible {∙-Op} {pair x y}) (interp-tuple-∙ 𝓗 _)

    hom-ε : h (Group-Op.ε 𝒢) ≈ᴴ εᴴ
    hom-ε = transᴴ (compatible {ε-Op} {λ ()}) (interp-tuple-ε 𝓗 _)

    hom-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ (h x ⁻¹ᴴ)
    hom-⁻¹ x = transᴴ (compatible {⁻¹-Op} {λ _ → x}) (interp-tuple-⁻¹ 𝓗 _)

    sub : IsSubgroup 𝒢 Ker
    sub = mkIsSubgroup 𝒢
      (λ x≈y p → transᴴ (symᴴ (_⟶_.cong hmap x≈y)) p)
      (λ {x} {y} p q → transᴴ (hom-∙ x y) (transᴴ (∙ᴴ-cong p q) (idˡᴴ εᴴ)))
      hom-ε
      (λ {x} p → transᴴ (hom-⁻¹ x) (transᴴ (⁻¹ᴴ-cong p) ε⁻¹≈ε))

    nrm : Conjugate.IsNormal 𝒢 Ker
    nrm g {x} p =
      transᴴ (hom-∙ (g ∙ x) (g ⁻¹))
      (transᴴ (∙ᴴ-cong (transᴴ (hom-∙ g x) (transᴴ (∙ᴴ-cong reflᴴ p) (idʳᴴ (h g)))) (hom-⁻¹ g))
      (invʳᴴ (h g)))

    coset : ∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker)
    coset x y = fwd , bwd
      where
      eq : h (x ⁻¹ ∙ y) ≈ᴴ (h x ⁻¹ᴴ ∙ᴴ h y)
      eq = transᴴ (hom-∙ (x ⁻¹) y) (∙ᴴ-cong (hom-⁻¹ x) reflᴴ)

      fwd : (x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y
      fwd p = symᴴ (transᴴ (inverseʳ-unique (h x ⁻¹ᴴ) (h y) (transᴴ (symᴴ eq) p)) (⁻¹-involutive (h x)))

      bwd : h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker
      bwd q = transᴴ eq (transᴴ (∙ᴴ-cong reflᴴ (symᴴ q)) (invˡᴴ (h x)))
