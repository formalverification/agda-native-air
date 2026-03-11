-- Example.agda
--
-- File: data/agda/Example.agda
--
-- Description:
-- This file contains a simple Agda module that defines a few basic functions
-- and types. It serves as a test case for the Agda JSON backend.

module Example where

open import Agda.Builtin.Nat      using (Nat; zero; suc)
open import Agda.Builtin.Equality using (_≡_; refl)

foo : Nat → Nat
foo n = suc n

foo-id : Nat → Nat
foo-id n = n

foo-id-correct : (n : Nat) → foo-id n ≡ n
foo-id-correct n = refl

-- Anonymous section: defs here often live in *section signatures*
module _ {A : Set} where
  secId : A → A
  secId x = x

-- Named nested module: should also be included if we do prefix filtering
module Nested where
  bar : Nat
  bar = zero
