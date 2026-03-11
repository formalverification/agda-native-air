-- FixtureLambda.agda
--
-- File: data/agda/FixtureLambda.agda
--
module FixtureLambda where

open import Agda.Builtin.Unit
open import AgdaJang.Debug

foo : {A : Set} → A → A
foo = λ x → {!!}  -- ctx should include x : A
