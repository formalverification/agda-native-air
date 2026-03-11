-- ApplyDemo.agda
--
-- File: agda-jang/agda/AgdaJang/ApplyDemo.agda
--
-- Description:
--   This module demonstrates the use of the `apply` macro from `AgdaJang
--   Apply`. The `apply` macro allows us to create an application of a function to
--   some arguments, where the arguments are represented as metas (holes) that can be
--   filled in later.  This can be useful for constructing terms incrementally or for
--   testing the behavior of metas in applications.
--
--   In this example, we show how to use `apply` to create an application of the `suc`
--   function to a meta argument. This will create a term that looks like `suc ?`,
--   where `?` is a meta that can be filled in later.  If the goal is not already a
--   function type, this will leave a subgoal (meta) that needs to be solved.
--
{-# OPTIONS --safe --cubical-compatible #-}

module ApplyDemo where
open import Agda.Builtin.Nat
open import AgdaJang.Apply

-- If 'suc' is in scope:
ex₁ : Nat
ex₁ = apply⟨ (quote suc) ⟩   -- creates an application with one meta for the arg
-- This will leave a subgoal (meta) unless the goal is already a function.
