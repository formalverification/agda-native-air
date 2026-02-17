-- Debug.agda
--
-- File: agda-jang/agda/AgdaJang/Debug.agda
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

module AgdaJang.Debug where

open import AgdaJang.Prelude
open import Agda.Builtin.List using (_∷_; [])

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

-- Reuse our visibility tagger
visTag : Visibility → String
visTag visible   = "visible"
visTag hidden    = "hidden"
visTag instance′ = "instance"

-- Context lines: AGDAJANG_CTX:<i>:<vis>:<name>: <type>
mkCtxParts :
  Nat →
  List (Σ String (λ _ → Arg Term)) →
  List ErrorPart →
  TC (List ErrorPart)
mkCtxParts _ [] tail = unit tail
mkCtxParts i ((nm , arg (arg-info v _) t) ∷ rest) tail = do
  -- NOTE: in getContext, the payload is a *term for the variable*; infer its type.
  ty    ← inferType t
  tyNF  ← normalise ty
  tyStr ← formatErrorParts (termErr tyNF ∷ [])
  tail′  ← mkCtxParts (suc i) rest tail
  unit (  strErr "AGDAJANG_CTX:" ∷ strErr (primShowNat i) ∷ strErr ":" ∷ strErr (visTag v)
        ∷ strErr ":" ∷ strErr nm ∷ strErr ": " ∷ strErr tyStr ∷ strErr "\n"
        ∷ tail′ )

macro
  reportGoalCtx : Term → TC ⊤
  reportGoalCtx hole = do
    goalTy  ← inferType hole
    goalNF  ← normalise goalTy
    goalStr ← formatErrorParts (termErr goalNF ∷ [])

    ctx ← getContext

    ctxParts ← mkCtxParts 0 ctx (strErr "AGDAJANG_REQ_END" ∷ [])
    typeError
      ( strErr "AGDAJANG_REQ_BEGIN\n"
      ∷ strErr "AGDAJANG_GOAL: " ∷ strErr goalStr ∷ strErr "\n"
      ∷ strErr "AGDAJANG_CTX_BEGIN\n"
      ∷ ctxParts
      )
-- Notes.
--   policy_fixture.py already solves our demo-class goals:
--   +  assumption rule (find `x : A` when goal is A)
--   +  ⊤ → tt
--   +  _≡_ → refl
--   So with reportGoalCtx, our bridge can solve 1–3 (likely *all*) holes in a
--   fixture file deterministically.
