module AgdaJang.Debug where

open import AgdaJang.Prelude
open import Agda.Builtin.List using (_∷_; [])

-- Print the type of the current goal (elaborated).
macro
  showGoalType : Term → TC ⊤
  showGoalType hole =
    inferType hole >>= λ ty →
    typeError (strErr "GOAL TYPE: " ∷ termErr ty ∷ [])

-- Compare the raw type, its 'whnf' (alias defined in Prelude), and full 'normalise'.
macro
  showTypeNFvsWHNF : Term → TC ⊤
  showTypeNFvsWHNF hole =
    inferType hole  >>= λ A  →
    whnf A          >>= λ A' →
    normalise A     >>= λ A'' →
    typeError
      ( strErr "TYPE:  " ∷ termErr A
      ∷ strErr "\nWHNF: " ∷ termErr A'
      ∷ strErr "\nNF:   " ∷ termErr A''
      ∷ [] )

