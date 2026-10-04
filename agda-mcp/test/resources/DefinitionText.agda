-- DefinitionText.agda
--
-- File: agda-native-air/agda-mcp/test/resources/DefinitionText.agda
--
-- Description:
--   Fixture for issue #185: definition_of returns what a definition says.
--   Each declaration below is one shape of the layout rule that cuts a
--   declaration's extent (AgdaMCP.Declaration): clauses after a signature,
--   a where block, a mixfix operator defined by infix clauses with a comment
--   between them, a signature that names two things and breaks before its
--   colon, a data type, and a record.  Hole-free, so the lane loads it whole.
module DefinitionText where

open import Agda.Builtin.Nat

double : Nat → Nat
double zero    = zero
double (suc n) = suc (suc (double n))

-- A comment between declarations belongs to neither.
quadruple : Nat → Nat
quadruple n = twice (twice n)
  where
  twice : Nat → Nat
  twice = double

_⊕_ : Nat → Nat → Nat
zero  ⊕ n = n
-- A comment between clauses stays inside the quote.
suc m ⊕ n = suc (m ⊕ n)

_≼_
  _AtMost_ : Nat → Nat → Nat
m AtMost n = m ⊕ n
m ≼ n = n ⊕ m

data Color : Set where
  red green : Color
  blue      : Color

record Pair : Set where
  constructor pair
  field
    first  : Nat
    second : Nat

lastOne : Nat
lastOne = Pair.first (pair (double 1) zero)
