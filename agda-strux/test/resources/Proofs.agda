{-# OPTIONS --safe #-}

module Proofs where

open import Agda.Primitive using (Level; _⊔_; Set)
open import Relation.Binary.Core using (Rel)
open import Relation.Binary.Definitions using (Reflexive; Transitive)

private
  variable
    a ρ : Level

module _ {A : Set (a ⊔ ρ)} where

  _⊑_ : Rel A ρ → Rel A ρ → Set (a ⊔ ρ)
  P ⊑ Q = ∀ x y → P x y → Q x y

  ⊑-refl : Reflexive _⊑_
  ⊑-refl = λ _ _ z → z

  ⊑-trans : Transitive _⊑_
  ⊑-trans P⊑Q Q⊑R x y Pxy = Q⊑R x y (P⊑Q x y Pxy)

  ⊑-trans' : Transitive _⊑_
  ⊑-trans' {P}{Q}{R} = λ P⊑Q Q⊑R x y Pxy → Q⊑R x y (P⊑Q x y Pxy)

  ⊑-trans'' : Transitive _⊑_
  ⊑-trans'' {P}{Q}{R} = λ (h₁ : P ⊑ Q) (h₂ : Q ⊑ R) x y (h₃ : P x y) → h₂ x y (h₁ x y h₃)
