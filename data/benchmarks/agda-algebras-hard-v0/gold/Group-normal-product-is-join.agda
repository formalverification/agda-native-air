-- Group-normal-product-is-join.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/gold/Group-normal-product-is-join.agda
--
-- Benchmark obligation: hard-group-normal-product-is-join
-- Difficulty: non-obvious
-- Source: Classical.Structures.Group (Complexes, Conjugation, NormalSubgroupLattice has meets and no join)
-- Import stratum: novel
-- Strategy: conjugate a product elementwise; for leastness use closure of P under products
-- (ℓᵖ, the level of the comparison subgroup P, is a parameter so the statement stays in Set)
--
-- The complex product of two normal subgroups is normal, and it is their join: it contains both, and it lies inside every subgroup containing both.
--
-- GOLD WANTED
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
  normal-product-is-join = {!!}
