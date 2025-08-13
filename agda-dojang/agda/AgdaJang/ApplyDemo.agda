-- agda/ApplyDemo.agda
module AgdaJang.ApplyDemo where
open import Agda.Builtin.Nat
open import AgdaJang.Apply

ex₁ : Nat
ex₁ = refineApp⟨ suc zero ⟩    -- checks suc zero : Nat, then fills the goal
