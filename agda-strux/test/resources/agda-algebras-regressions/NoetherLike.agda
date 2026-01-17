-- File: agda-backend-jsonl/test/resources/NoetherLike.agda

{-# OPTIONS --safe #-}

module NoetherLike where

open import Agda.Primitive using (Level; _⊔_; lsuc)

private variable
  α : Level
  A : Set α

id : A → A
id x = x

-- This anonymous section is the key: Agda often produces internal qnames like
--   NoetherLike._.secId
-- while we want prettyQname to normalize to
--   NoetherLike.secId
module _ {A : Set α} where
  secId : A → A
  secId = id

FirstHomTheorem|Set : {A : Set α} → A → A
FirstHomTheorem|Set = secId

module Nested where
  bar : {A : Set α} → A → A
  bar x = x
