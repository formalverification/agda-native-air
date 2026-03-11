-- agda/ApplyDemo.agda
module ApplyDemo where
open import AgdaDojang.Prelude
open import AgdaDojang.Apply

-- Succeeds: fills the goal with a surface term
ex₁ : Nat
ex₁ = refineApp⟨ suc zero ⟩    -- checks suc zero : Nat, then fills the goal

-- Leaves a subgoal (meta) for the argument of 'suc'
ex₂ : Nat
ex₂ = apply⟨ suc ⟩  -- creates an application with one subgoal (meta) for the arg
                    -- leaves a subgoal ?0 : Nat

ex₃ : Nat
ex₃ = applyWith1⟨ _+_ , term⟨ zero ⟩ ⟩

ex₄ : Nat
ex₄ = applyWith⟨ _+_ , term⟨ zero ⟩ ∷ [] ⟩
-- applyWith⟨ _+_ , [ term⟨ zero ⟩ ] ⟩
