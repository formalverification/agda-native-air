-- FixtureLet.agda
--
-- File: data/agda/FixtureLet.agda
--
module FixtureLet where

open import Agda.Builtin.Unit
open import AgdaJang.Debug

foo : {A : Set} → A → A
foo {A} x =
  let  z : A
       z = {!!}  -- ctx should include x : A
  in z
