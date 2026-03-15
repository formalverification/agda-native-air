-- Fixture04.agda
--
-- File: data/agda/Fixture04.agda
--
module Fixture04 where

open import Agda.Builtin.Equality
open import AgdaDojang.Debug

-- Implicit binders still appear in context in the report; goal is x ≡ x.
reflImplicit : {A : Set} {x : A} → x ≡ x
reflImplicit = {!!}

reflImplicit2 : {A : Set} {x : A} → x ≡ x
reflImplicit2 = {!!}
