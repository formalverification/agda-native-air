-- List-append-assoc.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/List-append-assoc.agda
--
-- Gold solution for benchmark obligation: stdlib-list-append-assoc
--
module List-append-assoc where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; [] ; _∷_ ; _++_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong )

++-assoc : ∀ {A : Set} (xs ys zs : List A) → (xs ++ ys) ++ zs ≡ xs ++ (ys ++ zs)
++-assoc []       ys zs = refl
++-assoc (x ∷ xs) ys zs = cong (x ∷_) (++-assoc xs ys zs)
