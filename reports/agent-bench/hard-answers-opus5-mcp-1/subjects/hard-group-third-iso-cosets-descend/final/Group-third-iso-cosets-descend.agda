-- Group-third-iso-cosets-descend.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/obligations/Group-third-iso-cosets-descend.agda
--
-- Benchmark obligation: hard-group-third-iso-cosets-descend
-- Difficulty: compositional
-- Import stratum: novel
--
-- For normal subgroups N ⊆ M of G, the M-coset relation descends to G/N: it contains the N-coset relation, and it respects N-cosets in both arguments, which is the statement (G/N)/(M/N) ≅ G/M on the carrier G.
--
module Group-third-iso-cosets-descend where

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
  (M : Pred 𝕌[ proj₁ 𝒢 ] ℓ) (M-sub : IsSubgroup 𝒢 M) (M-normal : Conjugate.IsNormal 𝒢 M)
  (N⊆M : N ⊆ M)
  where
  open Coset 𝒢 N N-sub using () renaming ( _∼_ to _∼ᴺ_ )
  open Coset 𝒢 M M-sub using () renaming ( _∼_ to _∼ᴹ_ )

  third-iso-cosets-descend
    :  (∀ {x y} → x ∼ᴺ y → x ∼ᴹ y)
    ×  (∀ {x x' y y'} → x ∼ᴺ x' → y ∼ᴺ y' → x ∼ᴹ y → x' ∼ᴹ y')
  third-iso-cosets-descend = descendsᴹ , respectsᴺ
    where
    open Coset 𝒢 M M-sub using () renaming ( ∼-sym to ∼ᴹ-sym ; ∼-trans to ∼ᴹ-trans )

    descendsᴹ : ∀ {x y} → x ∼ᴺ y → x ∼ᴹ y
    descendsᴹ x∼ᴺy = N⊆M x∼ᴺy

    respectsᴺ : ∀ {x x' y y'} → x ∼ᴺ x' → y ∼ᴺ y' → x ∼ᴹ y → x' ∼ᴹ y'
    respectsᴺ x∼ᴺx' y∼ᴺy' x∼ᴹy =
      ∼ᴹ-trans (∼ᴹ-trans (∼ᴹ-sym (descendsᴹ x∼ᴺx')) x∼ᴹy) (descendsᴹ y∼ᴺy')
