-- ModuleDoesntExport.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/ModuleDoesntExport.agda
--
-- Description:
--   Fixture for issue #74: the [ModuleDoesntExport] warning, and the
--   [NotInScope] error that follows from it.  This is the pair the feedback
--   document's § 5 error corpus opens with — "new module not yet in its
--   barrel", then "consequence of the above" — and it is the case that pins
--   root-cause ordering: the warning is raised on the import line, the error
--   on the use site below it, and a client reading the diagnostics in order
--   must be shown the cause before the consequence.
--
--   Agda reports both in one run because scope warnings are flushed with the
--   scope error, so this fixture never caches an interface and both
--   diagnostics reappear on every check.
module ModuleDoesntExport where

open import Agda.Builtin.Nat
open import DiagBarrel using (usable; absentName)

n : Nat
n = absentName
