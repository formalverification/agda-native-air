-- ScopeSearch.agda
--
-- File: agda-native-air/agda-mcp/test/resources/ScopeSearch.agda
--
-- Description:
--   The queried file of the search_in_scope fixture (issue #17): narrow
--   imports on purpose.  `open import ScopeSearchLib using (twice)` opens one
--   name bare and grants the rest of the module qualified; `import
--   ScopeSearchBarrel` (not opened) grants the barrel qualified only, so its
--   re-exported `quad` can be named as `ScopeSearchBarrel.quad` and no other
--   way.  The hole is load-bearing twice over: it keeps a goal for the
--   goal-scoped validation and the goal-derived query, and its type
--   `twice n ≡ n + n` normalizes to a display whose tokens (`+`, `≡`) meet
--   exactly one corpus row.
module ScopeSearch where

open import Agda.Builtin.Nat
open import Agda.Builtin.Equality
open import ScopeSearchLib using (twice)
import ScopeSearchBarrel

probe : (n : Nat) → twice n ≡ n + n
probe n = {!!}

-- Two more holes pin the identity check (PR #161 review): in `shadow`, a
-- pattern variable named like the using-listed import means the bare
-- spelling `twice` types but denotes the local, so the row must render
-- qualified; in `idish`, the goal is only a context variable and its
-- display yields no retrieval tokens, so a call with no query there must
-- answer in band rather than search the whole corpus.
shadow : Nat → Nat
shadow twice = {!!}

idish : (A : Set) → A → A
idish A x = {!!}
