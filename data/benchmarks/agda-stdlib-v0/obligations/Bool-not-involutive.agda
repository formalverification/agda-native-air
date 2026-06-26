-- Bool-not-involutive.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Bool-not-involutive.agda
--
-- Benchmark obligation: stdlib-bool-not-involutive
-- Difficulty: routine (Tier 1)
-- Source: Data.Bool.Properties
-- Strategy: case split on the boolean; each branch is refl
--
module Bool-not-involutive where

open import AgdaDojang.Debug

open import Data.Bool.Base using ( Bool ; true ; false ; not )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

not-involutive : ∀ (b : Bool) → not (not b) ≡ b
not-involutive b = {!!}
