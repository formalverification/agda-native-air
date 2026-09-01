-- Overture-proj-op.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Overture-proj-op.agda
--
-- Benchmark obligation: algebras-overture-proj-op
-- Difficulty: routine
-- Source: Overture.Operations (agda-algebras)
-- Import stratum: using
-- Strategy: lambda
--
module Overture-proj-op where

open import AgdaDojang.Debug

open import Agda.Primitive  using ( Level )

open import Overture.Operations  using ( Op )

π : {𝓥 a : Level} {I : Set 𝓥} {A : Set a} → I → Op I A
π i = {!!}
