-- List-cons-injective-head.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/gold/List-cons-injective-head.agda
--
-- Benchmark obligation: haystack-list-cons-injective-head
-- Difficulty: non-obvious (Tier 3)
-- Haystack: Data.List.Properties
-- Needle: Data.List.Properties.∷-injectiveˡ
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: the goal x ≡ y carries no signal; the decoy is the needle's own sibling.
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module List-cons-injective-head where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; _∷_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.List.Properties using ( ∷-injectiveʳ )

∷-injective-head : ∀ {A : Set} {x y : A} {xs : List A} → x ∷ xs ≡ y ∷ xs → x ≡ y
∷-injective-head eq = Data.List.Properties.∷-injectiveˡ eq
