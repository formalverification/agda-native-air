-- DiagBarrel.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/DiagBarrel.agda
--
-- Description:
--   Helper for the ModuleDoesntExport fixture (issue #74, feedback document
--   § 5): a barrel module that exports `usable` and, deliberately, nothing
--   called `absentName`.  It typechecks cleanly on its own; the diagnostic
--   belongs to the module that imports a name from here that is not here.
module DiagBarrel where

open import Agda.Builtin.Nat

usable : Nat
usable = zero
