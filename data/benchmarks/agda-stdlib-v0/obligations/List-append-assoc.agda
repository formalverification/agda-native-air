-- List-append-assoc.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/List-append-assoc.agda
--
-- Benchmark obligation: stdlib-list-append-assoc
-- Difficulty: compositional (Tier 2)
-- Source: Data.List.Properties
-- Strategy: induction on xs; base refl, step cong (x ∷_) IH
--
module List-append-assoc where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; [] ; _∷_ ; _++_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

++-assoc : ∀ {A : Set} (xs ys zs : List A) → (xs ++ ys) ++ zs ≡ xs ++ (ys ++ zs)
++-assoc xs ys zs = {!!}
