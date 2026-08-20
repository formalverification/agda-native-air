-- ExportSurfaces.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ExportSurfaces.agda
--
-- Description:
--   Fixture for exports_of's two member kinds (issue #75, Copilot round 2):
--   a module's surface is value members (the wire's `contents`) PLUS
--   exported nested modules (the wire's `names`) — `Inner.Nested` appears
--   only in the latter, so a reader of `contents` alone under-reports the
--   surface.  `Param` pins that a parameterized module's member types
--   arrive with the binders folded in (`ret : (A : Set) (base : A) → A`)
--   while the wire's `telescope` stays empty under the pinned 2.8.0.
module ExportSurfaces where

open import Agda.Builtin.Nat

module Inner where
  val : Nat
  val = zero
  module Nested where
    deep : Nat
    deep = zero

module Param (A : Set) (base : A) where
  ret : A
  ret = base

use : Nat
use = Inner.val
