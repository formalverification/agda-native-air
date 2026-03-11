-- ./agda-dojang/agda/AgdaDojang/Examples.agda
-- This file gives three compile-time checks that exercise `applyWith1`,
-- `applyWith2`, and `rewriteDef`.  The `intro` family is best used interactively,
-- so we leave commented “try me” goals at the bottom.
{-# OPTIONS --safe --cubical-compatible #-}

module AgdaDojang.Examples where

open import Agda.Builtin.Nat using (Nat; zero; suc; _+_)
open import Agda.Builtin.Unit using (⊤; tt)

open import AgdaDojang.Prelude
open import AgdaDojang.Apply

------------------------------------------------------------------------
-- These are *total* examples that compile (no interactive holes).
-- We deliberately avoid reporting macros here (they raise typeError).
------------------------------------------------------------------------

-- 1) Simple value via applyWith1⟨ suc , zero ⟩
ex-suc : Nat
ex-suc = applyWith1⟨ suc , zero ⟩

-- 2) Add two numbers with the 2-arg helper (avoids list syntax)
ex-plus : Nat
ex-plus = applyWith2⟨ _+_ , suc zero , zero ⟩

-- 3) Definitional-equality convert: id (suc zero) ↝ suc zero : Nat
id : {A : Set} → A → A
id x = x

ex-rewriteDef : Nat
ex-rewriteDef = rewriteDef⟨ id (suc zero) ⟩

------------------------------------------------------------------------
-- Interactive macros (don’t include them in total definitions):
-- Uncomment locally to try in an editor:
--
_ : Nat → Nat → Nat
_ =  {! intro₂ !}
--
-- _ : Nat → Nat → Nat → ⊤
-- _ = {! intros⟨ 3 ⟩ !}
------------------------------------------------------------------------
