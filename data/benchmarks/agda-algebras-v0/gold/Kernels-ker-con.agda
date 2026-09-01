-- Kernels-ker-con.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Kernels-ker-con.agda
--
-- Gold solution for benchmark obligation: algebras-kernels-ker-con
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
kercon′ {𝑩 = 𝑩} h =
  kerRel (Setoid._≈_ 𝔻[ 𝑩 ]) (Func.to (proj₁ h)) ,
  mkcon (λ x → Func.cong (proj₁ h) x)
        (kerRelOfEquiv (Setoid.isEquivalence 𝔻[ 𝑩 ]) (Func.to (proj₁ h)))
        (HomKerComp h)
