-- Overture-proj-op.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Overture-proj-op.agda
--
-- Gold solution for benchmark obligation: algebras-overture-proj-op
--
module Overture-proj-op where

open import AgdaDojang.Debug

open import Agda.Primitive  using ( Level )

open import Overture.Operations  using ( Op )

π : {𝓥 a : Level} {I : Set 𝓥} {A : Set a} → I → Op I A
π i = λ x → x i
