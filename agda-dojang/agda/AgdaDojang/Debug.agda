-- Debug.agda
--
-- File: agda-dojang/agda/AgdaDojang/Debug.agda
--
-- Description:
--   This module contains macros that can be used to print out the current goal, its
--   type, and the results of normalisation and whnf.
--
--   These macros can be invoked by writing `showGoal ?` or `showGoalType ?` in the
--   source code, where `?` is a hole that will be replaced by the current goal term.
--
--   The `showTypeNFvsWHNF` macro compares the raw type, its whnf, and its normal
--   form, which can be useful for understanding how the type is being processed by
--   the Agda type checker.
--
--   Note that these macros will raise a type error with the information, so they
--   should be used for debugging and not included in final code.
--
{-# OPTIONS --safe --cubical-compatible #-}

module AgdaDojang.Debug where

open import AgdaDojang.Prelude
open import Agda.Builtin.List using (_∷_; [])
-- We need qualified access to reflection constructors like R.var / R.lam:
open import Agda.Builtin.Reflection as R using ()

------------------------------------------------------------------------
-- A tiny Kleisli toolkit for TC
------------------------------------------------------------------------

infixr 1 _>=>_
_>=>_ : ∀ {a b c} {A : Set a} {B : Set b} {C : Set c}
      → (A → TC B) → (B → TC C) → (A → TC C)
(f >=> g) x = f x >>= g

------------------------------------------------------------------------
-- De Bruijn raise (shift) for Terms
------------------------------------------------------------------------

_≤ᵇ_ : Nat → Nat → Bool
zero  ≤ᵇ _      = true
suc _ ≤ᵇ zero   = false
suc m ≤ᵇ suc n  = m ≤ᵇ n


raiseTerm : Nat → Term → Term
raiseTerm k t = raiseFrom zero k t
  where
    -- Termination-friendly: only `raiseFrom` recurses, and only on strict subterms.
    raiseFrom : Nat → Nat → Term → Term

    go : Nat → Nat → List (Arg Term) → List (Arg Term)
    go _ _ [] = []
    go c k (arg info t ∷ rest) = arg info (raiseFrom c k t) ∷ go c k rest

    raiseFrom c k (R.var x args) = R.var (if c ≤ᵇ x then x + k else x) (go c k args)
    raiseFrom c k (R.def f args) = R.def f (go c k args)
    raiseFrom c k (R.con cn args) = R.con cn (go c k args)
    raiseFrom c k (R.meta m args) = R.meta m (go c k args)
    raiseFrom c k (R.pat-lam cs args) = R.pat-lam cs (go c k args)
    raiseFrom c k (R.pi (arg info dom) (R.abs s cod)) =
      R.pi (arg info (raiseFrom c k dom)) (R.abs s (raiseFrom (suc c) k cod))
    raiseFrom c k (R.lam v (R.abs s body)) =
      R.lam v (R.abs s (raiseFrom (suc c) k body))
    raiseFrom _ _ t = t

------------------------------------------------------------------------
-- Basic debugging macros
------------------------------------------------------------------------

macro
  showGoal : Term → TC ⊤
  showGoal hole =
    typeError (strErr "GOAL HOLE TERM (raw): " ∷ termErr hole ∷ [])

-- Print the type of the current goal (elaborated).
macro
  showGoalType : Term → TC ⊤
  showGoalType hole =
    inferType hole >>= λ ty →
    typeError (strErr "GOAL TYPE: " ∷ termErr ty ∷ [])

-- Compare the raw type, its 'whnf' (alias defined in Prelude), and full 'normalise'.
macro
  showTypeNFvsWHNF : Term → TC ⊤
  showTypeNFvsWHNF hole =
    inferType hole  >>= λ A  →
    whnf A          >>= λ A' →
    normalise A     >>= λ A'' →
    typeError
      ( strErr "TYPE:  " ∷ termErr A
      ∷ strErr "\nWHNF: " ∷ termErr A'
      ∷ strErr "\nNF:   " ∷ termErr A''
      ∷ [] )

------------------------------------------------------------------------
-- Reporting helpers
------------------------------------------------------------------------
-- Reuse our visibility tagger
visTag : Visibility → String
visTag visible   = "visible"
visTag hidden    = "hidden"
visTag instance′ = "instance"

-- Render a Term as a String the same way you were doing (via ErrorParts)
termToString : Term → TC String
termToString t = formatErrorParts (termErr t ∷ [])

-- Context lines: AGDADOJANG_CTX:<i>:<vis>:<name>: <type>
mkCtxParts :
  Nat →
  List (Σ String (λ _ → Arg Term)) →
  List ErrorPart →
  TC (List ErrorPart)
mkCtxParts _ [] tail = unit tail
  -- NOTE:
  --   getContext returns binder types in the *telescope* scope;
  --   the type of the i-th entry is expressed in the context *before* that binder.
  --   When we pretty-print inside the *full* current context, de Bruijn indices
  --   would otherwise be off-by-(suc i), e.g. A (var 0) would print as x.
  --   So we raise by (suc i) before normalising/printing.
mkCtxParts i ((nm , arg (arg-info v _) t) ∷ rest) tail =
  normalise (raiseTerm (suc i) t) >>= λ tyNF →
  termToString tyNF               >>= λ tyStr →
  mkCtxParts (suc i) rest tail    >>= λ tail′ →
  unit (  strErr "AGDADOJANG_CTX:" ∷ strErr (primShowNat i) ∷ strErr ":" ∷ strErr (visTag v)
        ∷ strErr ":" ∷ strErr nm ∷ strErr ": " ∷ strErr tyStr ∷ strErr "\n"
        ∷ tail′ )

macro
  reportGoalCtx : Term → TC ⊤
  reportGoalCtx hole =
    -- Build goal string: inferType >=> normalise >=> termToString
    (inferType >=> normalise >=> termToString) hole >>= λ goalStr →
    getContext >>= λ ctx →
    mkCtxParts 0 ctx (strErr "AGDADOJANG_REQ_END" ∷ []) >>= λ ctxParts →
    typeError
      ( strErr "AGDADOJANG_REQ_BEGIN\n"
      ∷ strErr "AGDADOJANG_GOAL: " ∷ strErr goalStr ∷ strErr "\n"
      ∷ strErr "AGDADOJANG_CTX_BEGIN\n"
      ∷ ctxParts
      )
-- Notes.
--   policy_fixture.py already solves our demo-class goals:
--   +  assumption rule (find `x : A` when goal is A)
--   +  ⊤ → tt
--   +  _≡_ → refl
--   So with reportGoalCtx, our bridge can solve 1–3 (likely *all*) holes in a
--   fixture file deterministically.
