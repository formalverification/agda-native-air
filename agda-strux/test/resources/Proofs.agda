-- File: agda-backend-jsonl/test/resources/Proofs.agda

{-# OPTIONS --safe #-}

module Proofs where

open import Agda.Primitive using (Level; _⊔_; lsuc)

private variable
  a b c ρ ℓ ℓ₁ ℓ₂ ℓ₃ : Level
  A : Set a
  B : Set b
  C : Set c

-- Heterogeneous binary relations

REL : Set a → Set b → (ℓ : Level) → Set (a ⊔ b ⊔ lsuc ℓ)
REL A B ℓ = A → B → Set ℓ

-- Homogeneous binary relations

Rel : Set a → (ℓ : Level) → Set (a ⊔ lsuc ℓ)
Rel A ℓ = REL A A ℓ

Reflexive : {A : Set a} → Rel A ℓ → Set _
Reflexive _∼_ = ∀ {x} → x ∼ x

Trans : REL A B ℓ₁ → REL B C ℓ₂ → REL A C ℓ₃ → Set _
Trans P Q R = ∀ {i j k} → P i j → Q j k → R i k

Transitive : {A : Set a} → Rel A ℓ → Set _
Transitive _∼_ = Trans _∼_ _∼_ _∼_

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
