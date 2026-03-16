-- FixtureWhere.agda
--
-- File: agda-dojang/data/fixtures/FixtureWhere.agda
--

module FixtureWhere where

open import Agda.Builtin.Unit
open import AgdaDojang.Debug

foo : {A : Set} → A → A
foo {A} x = y
  where
    y : A
    y = {!!}  -- ctx should include x : A
