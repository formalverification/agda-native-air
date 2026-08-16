-- DiagAmbigB.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/DiagAmbigB.agda
--
-- Description:
--   Helper for the AmbiguousName fixture (issue #74, feedback document § 5):
--   the second module exporting `shared`.  See DiagAmbigA.agda.
module DiagAmbigB where

open import Agda.Builtin.Nat

shared : Nat
shared = suc zero
