-- ClashingDefinition.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/ClashingDefinition.agda
--
-- Description:
--   Fixture for issue #74: the [ClashingDefinition] error.  The record field
--   below is re-exported into this module by `open Bound public`, and the
--   definition after it reuses that name — the feedback document's § 5 row
--   "local name colliding with a re-exported record field", which cost the
--   field session a full iteration.  The payload § 5 asks for is the origin
--   of the pre-existing definition, which Agda prints as a location and the
--   diagnostic carries in `involved.candidates`.  (The colliding name is
--   deliberately not spelled in this header: the test locates both the clash
--   and its origin by searching the fixture for that name.)
module ClashingDefinition where

open import Agda.Builtin.Nat

record Bound : Set where
  field least : Nat

open Bound public

least : Nat
least = zero
