-- HoleImportDecoy.agda
--
-- File: agda-native-air/agda-mcp/test/resources/HoleImportDecoy.agda
--
-- Description:
--   Regression fixture from Copilot's second review of PR 105 (issue #100): the
--   file's one hole holds three declaration-shaped lines — a bare
--   `open import AgdaDojang.Debug`, the same line inside a block comment, and a
--   `module … where` header.  Agda lexes `{! … !}` as a single token and never
--   parses what is inside, so all three are hole text; the file type-checks with
--   exactly one interaction point, which tier 2d confirms against Agda itself.
--
--   Read as code, though, the first line convinces get_goal's import injection
--   that AgdaDojang.Debug is already in scope, and the `module` line cuts the
--   prelude scan short.  The injection is then skipped, the hole (and with it the
--   decoy) is replaced by the reporting macro, and the call fails with
--   `reportGoalCtx` out of scope — measured, before the code-only view blanked
--   holes along with their contents.
module HoleImportDecoy where

open import Agda.Builtin.Nat

n : Nat
n = {!
open import AgdaDojang.Debug
{-
open import AgdaDojang.Debug
-}
module Decoy where
zero !}
