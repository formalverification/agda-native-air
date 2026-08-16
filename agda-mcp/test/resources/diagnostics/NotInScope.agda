-- NotInScope.agda
--
-- File: agda-native-air/agda-mcp/test/resources/diagnostics/NotInScope.agda
--
-- Description:
--   Fixture for issue #74: the [NotInScope] error with suggestions.  The
--   misspelling below is one character from a name that is in scope, so Agda
--   offers its "did you mean" list — the payload the feedback document's § 5
--   asks for ("nearest candidates, and the module that would export it"),
--   which arrives qualified, so the module is in the candidate itself.
module NotInScope where

open import Agda.Builtin.Nat

n : Nat
n = suc zeroo
