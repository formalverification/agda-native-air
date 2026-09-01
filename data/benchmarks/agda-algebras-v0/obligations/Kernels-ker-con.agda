-- Kernels-ker-con.agda
--
-- File: data/benchmarks/agda-algebras-v0/obligations/Kernels-ker-con.agda
--
-- Benchmark obligation: algebras-kernels-ker-con
-- Difficulty: non-obvious
-- Source: Setoid.Homomorphisms.Kernels (agda-algebras)
-- Import stratum: using
-- Strategy: record-assembly
--
module Kernels-ker-con where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )
open import Data.Product     using ( _,_ ; proj₁ )
open import Relation.Binary  using ( Setoid )
open import Function.Bundles using ( Func )

open import Overture              using ( Signature ; kerRel ; kerRelOfEquiv )
open import Setoid.Algebras       using ( Algebra ; 𝔻[_] )
open import Setoid.Congruences    using ( Con ; mkcon )
open import Setoid.Homomorphisms  using ( hom ; HomKerComp )

kercon′ : {𝓞 𝓥 α ρᵃ β ρᵇ : Level} {𝑆 : Signature 𝓞 𝓥}
          {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ}
          (h : hom 𝑨 𝑩)
  →  Con 𝑨 ρᵇ
kercon′ {𝑩 = 𝑩} h = {!!}
