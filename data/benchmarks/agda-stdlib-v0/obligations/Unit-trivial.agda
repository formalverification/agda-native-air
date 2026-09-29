-- Unit-trivial.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Unit-trivial.agda
--
-- Benchmark obligation: stdlib-unit-trivial
-- Difficulty: routine (Tier 1)
--
module Unit-trivial where

open import AgdaDojang.Debug

open import Data.Unit.Base using ( ⊤ ; tt )

trivial : ⊤
trivial = {!!}
