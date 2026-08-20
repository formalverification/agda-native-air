-- ReexportBarrel.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ReexportBarrel.agda
--
-- Description:
--   Fixture for issue #75's definition_of acceptance moment: the barrel
--   module, which re-exports everything ReexportOrigin defines without
--   defining anything itself, which is the shape grep cannot see through.
module ReexportBarrel where

open import ReexportOrigin public
