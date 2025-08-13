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
-- ```
--
-- (We'll refine this to accept explicit arguments later: e.g., `apply⟨ (quote _+_) ⟩` and give one or both operands, leaving metas for the rest.)


-- We'll make this nicer once we add implicit-meta insertion.
-- For now, think of `Apply.agda` as a staging area for those helpers.


module AgdaJang.Apply where

open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat  using (Nat; zero; suc; _+_)
open import AgdaJang.Compat
open import Agda.Builtin.Reflection
  using ( pi; abs; arg; unknown; def; Name; Arg; Term )

------------------------------------------------------------------------
-- Convenience: refine any surface term against the current goal.
------------------------------------------------------------------------
-- `refineApp⟨_⟩` is a refinement macro that takes a fully explicit application term
-- and refines. Think of it as a small convenience wrapper around 'refine⟨_⟩'.
macro
  refineApp⟨_⟩ : Term → Term → TC ⊤
  refineApp⟨ app ⟩ hole =
    inferType hole       >>= λ goalTy →
    checkType app goalTy >>= λ _ →
    unify hole app       >>= λ _ →
    unit tt

------------------------------------------------------------------------
-- Termination-friendly Π-binder collection
------------------------------------------------------------------------

-- A quick *syntactic* bound on the number of Π-binders (no normalization).
piDepth : Term → Nat
piDepth (pi (arg _ _) (abs _ b)) = suc (piDepth b)
piDepth _                        = zero

-- Worker that peels Π-binders up to 'fuel' steps, normalizing each step.
go : Nat → Term → TC (List (Arg Term))
go zero    _  = unit []
go (suc n) ty =
  whnf ty >>= λ t →
  peel n t
  where
    peel : Nat → Term → TC (List (Arg Term))
    peel n (pi (arg i _) (abs _ b)) =
      go n b >>= λ rest →
      unit (arg i unknown ∷ rest)
    peel _ _ = unit []

-- Public function: collect one 'Arg Term' per Π-binder, preserving ArgInfo
-- and replacing each argument with 'unknown' so Agda generates metas.
collectUnknownArgs : Term → TC (List (Arg Term))
collectUnknownArgs ty =
  let fuel = piDepth ty + 32  -- small safety margin
  in go fuel ty

-- ## Why this passes termination
--
--    +  `piDepth` is obviously structural (`b` is a direct subterm of `pi … (abs _ b)`).
--    +  `collectUnknownArgs` calls `go fuel ty` with `fuel = piDepth ty + 32`.
--    +  `go` strictly decreases `fuel` on each recursive call (`go n b`) or stops, so
--       the checker is happy, regardless of what `whnf` does.

------------------------------------------------------------------------
-- Tactic: apply⟨ f ⟩
------------------------------------------------------------------------

-- Build (def f [unknown,…,unknown]) from the Π-shape of f's type,
-- check against the goal, and unify. Leaves metas/subgoals for args
-- Agda cannot infer or that remain unspecified.
macro
  apply⟨_⟩ : Name → Term → TC ⊤
  apply⟨ f ⟩ hole =
    inferType (def f [])   >>= λ fty  →
    collectUnknownArgs fty >>= λ args →
    let app = def f args in
    inferType hole         >>= λ goal →
    checkType app goal     >>= λ _ →
    unify hole app         >>= λ _ →
    unit tt
