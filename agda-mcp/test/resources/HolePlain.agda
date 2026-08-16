-- HolePlain.agda
--
-- File: agda-native-air/agda-mcp/test/resources/HolePlain.agda
--
-- Description:
--   Plain-Agda twin of the code embedded in LiterateMd.lagda.md (and the
--   other literate fixtures): the same declarations, with the same single
--   {! zero !} hole.  Issue #73's acceptance criterion is that get_goal and
--   fill_hole behave identically on this file and on the literate twins.
module HolePlain where

open import Agda.Builtin.Nat

n : Nat
n = {! zero !}
