-- Group-second-iso-cosets-onto.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/obligations/Group-second-iso-cosets-onto.agda
--
-- Benchmark obligation: hard-group-second-iso-cosets-onto
-- Difficulty: non-obvious
-- Import stratum: novel
--
-- The inclusion H → HK is onto the cosets of K in HK: every element of the complex product H ∙ᶜ K lies in the K-coset of some element of H.
--
module Group-second-iso-cosets-onto where

open import AgdaDojang.Debug

open import Data.Product                  using ( _,_ ; _×_ ; Σ-syntax ; proj₁ ; proj₂ )
open import Level                         using ( Level )
open import Relation.Binary               using ( Setoid )
open import Relation.Unary                using ( Pred ; _∈_ )

open import Classical.Structures.Group.Basic         using ( Group ; module Group-Op )
open import Classical.Structures.Group.Subgroups     using ( IsSubgroup )
open import Classical.Structures.Group.Conjugation   using ( module Conjugate )
open import Setoid.Algebras.Basic                    using ( 𝕌[_] ; 𝔻[_] )
open import Classical.Structures.Group.Complexes     using ( module Complex )
open import Classical.Structures.Group.Cosets        using ( module Coset )

module _ {α ρ ℓ : Level} (𝒢 : Group α ρ)
  (H : Pred 𝕌[ proj₁ 𝒢 ] ℓ) (H-sub : IsSubgroup 𝒢 H)
  (K : Pred 𝕌[ proj₁ 𝒢 ] ℓ) (K-sub : IsSubgroup 𝒢 K) (K-normal : Conjugate.IsNormal 𝒢 K)
  where
  private
    𝑮 = proj₁ 𝒢
    G = 𝕌[ 𝑮 ]
  open Complex 𝒢 using ( _∙ᶜ_ )
  open Coset 𝒢 K K-sub using ( _∼_ )

  second-iso-cosets-onto : ∀ {x} → x ∈ (H ∙ᶜ K) → Σ[ h ∈ G ] (h ∈ H × x ∼ h)
  second-iso-cosets-onto x∈HK = {!!}
