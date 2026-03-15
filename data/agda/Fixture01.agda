-- Fixture01.agda
--
-- File: data/agda/Fixture01.agda
--
-- Description:
--   Tiny fixture for deterministic Agda-check evaluation.  Intended to be solved by
--   the scripted fixture policy.  These are very simple examples of holes that can
--   be used to test the behavior of the hole policy.  Each hole (`?`) should be
--   filled in by the hole policy according to the context and goal.
--
module Fixture01 where

open import Agda.Builtin.Unit
open import Agda.Builtin.Equality
open import AgdaDojang.Debug

-- Goal is A, ctx has x : A  → policy proposes "x"
id : {A : Set} → A → A
id x = {!!}

-- Goal is ⊤ → policy proposes "tt"
trivial : ⊤
trivial = {!!}

-- Goal is x ≡ x → policy proposes "refl"
reflExample : {A : Set} (x : A) → x ≡ x
reflExample x = {!!}
