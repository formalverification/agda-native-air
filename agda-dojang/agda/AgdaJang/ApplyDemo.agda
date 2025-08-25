-- agda/AgdaJang/ApplyDemo.agda
module ApplyDemo where
open import Agda.Builtin.Nat
open import AgdaJang.Apply

-- If 'suc' is in scope:
ex₁ : Nat
ex₁ = apply⟨ (quote suc) ⟩   -- creates an application with one meta for the arg
-- This will leave a subgoal (meta) unless the goal is already a function.
