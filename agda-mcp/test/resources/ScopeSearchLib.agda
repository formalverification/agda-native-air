-- ScopeSearchLib.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ScopeSearchLib.agda
--
-- Description:
--   The library half of the search_in_scope fixture (issue #17).  Its rows in
--   corpus-fixture.jsonl exercise each rung of the rendering ladder from a
--   file that imports it narrowly (ScopeSearch.agda: `using (twice)`):
--   `twice` is using-listed and renders bare; `twice-def` is not, and renders
--   qualified through the import that still grants qualified access to all of
--   the module; `Inner.thrice` and `Box.unbox` live in nested modules, which
--   the scope rule reaches at a dot boundary, and render qualified; and the
--   corpus additionally rows a `ghost` this file never defines, so the lane
--   rejects every rendering of it and the ledger names the rejection.
module ScopeSearchLib where

open import Agda.Builtin.Nat
open import Agda.Builtin.Equality

twice : Nat → Nat
twice n = n + n

twice-def : (n : Nat) → twice n ≡ n + n
twice-def n = refl

record Box : Set where
  field
    unbox : Nat

module Inner where
  thrice : Nat → Nat
  thrice n = n + n + n
