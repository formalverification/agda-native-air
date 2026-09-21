-- Shapes.agda
--
-- File: agda-native-air/agda-mcp/parity/fixtures/Shapes.agda
--
-- Description:
--   Deliberate cases for issue #163's parity measurement: candidate shapes
--   that the two lanes might read differently for reasons of syntax rather
--   than of typechecking.
--
--   Hole 0 takes a function, so an extended lambda is a candidate there, and
--   an extended lambda is the shape most likely to meet the same refusal a
--   `where` clause does: Agda's interaction protocol parses a give as an
--   expression, and the batch lane splices text into a clause's right-hand
--   side.  Hole 1 takes a string, which exercises the escaping chain end to
--   end: a quote and a non-ASCII character have to survive JSON, the IOTCM
--   line's Haskell string literal, and Agda's own lexer, and the batch lane's
--   splice has to agree with all of that.
--
--   Filling either hole leaves the other open, so both lanes should read the
--   tolerated [UnsolvedInteractionMetas] class.  This header deliberately
--   never spells the four-character hole token, so the fixture's hole indices
--   stay stable.
module Shapes where

open import Agda.Builtin.Bool
open import Agda.Builtin.String

negate : Bool → Bool
negate = {!!}

msg : String
msg = {!!}
