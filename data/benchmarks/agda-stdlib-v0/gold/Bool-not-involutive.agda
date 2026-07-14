-- Bool-not-involutive.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Bool-not-involutive.agda
--
-- Gold solution for benchmark obligation: stdlib-bool-not-involutive
--
module Bool-not-involutive where

open import AgdaDojang.Debug

open import Data.Bool.Base using ( Bool ; true ; false ; not )
open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )

not-involutive : ∀ (b : Bool) → not (not b) ≡ b
not-involutive true  = refl
not-involutive false = refl
