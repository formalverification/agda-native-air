-- ScopeAmbiguous.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ScopeAmbiguous.agda
--
-- Description:
--   Fixture for issue #75's resolve_name acceptance moment: `amb` is in
--   scope twice — once from each of two opened modules — so a resolution
--   query must report two candidates, each with its own provenance chain.
--   Mirrors the field session's ≈sym ambiguity (a Setoid record field
--   versus a lemma reached through module applications).  The file itself
--   never uses `amb` after the opens, so it loads clean; only the query
--   is ambiguous.
--
--   The trailing hole is load-bearing: a file with no interaction points
--   is completed on load, and its completed top-level scope no longer
--   carries names brought in by opening file-local modules (probed under
--   Agda 2.8.0 — see docs/agda-mcp-interaction-lane.md).  The open goal
--   keeps the inside scope live, which is also the field shape: the ≈sym
--   ambiguity was met mid-proof, holes open.
module ScopeAmbiguous where

open import Agda.Builtin.Nat

module Source1 where
  amb : Nat
  amb = zero

module Source2 where
  amb : Nat
  amb = suc zero

open Source1
open Source2

probe : Nat
probe = {!!}
