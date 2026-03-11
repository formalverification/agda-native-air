-- agda-example.agda
--
-- File: data/agda/agda-example.agda
--
-- Description:
--   An example of a simple Agda module defining natural numbers and proving a
--   property about addition.  This serves as a test case for the Agda JSON backend,
--   ensuring that it can handle basic data types, functions, and proofs. The module
--   defines the natural numbers, a recursive addition function, and a proof that
--   addition is commutative. The proof uses pattern matching and recursion,
--   demonstrating how the Agda JSON backend can represent complex proofs and their
--   dependencies.

open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong; trans)

module agda-example where

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
