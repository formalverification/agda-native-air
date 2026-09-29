-- Group-normal-product-is-join.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/obligations/Group-normal-product-is-join.agda
--
-- Benchmark obligation: hard-group-normal-product-is-join
-- Difficulty: non-obvious
-- Import stratum: novel
-- (ℓᵖ, the level of the comparison subgroup P, is a parameter so the statement stays in Set)
--
-- The complex product of two normal subgroups is normal, and it is their join: it contains both, and it lies inside every subgroup containing both.
--
module Group-normal-product-is-join where

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
open import Classical.Structures.Group.Complexes     using ( module Complex )

module _ {α ρ ℓ ℓ' : Level} (ℓᵖ : Level) (𝒢 : Group α ρ)
  (N : Pred 𝕌[ proj₁ 𝒢 ] ℓ)  (N-sub : IsSubgroup 𝒢 N) (N-normal : Conjugate.IsNormal 𝒢 N)
  (M : Pred 𝕌[ proj₁ 𝒢 ] ℓ') (M-sub : IsSubgroup 𝒢 M) (M-normal : Conjugate.IsNormal 𝒢 M)
  where
  open Complex 𝒢 using ( _∙ᶜ_ )
  open Conjugate 𝒢 using ( IsNormal ; conj-cong ; conj-∙-hom )
  open Group-Op 𝒢 using ( _∙_ ; ε ; idˡ-law ; idʳ-law )
  open Setoid 𝔻[ proj₁ 𝒢 ] using ( _≈_ ) renaming ( sym to ≈sym ; trans to ≈trans )
  open IsSubgroup N-sub using () renaming ( ε-closed to N-ε )
  open IsSubgroup M-sub using () renaming ( ε-closed to M-ε )

  normal-product-is-join
    :  Conjugate.IsNormal 𝒢 (N ∙ᶜ M)
    ×  (N ⊆ (N ∙ᶜ M)) × (M ⊆ (N ∙ᶜ M))
    ×  (∀ {P : Pred 𝕌[ proj₁ 𝒢 ] ℓᵖ} → IsSubgroup 𝒢 P → N ⊆ P → M ⊆ P → (N ∙ᶜ M) ⊆ P)
  normal-product-is-join = nrm , N⊆NM , M⊆NM , least
    where
    nrm : IsNormal (N ∙ᶜ M)
    nrm g (n , m , n∈N , m∈M , x≈nm) =
      _ , _ , N-normal g n∈N , M-normal g m∈M
        , ≈trans (conj-cong g x≈nm) (conj-∙-hom g n m)

    N⊆NM : N ⊆ (N ∙ᶜ M)
    N⊆NM {x} x∈N = x , ε , x∈N , M-ε , ≈sym (idʳ-law x)

    M⊆NM : M ⊆ (N ∙ᶜ M)
    M⊆NM {x} x∈M = ε , x , N-ε , x∈M , ≈sym (idˡ-law x)

    least : ∀ {P : Pred 𝕌[ proj₁ 𝒢 ] ℓᵖ}
      →  IsSubgroup 𝒢 P → N ⊆ P → M ⊆ P → (N ∙ᶜ M) ⊆ P
    least {P} P-sub N⊆P M⊆P (n , m , n∈N , m∈M , x≈nm) =
      respects (≈sym x≈nm) (∙-closed (N⊆P n∈N) (M⊆P m∈M))
      where open IsSubgroup P-sub using ( respects ; ∙-closed )
