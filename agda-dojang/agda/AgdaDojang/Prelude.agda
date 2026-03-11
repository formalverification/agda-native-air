-- Prelude.agda
--
-- File: agda-dojang/agda/AgdaDojang/Prelude.agda
--
-- Description:
--   This module serves as a prelude for the AgdaDojang project, providing common
--   imports and definitions that are used across the project. It re-exports necessary
--   parts of the Agda standard library and the reflection API, and defines some
--   convenient aliases and helper functions for working with the TC monad and terms.
--   The goal is to have a single place where we can manage our imports and common
--   utilities, making it easier to maintain and update as needed.
--
-- Notes:
--   This module is not intended to be a comprehensive prelude; it only includes
--   the specific imports and definitions that are currently needed for the AgdaDojang
--   project. As the project evolves, we may add more imports or utilities here as needed.
--
{-# OPTIONS --safe --cubical-compatible #-}

module AgdaDojang.Prelude where

open import Agda.Primitive public
open import Agda.Builtin.Bool public
open import Agda.Builtin.List using (List; []; _∷_) public
open import Agda.Builtin.Nat  using (Nat; zero; suc; _+_) public
open import Agda.Builtin.Sigma using (Σ; _,_; fst; snd) public
open import Agda.Builtin.String using (String; primShowNat) public
open import Agda.Builtin.Unit using (⊤; tt) public
open import Data.Bool using (if_then_else_) public
open import Data.String.Properties using (_==_) public
open import Function.Base using (case_of_) public
open import Relation.Binary.PropositionalEquality.Core public
  using (_≡_) -- ; _≢_; refl; cong; cong₂; sym; _≗_; trans; ≢-sym; subst₂;


-- Reflection API; re-export the things we need
open import Agda.Builtin.Reflection as R public
  using ( abs; Arg; arg; ArgInfo; arg-info
        ; bindTC
        ; catchTC; checkType; con
        ; def
        ; ErrorPart
        ; formatErrorParts
        ; getContext
        ; hidden
        ; instance′; inferType
        ; Modality; modality
        ; Name; normalise
        ; pi
        ; Quantity; quantity-ω
        ; reduce; Relevance; relevant; returnTC
        ; strErr
        ; TC; Term; termErr; typeError
        ; unify; unknown
        ; Visibility; visible
        )

-- Bring the monad ops for TC into scope so '>>=' works.
infixl 1 _>>=_ _>>_

-- Give an explicit signature, so monadic plumbing carries concrete universes.
_>>=_ : ∀ {a b} {A : Set a} {B : Set b} → TC A → (A → TC B) → TC B
_>>=_ = bindTC

_>>_ : ∀ {a b} {A : Set a} {B : Set b} → TC A → TC B → TC B
m >> n = m >>= λ _ → n

unit : ∀ {a} {A : Set a} → A → TC A
unit = returnTC

-- Portable alias: if later Agda version exposes 'whnf', replace this definition.
whnf : Term → TC Term
whnf = reduce
-- For Agda versions without 'whnf', 'reduce' is a reasonable stand-in.


-- ergonomic arg builders
vArg : Term → Arg Term
vArg t = arg (arg-info visible (modality relevant quantity-ω)) t

hArg : Term → Arg Term
hArg t = arg (arg-info hidden (modality relevant quantity-ω)) t

iArg : Term → Arg Term
iArg t = arg (arg-info instance′ (modality relevant quantity-ω)) t


macro
  term⟨_⟩ : Term → Term → TC ⊤
  term⟨ t ⟩ hole = unify hole t
  -- The `term⟨_⟩` macro allows us to write, e.g.,
  --    ex₃ : Nat
  --    ex₃ = applyWith⟨ _+_ , term⟨ zero ⟩ ∷ [] ⟩
  -- or
  --    ex₃ = applyWith⟨ _+_ , [ term⟨ zero ⟩ ] ⟩
