-- agda-dojang/agda/AgdaDojang/Everything.agda
{-# OPTIONS --safe --cubical-compatible #-}

module AgdaDojang.Everything where

open import AgdaDojang.Prelude
open import AgdaDojang.Refine
open import AgdaDojang.Apply
open import AgdaDojang.Debug

-- Smoke tests (tiny compile-time checks that should always succeed)
-- _ : Set
-- _ = {! showGoalType !}  -- leave commented out unless debugging
