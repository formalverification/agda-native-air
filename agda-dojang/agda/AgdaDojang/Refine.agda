-- Refine.agda
--
-- File: agda-dojang/agda/AgdaDojang/Refine.agda
--
-- Description:
--   This module defines two macros, `refine⟨_⟩` and `try⟨_⟩`, that can be used in
--   Agda holes to attempt to fill the hole with a candidate term (`cand`).
--
--   +  `refine⟨_⟩` checks if `cand` typechecks against the goal type and, if so, fills the
--      hole with `cand`. If it doesn't typecheck, it raises a type error.
--
--   +  `try⟨_⟩` performs the same check but does not fill the hole; instead, it uses
--      `catchTC` to signal whether the check succeeded or failed via compile-time
--      messages.  This can be useful for testing candidate terms without committing to them.
--
-- Notes:
--
--   +  `refine⟨_⟩` is the fast, reliable building block. If Agda accepts the candidate
--       term, it unifies the hole.
--
--   +  `try⟨_⟩` uses `catchTC` to signal OK/FAIL without committing the solution.
--      For v0 we use a `typeError` message as a signaling channel; the CLI looks
--      for `AGDADOJO_TRY:OK`/`FAIL` in Agda's JSON.
--
--  Usage:
--
--    In a hole, write `refine⟨ cand ⟩` where `cand` is a term (with implicits
--    explicit or implicit as usual).  If it typechecks, the goal gets solved;
--    otherwise, Agda prints a type error.
--
--    In a hole, write `try⟨ cand ⟩` to check if `cand` would typecheck against the
--    goal type. This does not solve the hole; instead, it reports the result via
--    compile-time messages.
--
{-# OPTIONS --safe --cubical-compatible #-}

module AgdaDojang.Refine where

open import AgdaDojang.Prelude
open import Agda.Builtin.Unit using (⊤; tt)
open import Agda.Builtin.List using (List; []; _∷_)

-- v0: a tiny "refine" macro. If `cand` checks against the goal type, fill the goal
-- with `cand`.
--
-- Usage: in a hole, write  `refine⟨ cand ⟩`  where `cand` is a term (with implicits
-- explicit or implicit as usual).  If it typechecks, the goal gets solved; otherwise
-- Agda prints a type error.

macro
  refine⟨_⟩ : Term → Term → TC ⊤
  refine⟨ cand ⟩ hole = do
    goalTy ← inferType hole               -- type of the current goal
    _      ← checkType cand goalTy        -- ensure cand : goalTy
    unify hole cand                       -- solve the hole by cand
    unit tt

-- v0: a "try" macro that *doesn't* solve the goal, only reports whether cand would
-- typecheck.
--
-- We encode the boolean result as a compile-time message + a dummy success on tt.
-- (Useful in the CLI: we call it in a scratch goal and parse the message.)

macro
  try⟨_⟩ : Term → Term → TC ⊤
  try⟨ cand ⟩ hole =
    catchTC {A = ⊤}
      ( inferType hole       >>= λ goalTy →
        checkType cand goalTy >>= λ _ →
        typeError (strErr "AGDADOJANG_TRY:OK" ∷ []) )
      ( typeError (strErr "AGDADOJANG_TRY:FAIL" ∷ []))

-- Notes.
-- `catchTC` has type: `∀ {A} → TC A → (Error → TC A) → TC A`
-- In a previous version, Agda wasn’t inferring `{A = ⊤}` in our handler, so it tried
-- to make `A` depend on the handler's argument, which breaks the type.

-- Helpers we'll likely want next (stubs for v1):
-- - build application terms with fresh metas for implicits
-- - "apply" a Name (lemma) to create subgoals
-- - normalize/whnf for goal types before checking
