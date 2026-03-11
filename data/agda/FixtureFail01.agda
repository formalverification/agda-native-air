-- FixtureFail01.agda
--
-- File: data/agda/FixtureFail01.agda
--
-- Description:
--   Tiny fixture for deterministic Agda-check evaluation.  Intended to be solved by
--   the scripted fixture policy.  These are very simple examples of holes that can
--   be used to test the behavior of the hole policy.  Each hole (`?`) should be
--   filled in by the hole policy according to the context and goal.
--
module FixtureFail01 where

open import Agda.Builtin.Nat
open import AgdaJang.Debug

-- If policy doesn’t know Nat yet (zero), this should remain unsolved deterministically.
needNat : Nat
needNat = {!!}
