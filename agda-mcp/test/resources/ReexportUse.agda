-- ReexportUse.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ReexportUse.agda
--
-- Description:
--   Fixture for issue #75's definition_of acceptance moment: sees
--   `originalName` only through ReexportBarrel, so `grep originalName`
--   in this file's imports finds the barrel, not the definition; the
--   type-checker knows better.
module ReexportUse where

open import Agda.Builtin.Nat
open import ReexportBarrel

useIt : Nat
useIt = originalName
