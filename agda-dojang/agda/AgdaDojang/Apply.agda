-- Apply.agda
--
-- File: agda-dojang/agda/AgdaDojang/Apply.agda
--
-- Description:
--   This file contains tactics for applying functions to goals, with various levels
--   of user-supplied information and reporting.  The main challenges are:
--
--   +  Building an application term with the right head (def or con) and the right
--      number of args.
--   +  Collecting the number of Π-binders from a function's type to know how
--      many args to build, without risking non-termination from normalization.
--
--   We solve the first by a helper that takes a *term* (e.g., `suc` or `_+_`) and
--   builds a head application with the right head constructor.
--
--   We solve the second by a syntactic bound on the number of Π-binders, plus a
--   worker that peels normalization one step at a time, so the termination checker
--   is happy.
--
--   We don't try to invent metas yet (that's version-sensitive);
--   we just give ergonomic builders for *explicit* applications.
--   We'll extend it to implicit-meta insertion later.
--
-- Usage:
--
--   Example 1. Fully explicit functions
--     Inside some module where 'suc' is in scope and args are explicit:
--     _ : Term → Term → Set -- pseudo, illustrative only
--     _ = refineApp⟨ mkDefApp (quote suc) (vArg (R.lit (R.nat 0)) ∷ []) ⟩
--
--   Example 2. Fill first binder with zero; leave subgoal for second operand.
--     _ : Nat
--     _ = applyWith⟨ _+_ , zero ⟩
--
-- We'll make this nicer once we add implicit-meta insertion.
-- For now, `Apply.agda` is a staging area for those helpers.
{-# OPTIONS --safe --cubical-compatible #-}

module AgdaDojang.Apply where

open import AgdaDojang.Prelude
open import Data.List.Base
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

------------------------------------------------------------------------
-- Termination-friendly Π-binder collection
------------------------------------------------------------------------
-- A quick *syntactic* bound on the number of Π-binders (no normalization).
piDepth : Term → Nat
piDepth (pi (arg _ _) (abs _ b)) = suc (piDepth b)
piDepth _                        = zero

FUEL : Nat
FUEL = 32

-- Worker that peels Π-binders up to `FUEL` steps, normalizing each step.
peel : Nat → Term → TC (List (Arg Term))
peel zero    _  = unit []
peel (suc n) ty =
  whnf ty >>= λ t →
  case t of λ where
    (pi (arg i _) (abs _ b)) →
      peel n b >>= λ rest → unit (arg i unknown ∷ rest)
    _ → unit []

-- Public function: collect one 'Arg Term' per Π-binder, preserving ArgInfo
-- and replacing each argument with 'unknown' so Agda generates metas.
collectUnknownArgs : Term → TC (List (Arg Term))
collectUnknownArgs t = peel (piDepth t + FUEL) t


-- ## Why this passes termination
--
-- +  `piDepth` is obviously structural (`b` is a direct subterm of `pi … (abs _ b)`).
-- +  `collectUnknownArgs` calls `peel (piDepth ty + FUEL)`.
-- +  `peel` strictly decreases `FUEL` on each recursive call (`peel n b`) or stops, so
--    the checker is happy, regardless of what `whnf` does.

peel' : Nat → Term → TC (List (Arg Term))
peel' zero    _  = unit []
peel' (suc n) t0 =
  whnf t0 >>= λ t →
  case t of λ where
    (pi (arg i A) (abs _ b)) →
      peel' n b >>= λ rest → unit (arg i A ∷ rest)
    _ → unit []

-- Collect Π-binders as Arg Type (preserve ArgInfo + domain types)
collectBinderTypes : Term → TC (List (Arg Term))
collectBinderTypes ty = peel' (piDepth ty + FUEL) ty
------------------------------------------------------------------------


------------------------------------------------------------------------
-- Head resolution helpers: pick def/con from a *term* (no 'quote' needed)
------------------------------------------------------------------------
-- Build a zero-argument head term to query its type.
headZero : Term → TC Term
headZero fTerm =
  whnf fTerm >>= λ t′ →
  case t′ of λ where
    (def f _) → unit (def f [])
    (con c _) → unit (con c [])
    _ → typeError
          ( strErr "AGDADOJANG_APPLY: expected a bare name (e.g., suc, _+_, proj₁)"
          ∷ termErr t′ ∷ [] )

-- Build an application with the right head (def or con).
headApp : Term → List (Arg Term) → TC Term
headApp fTerm args =
  whnf fTerm >>= λ t′ →
  case t′ of λ where
    (def f _) → unit (def f args)
    (con c _) → unit (con c args)
    _ → typeError
          ( strErr "AGDADOJANG_APPLY: expected a bare name (e.g., suc, _+_, proj₁)"
          ∷ termErr t′ ∷ [] )
------------------------------------------------------------------------


--------------------------------------------------------------------------
-- Tactic: apply⟨ f ⟩ where f is a *term*, e.g. apply⟨ suc ⟩, apply⟨ _+_ ⟩
--------------------------------------------------------------------------
-- Build (def f [unknown,…,unknown]) from the Π-shape of f's type,
-- check against the goal, and unify. Leaves metas/subgoals for args
-- Agda cannot infer or that remain unspecified.
macro
  apply⟨_⟩ : Term → Term → TC ⊤
  apply⟨ fTerm ⟩ hole =
    headZero fTerm        >>= λ f0    →   -- def f []  or  con c []
    inferType f0          >>= λ fty   →
    collectUnknownArgs fty >>= λ args →
    headApp fTerm args    >>= λ app   →
    inferType hole        >>= λ goal  →
    checkType app goal    >>= λ _     →
    unify hole app        >>= λ _     →
    unit tt
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Tactic: report subgoals for applying f (no solving)
------------------------------------------------------------------------
-- Print stable, parseable lines describing expected binders
-- Lines look like:
--   AGDADOJANG_GOAL:0:visible:  <TYPE_TERM_RENDERED>
--   AGDADOJANG_GOAL:1:hidden:   <TYPE_TERM_RENDERED>
--
-- Notes:
-- +  We include the domain type of each binder (`A`), and whether it's
--    `visible/hidden/instance`.
-- +  We wrap the list with `AGDADOJANG_SUBGOALS_BEGIN` / `..._END` markers
--    so the parser can be simple and robust.
-- +  This macro does NOT attempt to solve; it only reports (so it will
--    exit non-zero; our runner should expect that when using report mode).

-- Convert Visibility to a short string
visTag : Visibility → String
visTag visible   = "visible"
visTag hidden    = "hidden"
visTag instance′ = "instance"

build_parts : Nat → List (Arg Term) → List ErrorPart
build_parts _ [] = strErr "AGDADOJANG_SUBGOALS_END" ∷ []
build_parts n (arg (arg-info v _) A ∷ rest) =
  ( strErr "AGDADOJANG_GOAL:"
  ∷ strErr (primShowNat n)
  ∷ strErr ":"
  ∷ strErr (visTag v)
  ∷ strErr ": "
  ∷ termErr A
  ∷ strErr "\n"
  ∷ build_parts (suc n) rest )

get_subgoals : List (Arg Term) → List ErrorPart
get_subgoals bs = strErr "AGDADOJANG_SUBGOALS_BEGIN\n" ∷ build_parts 0 bs

macro
  applyReport⟨_⟩ : Term → Term → TC ⊤
  applyReport⟨ fTerm ⟩ hole =
    headZero fTerm         >>= λ f0   →
    inferType f0           >>= λ fty  →
    collectBinderTypes fty >>= λ bs   → typeError (get_subgoals bs)
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Tactic: applyWith⟨ f , [t₁ , … , tₖ] ⟩
-- Fill the first k *visible* binders with the given terms.
------------------------------------------------------------------------
-- Pure helper: consume explicit terms across a binder spine
-- Visible binders consume an argument from the list; hidden/instance do not.
fillVisible : List Term → List (Arg Term) → List (Arg Term)
fillVisible []         slots                           = slots
fillVisible ts         []                              = []
fillVisible (t ∷ ts)   (arg (arg-info visible   m) _ ∷ rest) =
  arg (arg-info visible   m) t       ∷ fillVisible ts rest
fillVisible ts         (arg (arg-info hidden    m) _ ∷ rest) =
  arg (arg-info hidden    m) unknown ∷ fillVisible ts rest
fillVisible ts         (arg (arg-info instance′ m) _ ∷ rest) =
  arg (arg-info instance′ m) unknown ∷ fillVisible ts rest

macro
  -- applyWith⟨_,_⟩: explicit args for visible binders
  --   This fills the first k visible binder with the user's terms, leaves
  --   `unknown` for the rest, and preserves hidden/instance binders as `unknown`.
  --   This matches how humans use "apply": supply some explicit arguments and
  --   let implicits stay metas.
  applyWith⟨_,_⟩ : Term → List Term → Term → TC ⊤
  applyWith⟨ fTerm , vs ⟩ hole =
    headZero fTerm          >>= λ f0     →
    inferType f0            >>= λ fty    →
    collectUnknownArgs fty  >>= λ slots  →
    let args = fillVisible vs slots in
    headApp fTerm args      >>= λ app    →
    inferType hole          >>= λ goal   →
    checkType app goal      >>= λ _      →
    unify hole app          >>= λ _      →
    unit tt
------------------------------------------------------------------------


------------------------------------------------------------------------
-- Tactic: applyWith⟨ f , t ⟩
-- Fill the first *visible* binder with the given term.
------------------------------------------------------------------------
-- Fill the *first* visible binder with v1; metas for the rest.
fillFirstVisible : Term → List (Arg Term) → List (Arg Term)
fillFirstVisible v [] = []
fillFirstVisible v (arg (arg-info visible   m) _ ∷ rest) =
  arg (arg-info visible   m) v       ∷ rest
fillFirstVisible v (arg (arg-info hidden    m) _ ∷ rest) =
  arg (arg-info hidden    m) unknown ∷ fillFirstVisible v rest
fillFirstVisible v (arg (arg-info instance′ m) _ ∷ rest) =
  arg (arg-info instance′ m) unknown ∷ fillFirstVisible v rest

macro
  -- applyWith1⟨_,_⟩: explicit args for visible binders
  --   This fills the first visible binder with the user's term, leaves
  --   `unknown` for the rest, and preserves hidden/instance binders as `unknown`.
  --   This matches how humans use "apply": supply some explicit arguments and
  --   let implicits stay metas.
  applyWith1⟨_,_⟩ : Term → Term → Term → TC ⊤
  applyWith1⟨ fTerm , v1 ⟩ hole =
    headZero fTerm         >>= λ f0    →
    inferType f0           >>= λ fty   →
    collectUnknownArgs fty >>= λ slots →
    let args = fillFirstVisible v1 slots in
    headApp fTerm args     >>= λ app   →
    inferType hole         >>= λ goal  →
    checkType app goal     >>= λ _     →
    unify hole app         >>= λ _     →
    unit tt
------------------------------------------------------------------------


------------------------------------------------------------------------
-- Tactic: applySolveReport⟨ f ⟩
-- Apply f against the current goal (so unification runs), then print the
-- instantiated types of any remaining meta arguments as AGDADOJANG_GOAL lines.
------------------------------------------------------------------------
macro
  applySolveReport⟨_⟩ : Term → Term → TC ⊤
  applySolveReport⟨ fTerm ⟩ hole =
    headZero fTerm          >>= λ f0   →
    inferType f0            >>= λ fty  →
    collectUnknownArgs fty  >>= λ slots →
    headApp fTerm slots     >>= λ app  →
    inferType hole          >>= λ goal →
    checkType app goal      >>= λ app′ →
    unify hole app′         >>= λ _    →
    -- post-unification reporting (instantiated metas)
    -- build the lines, then emit once
    mkParts 0 (gather app′) >>= λ parts →
    emit (strErr "AGDADOJANG_SUBGOALS_BEGIN\n" ∷ parts)

    where
    -- Force typeError to a concrete result type (`TC ⊤`)
    emit : List ErrorPart → TC ⊤
    emit es = typeError {A = ⊤} es

    -- Gather arguments from a head application (no polymorphic map)
    gatherArgs : List (Arg Term) → List Term
    gatherArgs []                = []
    gatherArgs (arg _ t ∷ rest)  = t ∷ gatherArgs rest

    gather : Term → List Term
    gather (def _ args) = gatherArgs args
    gather (con _ args) = gatherArgs args
    gather _            = []

    -- Build tagged lines; avoid (++) and just cons the 5 parts in front of the tail
    mkParts : Nat → List Term → TC (List ErrorPart)
    mkParts _ []       = unit (strErr "AGDADOJANG_SUBGOALS_END" ∷ [])
    mkParts i (t ∷ ts) =
      inferType t >>= λ A →
      mkParts (suc i) ts >>= λ tail →
      unit (  strErr "AGDADOJANG_GOAL:" ∷ strErr (primShowNat i)
            ∷ strErr ":?arg: "        ∷ termErr A
            ∷ strErr "\n"             ∷ tail )

-- Notes:
-- `applySolveReport` uses the *elaborated* application `app′` from `checkType` so
-- metas are real; we infer each arg's type to print post-unification obligations.
-- The visibility tag is `?arg` here (we can improve by threading `ArgInfo` alongside).
------------------------------------------------------------------------


------------------------------------------------------------------------
-- Tactic: intro
-- If the goal is a Π/→, introduce a λ-abstraction and leave the codomain.
-- No argument; use a default binder name.
------------------------------------------------------------------------
open Term using (lam)
macro
  intro : Term → TC ⊤
  intro hole =
    inferType hole >>= λ ty →
    whnf ty        >>= λ t  →
    case t of λ where
      (pi (arg (arg-info v m) A) (abs s B)) →
        let nm   = if s == "" then "x" else s
            body = abs nm unknown
            lamT = lam v body
        in checkType lamT ty >>= λ lam′ → unify hole lam′
      _ → typeError (strErr "AGDADOJANG_INTRO: goal is not a function/Π-type" ∷ [])

-- Notes:
-- `intro` is nullary for ergonomics: write simply `intro` in a goal to lambda-intro.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Multi-intros: intro₂ and intros⟨ n ⟩ via a TC-worker (no nested macro calls)
--  * `intro₂` introduces exactly two λs (or errors if there aren’t two Πs).
--  * `intros⟨ n ⟩` builds n nested λs, preserving binder visibility/names.
--     If there are fewer than n Π-binders, we error with a clear message.
------------------------------------------------------------------------
-- Build n nested lambdas from a Π-type spine; innermost body is `unknown`.
mkNLams : Nat → Term → TC Term
mkNLams zero    ty = unit unknown
mkNLams (suc n) ty =
  whnf ty >>= λ t →
  case t of λ where
    (pi (arg (arg-info v m) A) (abs s B)) →
      mkNLams n B >>= λ bod →
      let nm = if s == "" then "x" else s in
      unit (lam v (abs nm bod))
    _ → typeError (strErr "AGDADOJANG_INTROS: not enough Π-binders in goal type" ∷ [])

-- Plain TC worker to avoid nested macro expansion (which can cause de Bruijn issues).
introsWorker : Nat → Term → TC ⊤
introsWorker n hole =
  inferType hole >>= λ ty →
  mkNLams n ty  >>= λ lamT →
  checkType lamT ty >>= λ lam′ →
  unify hole lam′

macro
  intros⟨_⟩ : Nat → Term → TC ⊤
  intros⟨ n ⟩ hole = introsWorker n hole

macro
  intro₂ : Term → TC ⊤
  intro₂ hole = introsWorker 2 hole

-- Notes:
-- `intros⟨ n ⟩` builds nested lambdas in one shot, so it doesn’t depend on
-- follow-up interactive invocations.
------------------------------------------------------------------------


------------------------------------------------------------------------
-- Minimal "rewrite" for definitional equality
--  rewriteDef⟨ t ⟩ : if t checks against the WHNF of the goal type,
--  we, in effect, "convert" by def-equality and solve with t.
--  (This is *not* propositional `rewrite` by a proof; it's a safe local
--   convert that leans on the typechecker + normalization.)
------------------------------------------------------------------------
macro
  rewriteDef⟨_⟩ : Term → Term → TC ⊤
  rewriteDef⟨ t ⟩ hole =
    inferType hole >>= λ goal →
    whnf goal      >>= λ goal′ →
    checkType t goal′ >>= λ t′ →
    unify hole t′     >>= λ _  →
    unit tt

-- Notes:
-- `rewriteDef⟨_⟩` is a conservative “convert-by-defeq”: it normalizes the goal type
-- to WHNF and checks the given term against that. No propositional equality
-- plumbing---just a safe local convert.
------------------------------------------------------------------------


------------------------------------------------------------------------
-- Small convenience: applyWith2⟨ f , v₁ , v₂ ⟩
--  Like applyWith, but avoids list syntax on the call site.
------------------------------------------------------------------------
macro
  applyWith2⟨_,_,_⟩ : Term → Term → Term → Term → TC ⊤
  applyWith2⟨ fTerm , v1 , v2 ⟩ hole =
    headZero fTerm          >>= λ f0     →
    inferType f0            >>= λ fty    →
    collectUnknownArgs fty  >>= λ slots  →
    let args = fillVisible (v1 ∷ v2 ∷ []) slots in
    headApp fTerm args      >>= λ app    →
    inferType hole          >>= λ goal   →
    checkType app goal      >>= λ _      →
    unify hole app          >>= λ _      →
    unit tt

--  Notes:
--  `applyWith2⟨_,_,_⟩` makes it easy to supply two visible binders without list
-- literal syntax (which can be finicky in macro arguments).
------------------------------------------------------------------------
