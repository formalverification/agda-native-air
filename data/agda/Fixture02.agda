-- Fixture02.agda
--
-- File: data/agda/Fixture02.agda
--
module Fixture02 where

open import Agda.Builtin.Unit
open import Agda.Builtin.Equality
open import AgdaJang.Debug

-- Multiple ctx vars of the same type; any is acceptable.
useCtx1 : {A : Set} (a : A) (b : A) → A
useCtx1 a b = {!!}

useCtx2 : {A : Set} (a : A) → A
useCtx2 a = {!!}

-- Another ⊤ goal
trivial2 : ⊤
trivial2 = {!!}
