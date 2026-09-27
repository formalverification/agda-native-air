-- Group-intersection-normal-in-subgroup.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/gold/Group-intersection-normal-in-subgroup.agda
--
-- Benchmark obligation: hard-group-intersection-normal-in-subgroup
-- Difficulty: compositional
-- Source: group theory qualifying exam 2000 Nov 10, problem 2 (Classical.Structures.Group)
-- Import stratum: novel
-- Strategy: closure of H under conjugation by its own elements, and normality of K in G, read elementwise
--
-- For a subgroup H and a normal subgroup K of G, H ∩ K is normal in H: conjugating an element of H ∩ K by an element of H stays in H ∩ K.
--
-- GOLD WANTED
module Group-intersection-normal-in-subgroup where

open import AgdaDojang.Debug

open import Data.Product                  using ( _,_ ; _×_ ; Σ-syntax ; proj₁ ; proj₂ )
open import Level                         using ( Level )
open import Relation.Binary               using ( Setoid )
open import Relation.Unary                using ( Pred ; _∈_ )

open import Classical.Structures.Group.Basic         using ( Group ; module Group-Op )
open import Classical.Structures.Group.Subgroups     using ( IsSubgroup )
open import Classical.Structures.Group.Conjugation   using ( module Conjugate )
open import Setoid.Algebras.Basic                    using ( 𝕌[_] ; 𝔻[_] )

module _ {α ρ ℓ ℓ' : Level} (𝒢 : Group α ρ)
  (H : Pred 𝕌[ proj₁ 𝒢 ] ℓ)  (H-sub : IsSubgroup 𝒢 H)
  (K : Pred 𝕌[ proj₁ 𝒢 ] ℓ') (K-sub : IsSubgroup 𝒢 K) (K-normal : Conjugate.IsNormal 𝒢 K)
  where
  open Group-Op 𝒢 using ( _∙_ ; _⁻¹ )

  intersection-normal-in-subgroup
    :  ∀ {h x} → h ∈ H → x ∈ H → x ∈ K → ((h ∙ x) ∙ h ⁻¹ ∈ H) × ((h ∙ x) ∙ h ⁻¹ ∈ K)
  intersection-normal-in-subgroup h∈H x∈H x∈K = {!!}
