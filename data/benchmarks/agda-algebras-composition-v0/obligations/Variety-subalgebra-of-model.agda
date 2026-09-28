-- Variety-subalgebra-of-model.agda
--
-- File: data/benchmarks/agda-algebras-composition-v0/obligations/Variety-subalgebra-of-model.agda
--
-- Benchmark obligation: comp-variety-subalgebra-of-model
-- Difficulty: non-obvious
-- Source: Setoid.Varieties.Properties (⊧-S-invar), Setoid.Varieties.SoundAndComplete (Soundness.sound), Setoid.Subalgebras.Basic (mon→≤)
-- Import stratum: composition
-- Strategy: soundness makes the model satisfy the identity; the monomorphism makes A a subalgebra of it; identities pass to subalgebras
--
-- An algebra that embeds in a model of E satisfies every identity derivable from E.
--
module Variety-subalgebra-of-model where

open import AgdaDojang.Debug

open import Level                              using ( Level )
open import Overture                           using ( 𝓞 ; 𝓥 ; Signature )
open import Overture.Terms                     using ( Term )
open import Setoid.Algebras                    using ( Algebra )
open import Setoid.Homomorphisms.Basic         using ( mon )
open import Setoid.Subalgebras.Basic           using ( _≤_ )
open import Setoid.Varieties.Properties        using ( ⊧-I-invar )
open import Setoid.Varieties.SoundAndComplete  using ( Eq ; _⊨_ ; _⊧_ ; _≈̇_ ; _⊢_▹_≈_ )

module _ {α ρᵃ β ρᵇ χ ι : Level} {𝑆 : Signature 𝓞 𝓥} {X : Set χ} {I : Set ι}
  {E : I → Eq {𝑆 = 𝑆} {χ = χ}} {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra {𝑆 = 𝑆} β ρᵇ}
  {p q : Term X}
  where

  embeds-in-model : 𝑩 ⊨ E → E ⊢ X ▹ p ≈ q → mon 𝑨 𝑩 → 𝑨 ⊧ (p ≈̇ q)
  embeds-in-model B⊨E Epq A↪B = {!!}
