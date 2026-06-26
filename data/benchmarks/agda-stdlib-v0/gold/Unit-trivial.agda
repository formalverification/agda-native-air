-- Unit-trivial.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Unit-trivial.agda
--
-- Gold solution for benchmark obligation: stdlib-unit-trivial
--
module Unit-trivial where

open import AgdaDojang.Debug

open import Data.Unit.Base using ( ⊤ ; tt )

trivial : ⊤
trivial = tt
