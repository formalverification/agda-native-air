-- Group-normal-product-is-join.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/gold/Group-normal-product-is-join.agda
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

  normal-product-is-join
    :  Conjugate.IsNormal 𝒢 (N ∙ᶜ M)
    ×  (N ⊆ (N ∙ᶜ M)) × (M ⊆ (N ∙ᶜ M))
    ×  (∀ {P : Pred 𝕌[ proj₁ 𝒢 ] ℓᵖ} → IsSubgroup 𝒢 P → N ⊆ P → M ⊆ P → (N ∙ᶜ M) ⊆ P)
  normal-product-is-join =
    ∙ᶜ-normal , mem-∙ᶜˡ (ε-closed M-sub) , mem-∙ᶜʳ (ε-closed N-sub) , ∙ᶜ-least
    where
    open import Classical.Structures.Group.Complements  using ( module Complements )
    open import Relation.Binary.Reasoning.Setoid 𝔻[ proj₁ 𝒢 ]
    open Group-Op 𝒢     using ( _∙_ )
    open Complex 𝒢      using ( ∙ᶜ-mono ; subgroup-∙ᶜ-idem )
    open Complements 𝒢  using ( mem-∙ᶜˡ ; mem-∙ᶜʳ )
    open Conjugate 𝒢    using ( conj-syntax ; conj-cong ; conj-∙-hom )
    open IsSubgroup     using ( ε-closed )

    -- Conjugating x ≈ n ∙ m by g gives n ^ g ∙ m ^ g, with n ^ g ∈ N and m ^ g ∈ M.
    ∙ᶜ-normal : Conjugate.IsNormal 𝒢 (N ∙ᶜ M)
    ∙ᶜ-normal g {x} (n , m , n∈N , m∈M , x≈nm) =
      n ^ g , m ^ g , N-normal g n∈N , M-normal g m∈M , (begin
        x ^ g          ≈⟨ conj-cong g x≈nm ⟩
        (n ∙ m) ^ g    ≈⟨ conj-∙-hom g n m ⟩
        n ^ g ∙ m ^ g  ∎)

    -- N ∙ᶜ M lies in P ∙ᶜ P, which the subgroup P absorbs.
    ∙ᶜ-least : ∀ {P : Pred 𝕌[ proj₁ 𝒢 ] ℓᵖ} → IsSubgroup 𝒢 P → N ⊆ P → M ⊆ P → (N ∙ᶜ M) ⊆ P
    ∙ᶜ-least P-sub N⊆P M⊆P x∈NM = proj₁ (subgroup-∙ᶜ-idem P-sub) (∙ᶜ-mono N⊆P M⊆P x∈NM)
