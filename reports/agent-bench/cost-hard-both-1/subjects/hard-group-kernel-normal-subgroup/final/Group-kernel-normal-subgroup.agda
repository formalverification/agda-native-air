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

open import Classical.Operations                     using ( pair )
open import Classical.Signatures.Group               using ( Op-Group ; ar-Group
                                                          ; ∙-Op ; ε-Op ; ⁻¹-Op )
open import Classical.Structures.Group.Subgroups     using ( mkIsSubgroup ; interp-tuple-∙
                                                          ; interp-tuple-ε ; interp-tuple-⁻¹ )
open import Setoid.Algebras.Basic                    using ( _^_ )
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

  private
    𝑯 = proj₁ 𝓗

  open Setoid 𝔻[ 𝑮 ]  using () renaming ( _≈_ to _≈ᴳ_ )
  open Setoid 𝔻[ 𝑯 ]  using () renaming ( refl to reflᴴ ; sym to symᴴ ; trans to transᴴ )
  open Group-Op 𝒢 using () renaming ( ε to εᴳ )
  open Group-Op 𝓗 using ()
    renaming  ( _∙_ to _∙ᴴ_ ; _⁻¹ to _⁻¹ᴴ ; ∙-cong to ∙-congᴴ ; ⁻¹-cong to ⁻¹-congᴴ
              ; assoc-law to assoc-lawᴴ ; idˡ-law to idˡ-lawᴴ ; idʳ-law to idʳ-lawᴴ
              ; invˡ-law to invˡ-lawᴴ ; invʳ-law to invʳ-lawᴴ )

  Ker : Pred G ρᵇ
  Ker x = h x ≈ᴴ εᴴ

  -- h is a setoid function, hence respects the equality of 𝑮.
  hcong : ∀ {x y} → x ≈ᴳ y → h x ≈ᴴ h y
  hcong = _⟶_.cong hmap

  -- The compatibility law of the homomorphism, in tuple-indexed form.
  compat : (f : Op-Group) (a : ar-Group f → G) → h ((f ^ 𝑮) a) ≈ᴴ (f ^ 𝑯) (λ i → h (a i))
  compat f a = IsHom.compatible hhom

  -- The three curried homomorphism laws, got from `compat` by the
  -- tuple-vs-curried interpretation bridges of the codomain.
  h-∙ : ∀ x y → h (x ∙ y) ≈ᴴ (h x ∙ᴴ h y)
  h-∙ x y = transᴴ (compat ∙-Op (pair x y)) (interp-tuple-∙ 𝓗 (λ i → h (pair x y i)))

  h-ε : h εᴳ ≈ᴴ εᴴ
  h-ε = transᴴ (compat ε-Op (λ ())) (interp-tuple-ε 𝓗 _)

  h-⁻¹ : ∀ x → h (x ⁻¹) ≈ᴴ (h x) ⁻¹ᴴ
  h-⁻¹ x = transᴴ (compat ⁻¹-Op (λ _ → x)) (interp-tuple-⁻¹ 𝓗 _)

  -- The identity of 𝓗 is its own inverse.
  ε⁻¹≈εᴴ : (εᴴ ⁻¹ᴴ) ≈ᴴ εᴴ
  ε⁻¹≈εᴴ = transᴴ (symᴴ (idʳ-lawᴴ (εᴴ ⁻¹ᴴ))) (invˡ-lawᴴ εᴴ)

  -- The kernel predicate respects ≈, by the congruence of h.
  Ker-respects : Ker Respects _≈ᴳ_
  Ker-respects x≈y hx≈ε = transᴴ (symᴴ (hcong x≈y)) hx≈ε

  Ker-∙-closed : ∀ {x y} → x ∈ Ker → y ∈ Ker → (x ∙ y) ∈ Ker
  Ker-∙-closed {x} {y} hx hy = transᴴ (h-∙ x y) (transᴴ (∙-congᴴ hx hy) (idˡ-lawᴴ εᴴ))

  Ker-⁻¹-closed : ∀ {x} → x ∈ Ker → (x ⁻¹) ∈ Ker
  Ker-⁻¹-closed {x} hx = transᴴ (h-⁻¹ x) (transᴴ (⁻¹-congᴴ hx) ε⁻¹≈εᴴ)

  Ker-isSubgroup : IsSubgroup 𝒢 Ker
  Ker-isSubgroup = mkIsSubgroup 𝒢 Ker-respects Ker-∙-closed h-ε Ker-⁻¹-closed

  -- Normality: conjugating an element of the kernel conjugates εᴴ, which is εᴴ.
  Ker-isNormal : Conjugate.IsNormal 𝒢 Ker
  Ker-isNormal g {x} hx =
    transᴴ  (h-∙ (g ∙ x) (g ⁻¹))
            (transᴴ  (∙-congᴴ (h-∙ g x) (h-⁻¹ g))
                     (transᴴ  (∙-congᴴ (∙-congᴴ reflᴴ hx) reflᴴ)
                              (transᴴ  (∙-congᴴ (idʳ-lawᴴ (h g)) reflᴴ)
                                       (invʳ-lawᴴ (h g)))))

  -- The fibers are the cosets: h (x ⁻¹ ∙ y) ≈ᴴ (h x) ⁻¹ ∙ᴴ h y.
  Ker-coset : ∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker)
  Ker-coset x y = fwd , bwd
    where
    key : h (x ⁻¹ ∙ y) ≈ᴴ ((h x) ⁻¹ᴴ ∙ᴴ h y)
    key = transᴴ (h-∙ (x ⁻¹) y) (∙-congᴴ (h-⁻¹ x) reflᴴ)

    fwd : (x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y
    fwd p = transᴴ  (symᴴ (idʳ-lawᴴ (h x)))
                    (transᴴ  (∙-congᴴ reflᴴ (symᴴ (transᴴ (symᴴ key) p)))
                             (transᴴ  (symᴴ (assoc-lawᴴ (h x) ((h x) ⁻¹ᴴ) (h y)))
                                      (transᴴ  (∙-congᴴ (invʳ-lawᴴ (h x)) reflᴴ)
                                               (idˡ-lawᴴ (h y)))))

    bwd : h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker
    bwd e = transᴴ key (transᴴ (∙-congᴴ reflᴴ (symᴴ e)) (invˡ-lawᴴ (h x)))

  kernel-normal-subgroup
    :  IsSubgroup 𝒢 Ker × Conjugate.IsNormal 𝒢 Ker
    ×  (∀ x y → ((x ⁻¹ ∙ y) ∈ Ker → h x ≈ᴴ h y) × (h x ≈ᴴ h y → (x ⁻¹ ∙ y) ∈ Ker))
  kernel-normal-subgroup = Ker-isSubgroup , Ker-isNormal , Ker-coset
