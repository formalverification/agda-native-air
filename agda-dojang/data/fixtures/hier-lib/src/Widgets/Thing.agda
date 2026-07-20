-- Thing.agda
--
-- File: agda-dojang/data/fixtures/hier-lib/src/Widgets/Thing.agda
--
-- Description:
--   A trivial module in the `hier-lib` regression fixture, living under a
--   top-level directory (`Widgets/`) distinct from the module that imports it
--   (`Proofs.Use`).  Its only job is to be a cross-directory dependency, so that
--   type-checking `Proofs.Use` exercises hierarchical include-path resolution.
--   See issue #66 and agda-mcp/test/Main.hs.
module Widgets.Thing where

open import Agda.Builtin.Nat

thing : Nat
thing = 7
