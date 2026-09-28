-- Group-correspondence-over-N.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/gold/Group-correspondence-over-N.agda
--
-- Benchmark obligation: hard-group-correspondence-over-N
-- Difficulty: compositional
-- Import stratum: novel
--
-- A subgroup H of G contains the normal subgroup N exactly when H respects N-cosets, that is, when H is a subgroup of G/N on the same carrier.
--
module Group-correspondence-over-N where

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
open import Classical.Structures.Group.Cosets        using ( module Coset )

module _ {α ρ ℓ : Level} (𝒢 : Group α ρ)
  (N : Pred 𝕌[ proj₁ 𝒢 ] ℓ) (N-sub : IsSubgroup 𝒢 N) (N-normal : Conjugate.IsNormal 𝒢 N)
  (H : Pred 𝕌[ proj₁ 𝒢 ] ℓ) (H-sub : IsSubgroup 𝒢 H)
  where
  open Coset 𝒢 N N-sub using ( _∼_ )

  correspondence-over-N : (N ⊆ H → H Respects _∼_) × (H Respects _∼_ → N ⊆ H)
  correspondence-over-N = N⊆H⇒H-resp-∼ , H-resp-∼⇒N⊆H
    where
    open import Classical.Bundles.Group using ( ⟨_⟩ᵍᵖ )
    open import Algebra.Properties.Group ⟨ 𝒢 ⟩ᵍᵖ using ( \\-leftDividesˡ )
    module N = IsSubgroup N-sub
    module H = IsSubgroup H-sub

    -- y ≈ x ∙ (x ⁻¹ ∙ y), a product of x ∈ H and x ⁻¹ ∙ y ∈ N ⊆ H.
    N⊆H⇒H-resp-∼ : N ⊆ H → H Respects _∼_
    N⊆H⇒H-resp-∼ N⊆H {x} {y} x∼y x∈H =
      H.respects (\\-leftDividesˡ x y) (H.∙-closed x∈H (N⊆H x∼y))

    -- ε ∼ n, since ε ⁻¹ ∙ n ∈ N by closure of N; and ε ∈ H.
    H-resp-∼⇒N⊆H : H Respects _∼_ → N ⊆ H
    H-resp-∼⇒N⊆H H-resp-∼ {n} n∈N =
      H-resp-∼ (N.∙-closed (N.⁻¹-closed N.ε-closed) n∈N) H.ε-closed
