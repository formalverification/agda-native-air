-- DiagAmbigA.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/DiagAmbigA.agda
--
-- Description:
--   Helper for the AmbiguousName fixture (issue #74, feedback document § 5):
--   one of two modules exporting a name called `shared`, so that opening both
--   makes the bare name ambiguous.
module DiagAmbigA where

open import Agda.Builtin.Nat

shared : Nat
shared = zero
