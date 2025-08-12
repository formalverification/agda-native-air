-- agda/AgdaJang/Refine.agda
--
-- **Notes**
--
-- + `refine⟨_⟩` is the fast, reliable building block. If Agda accepts the candidate
--    term, it unifies the hole.
--
-- +  `try⟨_⟩` uses `catchTC` to signal OK/FAIL without committing the solution.
--    For v0 we use a `typeError` message as a signaling channel; the CLI looks
--    for `AGDADOJO_TRY:OK`/`FAIL` in Agda's JSON.

module AgdaJang.Refine where

open import AgdaJang.Compat              -- <<—— use our shim
-- open import Agda.Primitive using (Level; lzero; lsuc)
open import Agda.Builtin.Unit using (⊤; tt)
open import Agda.Builtin.List using (List; []; _∷_)
-- open import Agda.Builtin.Reflection

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
    return tt

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
        typeError (strErr "AGDAJANG_TRY:OK" ∷ []) )
      ( typeError (strErr "AGDAJANG_TRY:FAIL" ∷ []))
-- macro
--   try⟨_⟩ : Term → Term → TC ⊤
--   try⟨ cand ⟩ hole =
--     catchTC {A = ⊤}
--       (do goalTy ← inferType hole
--           _      ← checkType cand goalTy
--           typeError (strErr "AGDAJANG_TRY:OK" ∷ []))
--       (λ _ → typeError (strErr "AGDAJANG_TRY:FAIL" ∷ []))

-- Notes.
-- `catchTC` has type: `∀ {A} → TC A → (Error → TC A) → TC A`
-- In a previous version, Agda wasn’t inferring `{A = ⊤}` in our handler, so it tried
-- to make `A` depend on the handler's argument, which breaks the type.

-- Helpers we'll likely want next (stubs for v1):
-- - build application terms with fresh metas for implicits
-- - "apply" a Name (lemma) to create subgoals
-- - normalize/whnf for goal types before checking
