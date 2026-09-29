-- Group-second-iso-cosets-agree.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/obligations/Group-second-iso-cosets-agree.agda
--
-- Benchmark obligation: hard-group-second-iso-cosets-agree
-- Difficulty: non-obvious
-- Import stratum: novel
--
-- The inclusion H → HK is well defined and injective on cosets: for h₁, h₂ in H, h₁ and h₂ lie in the same coset of H ∩ K exactly when they lie in the same coset of K.  The subgroup H ∩ K is built here so the statement can name its cosets.
--
module Group-second-iso-cosets-agree where

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

  -- The intersection, with its subgroup proof (provided, not to be proved here).
  H∩K : Pred G ℓ
  H∩K x = x ∈ H × x ∈ K

  H∩K-sub : IsSubgroup 𝒢 H∩K
  H∩K-sub = record
    { respects      = λ x≈y (x∈H , x∈K) → IsSubgroup.respects H-sub x≈y x∈H , IsSubgroup.respects K-sub x≈y x∈K
    ; isSubuniverse = λ f a im → IsSubgroup.isSubuniverse H-sub f a (λ i → proj₁ (im i))
                                , IsSubgroup.isSubuniverse K-sub f a (λ i → proj₂ (im i))
    }

  open Coset 𝒢 H∩K H∩K-sub using () renaming ( _∼_ to _∼ᴴ∩ᴷ_ )
  open Coset 𝒢 K   K-sub   using () renaming ( _∼_ to _∼ᴷ_ )

  second-iso-cosets-agree
    :  ∀ {h₁ h₂} → h₁ ∈ H → h₂ ∈ H → (h₁ ∼ᴴ∩ᴷ h₂ → h₁ ∼ᴷ h₂) × (h₁ ∼ᴷ h₂ → h₁ ∼ᴴ∩ᴷ h₂)
  second-iso-cosets-agree h₁∈H h₂∈H = proj₂ , λ h₁∼ᴷh₂ → H-closed , h₁∼ᴷh₂
    where
    open IsSubgroup H-sub using ( ∙-closed ; ⁻¹-closed )
    H-closed = ∙-closed (⁻¹-closed h₁∈H) h₂∈H
