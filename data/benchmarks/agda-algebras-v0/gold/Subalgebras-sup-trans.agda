-- Subalgebras-sup-trans.agda (gold solution)
--
-- File: data/benchmarks/agda-algebras-v0/gold/Subalgebras-sup-trans.agda
--
-- Gold solution for benchmark obligation: algebras-subalgebras-sup-trans
--
module Subalgebras-sup-trans where

open import AgdaDojang.Debug

open import Agda.Primitive   using ( Level )

open import Overture            using ( Signature )
open import Setoid.Algebras     using ( Algebra )
open import Setoid.Subalgebras  using ( _≥_ ; ≤-trans )

≥-trans′ : {𝓞 𝓥 α ρᵃ β ρᵇ γ ρᶜ : Level} {𝑆 : Signature 𝓞 𝓥}
           {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ} {𝑪 : Algebra γ ρᶜ}
  →  𝑨 ≥ 𝑩 → 𝑩 ≥ 𝑪 → 𝑨 ≥ 𝑪
≥-trans′ p q = ≤-trans q p
