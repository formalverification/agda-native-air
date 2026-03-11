-- FixtureWhere.agda
--
-- File: data/agda/FixtureWhere.agda
--

module FixtureWhere where

open import Agda.Builtin.Unit
open import AgdaJang.Debug

foo : {A : Set} → A → A
foo {A} x = y
  where
    y : A
    y = {!!}  -- ctx should include x : A
