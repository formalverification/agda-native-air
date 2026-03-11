-- FixtureStdlibBooleanAlgebraMinimal.agda
--
-- File: data/agda/FixtureStdlibBooleanAlgebraMinimal.agda
--

module FixtureStdlibBooleanAlgebraMinimal where

-- AgdaJang reporting macro used by agent_bridge / eval_fixtures:
open import AgdaJang.Debug using (reportGoalCtx)
open import Data.Bool.Properties using (∨-∧-booleanAlgebra)
open import Algebra.Lattice.Bundles using (BooleanAlgebra)
open BooleanAlgebra (∨-∧-booleanAlgebra)

-- Stdlib already proves these for any BooleanAlgebra; instantiate with the Bool one.
open import Algebra.Lattice.Properties.BooleanAlgebra (∨-∧-booleanAlgebra)
  using (⊥≉⊤; deMorgan₁; deMorgan₂)

goal-¬⊥≈⊤ : ¬ ⊥ ≈ ⊤
goal-¬⊥≈⊤ = {!!}

goal-deMorgan₁ : ∀ x y → ¬ (x ∧ y) ≈ ¬ x ∨ ¬ y
goal-deMorgan₁ = λ x y → {!!}

goal-deMorgan₂ : ∀ x y → ¬ (x ∨ y) ≈ ¬ x ∧ ¬ y
goal-deMorgan₂ x y = {!!}
