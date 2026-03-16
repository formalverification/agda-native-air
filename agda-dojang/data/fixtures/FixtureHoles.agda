-- FixtureHoles.agda
--
-- File: agda-dojang/data/fixtures/FixtureHoles.agda
--
-- Description:
--   This module contains some simple examples of holes that we can use to test
--   the behavior of the hole policy. Each function has a hole (`?`) that should be
--   filled in by the hole policy according to the context and goal.
--

module FixtureHoles where

open import Agda.Builtin.Unit
open import Agda.Builtin.Equality
open import AgdaDojang.Debug

-- Goal is A, context has x : A  -> policy proposes "x"
id : {A : Set} → A → A
id x = {!!}

-- Goal is ⊤ -> policy proposes "tt"
trivial : ⊤
trivial = {!!}

-- Goal is x ≡ x -> policy proposes "refl"
reflExample : {A : Set} (x : A) → x ≡ x
reflExample x = {!!}

-- Goal is A, context has a : A -> policy proposes "a"
useCtx : {A : Set} (a : A) → A
useCtx a = {!!}
