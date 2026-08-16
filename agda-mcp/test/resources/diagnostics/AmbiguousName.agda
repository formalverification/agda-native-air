-- AmbiguousName.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/AmbiguousName.agda
--
-- Description:
--   Fixture for issue #74: the [AmbiguousName] error.  Two `open import`s
--   bring the same name into scope, so the bare use below resolves to
--   neither.  This is the feedback document's § 5 row that cost the field
--   session a full iteration on `≈sym`; the payload it asks for is the
--   candidate list with qualified names, which is what the diagnostic's
--   `involved.candidates` carries.
module AmbiguousName where

open import Agda.Builtin.Nat
open import DiagAmbigA
open import DiagAmbigB

n : Nat
n = shared
