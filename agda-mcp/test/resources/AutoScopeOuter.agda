-- AutoScopeOuter.agda
--
-- File: agda-native-air/agda-mcp/test/resources/AutoScopeOuter.agda
--
-- Description:
--   Re-exports AutoScopeInner's record under another name and nothing else
--   (issue #205): the type reaches an importer, the module that defines its
--   field does not.
module AutoScopeOuter where

import AutoScopeInner

Wrapped : Set
Wrapped = AutoScopeInner.Cell
