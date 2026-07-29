-- TwoHoles.agda
--
-- File: agda-native-air/agda-mcp/test/resources/TwoHoles.agda
--
-- Description:
--   Regression fixture for issue #69 (the fill_hole verdict).  Hole 0 (in g)
--   is the fill target; hole 1 (in h) stays open, so every fill of hole 0
--   also reports the open hole's [UnsolvedInteractionMetas].  The function
--   implicitOnly has an implicit argument that nothing constrains, so filling
--   hole 0 with `implicitOnly` typechecks the clause but leaves an unsolved
--   meta behind — fill_hole must report that candidate as a type error, not
--   ok.  (This header deliberately never spells the four-character hole
--   token, so the fixture's hole indices stay stable.)
module TwoHoles where

open import Agda.Builtin.Nat

implicitOnly : {n : Nat} → Nat
implicitOnly {n} = n

g : Nat
g = {!!}

h : Nat
h = {!!}
