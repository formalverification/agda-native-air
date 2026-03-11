-- File: data/agda/AddCommExample.agda

module AddCommExample where

open import Agda.Primitive using (Level)
open import Agda.Builtin.Equality using (_≡_; refl)
open import Proofs using (Transitive)

private
  variable
    a : Level
    A B : Set a

cong : ∀ (f : A → B) {x y} → x ≡ y → f x ≡ f y
cong f refl = refl

trans : Transitive {A = A} _≡_
trans refl eq = eq

data ℕ : Set where
  zero  : ℕ
  suc   : ℕ → ℕ

_+_ : ℕ → ℕ → ℕ
zero   + n = n
suc m  + n = suc (m + n)

module properties where

  +-comm : (m n : ℕ) → m + n ≡ n + m
  +-comm zero     zero     = refl
  +-comm zero     (suc n)  = cong suc (+-comm zero n)
  +-comm (suc m)  zero     = cong suc (+-comm m zero)
  +-comm (suc m)  (suc n)  = cong suc (trans (+-suc m n) (+-comm (suc m) n))
    where +-suc : ∀ m n → m + suc n ≡ suc (m + n)
          +-suc zero     n = refl
          +-suc (suc m)  n = cong suc (+-suc m n)
