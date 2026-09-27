-- Group-centralizer-closed.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/gold/Group-centralizer-closed.agda
--
-- Benchmark obligation: hard-group-centralizer-closed
-- Difficulty: compositional
-- Source: exam genre (Algebra.Bundles.Group)
-- Import stratum: novel
-- Strategy: the product case is associativity twice; the inverse case conjugates the hypothesis by x ⁻¹ on both sides
--
-- What commutes with a commutes with products and inverses: if a ∙ x ≈ x ∙ a and a ∙ y ≈ y ∙ a then a ∙ (x ∙ y) ≈ (x ∙ y) ∙ a and a ∙ x ⁻¹ ≈ x ⁻¹ ∙ a.
--
-- GOLD WANTED
module Group-centralizer-closed where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )
open import Data.Product.Base         using ( _×_ )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  centralizer-closed
    :  ∀ a x y → a ∙ x ≈ x ∙ a → a ∙ y ≈ y ∙ a
    →  (a ∙ (x ∙ y) ≈ (x ∙ y) ∙ a) × (a ∙ x ⁻¹ ≈ x ⁻¹ ∙ a)
  centralizer-closed a x y ax≈xa ay≈ya = {!!}
