-- agda-jang/agda/AgdaJang/Everything.agda
{-# OPTIONS --safe --cubical-compatible #-}

module AgdaJang.Everything where

open import AgdaJang.Prelude
open import AgdaJang.Refine
open import AgdaJang.Apply
open import AgdaJang.Debug

-- Smoke tests (tiny compile-time checks that should always succeed)
-- _ : Set
-- _ = {! showGoalType !}  -- leave commented out unless debugging
