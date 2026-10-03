-- Group-correspondence-over-N.agda
--
-- File: data/benchmarks/agda-algebras-hard-v0/obligations/Group-correspondence-over-N.agda
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

  private
    𝑮 = proj₁ 𝒢

  open Setoid 𝔻[ 𝑮 ]  using ( _≈_ )
                      renaming ( refl to ≈refl ; sym to ≈sym ; trans to ≈trans )
  open Group-Op 𝒢     using ( _∙_ ; ε ; _⁻¹ ; ∙-cong ; assoc-law
                            ; invʳ-law ; invˡ-law ; idˡ-law ; idʳ-law )
  open IsSubgroup H-sub using ()
    renaming ( respects to H-respects ; ∙-closed to H-∙-closed ; ε-closed to H-ε-closed )
  open IsSubgroup N-sub using () renaming ( respects to N-respects )

  private
    ε⁻¹≈ε : ε ⁻¹ ≈ ε
    ε⁻¹≈ε = ≈trans (≈sym (idʳ-law (ε ⁻¹))) (invˡ-law ε)

    ⊆⇒Respects : N ⊆ H → H Respects _∼_
    ⊆⇒Respects N⊆H {x} {y} x∼y x∈H =
      H-respects eq (H-∙-closed x∈H (N⊆H x∼y))
      where
      eq : x ∙ (x ⁻¹ ∙ y) ≈ y
      eq = ≈trans (≈sym (assoc-law x (x ⁻¹) y))
                  (≈trans (∙-cong (invʳ-law x) ≈refl) (idˡ-law y))

    Respects⇒⊆ : H Respects _∼_ → N ⊆ H
    Respects⇒⊆ H-resp {n} n∈N = H-resp (N-respects (≈sym eq) n∈N) H-ε-closed
      where
      eq : ε ⁻¹ ∙ n ≈ n
      eq = ≈trans (∙-cong ε⁻¹≈ε ≈refl) (idˡ-law n)

  correspondence-over-N : (N ⊆ H → H Respects _∼_) × (H Respects _∼_ → N ⊆ H)
  correspondence-over-N = ⊆⇒Respects , Respects⇒⊆
