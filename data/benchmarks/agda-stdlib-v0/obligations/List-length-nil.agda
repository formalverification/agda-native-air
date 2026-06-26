-- List-length-nil.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/List-length-nil.agda
--
-- Benchmark obligation: stdlib-list-length-nil
-- Difficulty: routine (Tier 1)
-- Source: Data.List.Base
-- Strategy: refl (length [] reduces to 0)
--
module List-length-nil where

open import AgdaDojang.Debug

open import Data.Nat.Base  using ( ℕ )
open import Data.List.Base using ( List ; [] ; length )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

length-[] : {A : Set} → length {A = A} [] ≡ 0
length-[] = {!!}
