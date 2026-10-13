-- Congruence-simple-equivalent-total.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Congruence-simple-equivalent-total.agda
--
-- Benchmark obligation: comp-congruence-simple-equivalent-total
-- Difficulty: compositional
-- Import stratum: composition
--
-- In a simple algebra, a congruence equivalent to one that relates two distinct points is the total congruence.
--
module Congruence-simple-equivalent-total where

open import AgdaDojang.Debug

open import Data.Product                  using ( proj₁ )
open import Level                         using ( Level )
open import Overture                      using ( 𝓞 ; 𝓥 ; Signature )
open import Setoid.Algebras               using ( Algebra )
open import Setoid.Congruences.Basic      using ( Con ; 𝟙[_] )
open import Setoid.Congruences.Lattice    using ( _≑_ ; ≑-refl )
open import Setoid.Congruences.Simple     using ( IsSimple ; RelatesDistinctPoints )

open import Data.Product   using ( _,_ )
open import Data.Unit.Base using ( tt )
open import Level          using ( lift )

module _ {α ρ ℓ : Level} {𝑆 : Signature 𝓞 𝓥} {𝑨 : Algebra {𝑆 = 𝑆} α ρ} {θ φ : Con 𝑨 ℓ} where

  simple-equivalent-total : IsSimple 𝑨 ℓ → RelatesDistinctPoints 𝑨 (proj₁ θ) → θ ≑ φ → φ ≑ 𝟙[ 𝑨 ]
  simple-equivalent-total simple (a , b , aθb , a≉b) (θ⊆φ , _) =
    (λ _ → lift tt) , λ {x} {y} _ → simple φ (a , b , θ⊆φ aθb , a≉b) x y
