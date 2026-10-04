-- AutoScopeInner.agda
--
-- File: agda-native-air/agda-mcp/test/resources/AutoScopeInner.agda
--
-- Description:
--   The record whose field the auto fixture cannot name (issue #205).  Only
--   AutoScopeOuter imports this module, so a file that imports AutoScopeOuter
--   alone can hold a Cell but cannot write its field, and a term Agda's proof
--   search builds from the field is printed with a name that file cannot read.
module AutoScopeInner where

open import Agda.Builtin.Nat

record Cell : Set where
  field
    contents : Nat
