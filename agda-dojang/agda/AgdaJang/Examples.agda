module AgdaJang.Examples where
open import Agda.Builtin.Nat
open import AgdaJang.Debug

demo : Nat
demo = {! showGoal !}
