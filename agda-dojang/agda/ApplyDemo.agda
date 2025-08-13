-- agda/ApplyDemo.agda
module ApplyDemo where
open import Agda.Builtin.Nat
open import AgdaJang.Apply

-- Succeeds: fills the goal with a surface term
ex₁ : Nat
ex₁ = refineApp⟨ suc zero ⟩    -- checks suc zero : Nat, then fills the goal

-- Leaves a subgoal (meta) for the argument of 'suc'
ex₂ : Nat
ex₂ = apply⟨ suc ⟩  -- creates an application with one subgoal (meta) for the arg
                    -- leaves a subgoal ?0 : Nat
