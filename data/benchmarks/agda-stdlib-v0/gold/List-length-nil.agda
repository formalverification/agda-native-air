-- List-length-nil.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/List-length-nil.agda
--
-- Gold solution for benchmark obligation: stdlib-list-length-nil
--
module List-length-nil where

open import AgdaDojang.Debug

open import Data.Nat.Base  using ( ℕ )
open import Data.List.Base using ( List ; [] ; length )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

length-[] : {A : Set} → length {A = A} [] ≡ 0
length-[] = refl
