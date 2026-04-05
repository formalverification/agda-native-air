-- Fixture01.agda
--
-- File: agda-dojang/data/fixtures/Fixture01.agda
--
-- Description:
--   Tiny fixture for deterministic Agda-check evaluation.  These are very simple
--   examples of holes that can be used to test automated hole filling tools.
--
module Fixture01 where

open import Agda.Builtin.Unit
open import Agda.Builtin.Equality
open import AgdaDojang.Debug

id : {A : Set} → A → A
id x = x

trivial : ⊤
trivial = tt

reflExample : {A : Set} (x : A) → x ≡ x
reflExample x = refl
