-- List-cons-injective-head.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/List-cons-injective-head.agda
--
-- Benchmark obligation: haystack-list-cons-injective-head
-- Difficulty: non-obvious (Tier 3)
--
module List-cons-injective-head where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; _∷_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.List.Properties using ( ∷-injectiveʳ )

∷-injective-head : ∀ {A : Set} {x y : A} {xs : List A} → x ∷ xs ≡ y ∷ xs → x ≡ y
∷-injective-head eq = Data.List.Properties.∷-injectiveˡ eq
