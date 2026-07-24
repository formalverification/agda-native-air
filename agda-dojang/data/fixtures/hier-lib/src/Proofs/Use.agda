-- Use.agda
--
-- File: agda-dojang/data/fixtures/hier-lib/src/Proofs/Use.agda
--
-- Description:
--   Regression fixture for issue #66: a hierarchically-named module (`Proofs.Use`)
--   embedded in a library (`hier-lib`) that imports across a sibling directory
--   (`Widgets.Thing`).  This is the shape that broke the old temp-copy get_goal /
--   fill_hole path (ModuleDefinedInOtherFile), and that the in-place implementation
--   must handle.
--
--   It deliberately does NOT `open import AgdaDojang.Debug`, so exercising get_goal
--   on it also tests the transient import injection.
module Proofs.Use where

open import Agda.Builtin.Nat
open import Agda.Builtin.Unit
open import Widgets.Thing

-- A single hole with a local variable in context, mirroring Fixture01's `id x`.
-- Correct fill: `thing` (a cross-directory Nat).  Ill-typed fill: `tt` (⊤ ≢ Nat).
useIt : Nat → Nat
useIt x = {!!}
