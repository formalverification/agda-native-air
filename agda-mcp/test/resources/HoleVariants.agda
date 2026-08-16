-- HoleVariants.agda
--
-- File: agda-native-air/agda-mcp/test/resources/HoleVariants.agda
--
-- Description:
--   Regression fixture for issue #71 (the hole model).  Agda sees exactly
--   four interaction points here — one per hole syntax: {!!}, {! !},
--   {!zero!}, and a standalone ?.  Around them sit decoys that must
--   contribute zero holes: hole tokens in this header comment ({!!} and
--   {! zero !} and a lone ? ), in the block comment below, in a string
--   literal, and names in which ? is not a separate token (is-zero?, and
--   the backslash-named \? — backslash is a name character in Agda's
--   lexer, so the ? it carries is part of the identifier).  The comment
--   decoys deliberately precede the first real hole, so an index-addressed
--   tool call that miscounts them targets the wrong span.
module HoleVariants where

open import Agda.Builtin.Nat
open import Agda.Builtin.String

{- block-comment decoys: {!!} and {! nested {! !} !} and a lone ?
   {- nested comment: {!!} -} still inside the outer comment -}

is-zero? : Nat → Nat
is-zero? zero    = 1
is-zero? (suc n) = 0

decoyString : String
decoyString = "not holes: {!!} {! x !} ? --"

\? : Nat → Nat
\? n = n

e : Nat
e = \? 1

a : Nat
a = {!!}

b : Nat
b = {! !}

c : Nat
c = {!zero!}

d : Nat
d = ?
