-- ReexportOrigin.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ReexportOrigin.agda
--
-- Description:
--   Fixture for issue #75's definition_of acceptance moment: the module
--   that actually defines `originalName`.  ReexportBarrel re-exports it,
--   and ReexportUse sees it only through that barrel, so a definition
--   query must chase the chain back to this file and line.
module ReexportOrigin where

open import Agda.Builtin.Nat

originalName : Nat
originalName = zero
