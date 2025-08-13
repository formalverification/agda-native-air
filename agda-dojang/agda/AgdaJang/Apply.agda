-- agda/AgdaJang/Apply.agda
-- We don't try to invent metas yet (that's version-sensitive);
-- we just give ergonomic builders for *explicit* applications.
-- We'll extend it to implicit-meta insertion later.
--
-- USAGE
--
--   for fully explicit functions:
--
--     -- inside some module where 'suc' is in scope and args are explicit:
--     example : R.Term → R.Term → Set -- pseudo, illustrative only
--     example = refineApp⟨ mkDefApp (quote suc) (vArg (R.lit (R.nat 0)) ∷ []) ⟩
--
-- We'll make this nicer once we add implicit-meta insertion.
-- For now, think of `Apply.agda` as a staging area for those helpers.

module AgdaJang.Apply where

open import AgdaJang.Compat
open import Agda.Builtin.List using (List; []; _∷_)

-- Build a 'def' application with explicit arguments you provide.
-- Use vArg/hArg/iArg from Compat to tag each argument.
mkDefApp : Name → List (Arg Term) → Term
mkDefApp f args = def f args

-- A refinement macro that takes a fully explicit application term and refines.
-- (Think of this as a small convenience wrapper around 'refine⟨_⟩'.)
macro
  refineApp⟨_⟩ : Term → Term → TC ⊤
  refineApp⟨ app ⟩ hole =
    inferType hole     >>= λ goalTy →
    checkType app goalTy >>= λ _ →
    unify hole app       >>= λ _ →
    unit tt

-- TODO (next pass):
-- - mkDefAppWithImplicits : Name → List Term → TC Term
--     (insert fresh metas for implicits, use 'checkType' to elaborate)
-- - apply⟨_⟩ macro that accepts (quote f) and a list of explicit Term args,
--   builds 'def f [...]' and refines/unifies.
