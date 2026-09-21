-- LaterUse.agda
--
-- File: agda-native-air/agda-mcp/parity/fixtures/LaterUse.agda
--
-- Description:
--   A deliberate case for issue #163's parity measurement: a hole whose
--   correctness is decided by a definition that comes AFTER it.
--
--   The two lanes check this file in different orders, and that is the point.
--   Batch agda splices the candidate in and typechecks the whole module from
--   the top, so `later` is checked against the candidate's value.  The
--   interaction lane has already checked the module once, with `n` standing
--   for an interaction meta, so `later = refl` left a constraint blocked on
--   that meta; a `Cmd_give` instantiates the meta and the solver then has to
--   discharge the constraint.  If the two orders can disagree anywhere, a
--   file shaped like this is where.
--
--   `n = 1` is the one value that makes the module typecheck.  This header
--   deliberately never spells the four-character hole token, so the fixture's
--   hole index stays stable.
module LaterUse where

open import Agda.Builtin.Nat
open import Agda.Builtin.Equality

n : Nat
n = {!!}

later : n ≡ 1
later = refl
