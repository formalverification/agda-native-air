-- AnonModule.agda
--
-- File: agda-native-air/agda-mcp/test/resources/AnonModule.agda
--
-- Description:
--   Regression fixture for the module name get_goal reports (issue #100): a
--   file whose top-level module is anonymous.  Its header declares `_`, so no
--   scan of the source can name it, while Agda resolves it from the file's
--   place on the include path and calls it `AnonModule` — the name an agent
--   would have to import.  get_goal must report Agda's answer, so this fixture
--   is the one that fails if the reported name ever goes back to being read
--   out of the source alone.
module _ where

open import Agda.Builtin.Nat

n : Nat
n = {! zero !}
