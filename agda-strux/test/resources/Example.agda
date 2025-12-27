-- Example.agda
--
-- File: agda-backend-json/tests/resources/Example.agda
--
-- Description:
-- This file contains a simple Agda module that defines a few basic functions
-- and types. It serves as a test case for the Agda JSON backend.

module Example where

open import Agda.Builtin.Nat      using (Nat; zero; suc)
open import Agda.Builtin.Equality using (_≡_; refl)

foo : Nat
foo = suc zero

foo-id : foo ≡ suc zero
foo-id = refl
