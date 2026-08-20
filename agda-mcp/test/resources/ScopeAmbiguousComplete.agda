-- ScopeAmbiguousComplete.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ScopeAmbiguousComplete.agda
--
-- Description:
--   The hole-free twin of ScopeAmbiguous.agda, for issue #75's recovery
--   path.  With no interaction point, the module completes on load and its
--   toplevel scope no longer carries the names the two opens brought in
--   (docs/agda-mcp-interaction-lane.md § 2.6), so a WhyInScope on `amb`
--   answers "not in scope" and resolve_name must recover through Agda's
--   own did-you-mean suggestions — re-resolving each suggested qualified
--   spelling for its full provenance chain, which the completed scope
--   still answers.  ScopeAmbiguous (with its hole) pins the first-class
--   path; this fixture pins the recovered one.
module ScopeAmbiguousComplete where

open import Agda.Builtin.Nat

module Source1 where
  amb : Nat
  amb = zero

module Source2 where
  amb : Nat
  amb = suc zero

open Source1
open Source2

settled : Nat
settled = zero
