-- agda/AgdaJang/Compat.agda

module AgdaJang.Compat where

open import Agda.Builtin.Unit using (⊤; tt) public

-- Reflection API; re-export the things we need
open import Agda.Builtin.Reflection as R public
  using ( Term; TC; Name
        ; inferType; checkType; unify; catchTC
        ; typeError; strErr; termErr
        ; reduce; normalise
        ; ErrorPart ; Arg ; def
        )

-- Bring the monad ops for TC into scope so '>>=' works.
infixl 1 _>>=_ _>>_
_>>=_ = R.bindTC

_>>_ : ∀ {a b} {A : Set a} {B : Set b} → TC A → TC B → TC B
m >> n = m >>= λ _ → n

return : ∀ {a} {A : Set a} → A → TC A
return = R.returnTC

-- Portable alias: if later Agda version exposes 'whnf', replace this definition.
whnf : Term → TC Term
whnf = reduce
-- For Agda versions without 'whnf', 'reduce' is a reasonable stand-in.
