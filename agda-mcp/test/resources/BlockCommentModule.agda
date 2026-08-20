-- BlockCommentModule.agda
--
-- File: agda-native-air/agda-mcp/test/resources/BlockCommentModule.agda
--
-- Description:
--   Regression fixture for the plain-Agda half of issue #100: a .agda file
--   whose block comment contains a commented-out `module … where` line above
--   the real header.  A scan of the raw source calls this module `Decoy`; the
--   code-only scan (AgdaMCP.Holes.codeOnly) calls it `BlockCommentModule`,
--   which is the name Agda gives it.
--
--   The commented-out draft carries the same decoy hole and a nested block
--   comment, so the file also pins that a block comment hides both from the
--   hole scan: it has exactly one hole, the `n = {! zero !}` of HolePlain.agda
--   and of the literate fixtures.

{- An earlier draft of this module, kept as a comment:

module Decoy where

  open import Agda.Builtin.Nat

  n : Nat
  n = {! zero !}

  {- with a nested comment, which Agda's block comments allow -}
-}

module BlockCommentModule where

open import Agda.Builtin.Nat

n : Nat
n = {! zero !}
