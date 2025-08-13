-- agda/AgdaJang/Prelude.agda

module AgdaJang.Prelude where

open import Agda.Primitive public
open import Agda.Builtin.Bool public
open import Agda.Builtin.List using (List; []; _∷_) public
open import Agda.Builtin.Nat  using (Nat; zero; suc; _+_) public
open import Agda.Builtin.String using (String; primShowNat) public
open import Agda.Builtin.Unit using (⊤; tt) public

open import Function.Base using (case_of_) public


-- Reflection API; re-export the things we need
open import Agda.Builtin.Reflection as R public
  using ( abs; Arg; arg; ArgInfo; arg-info
        ; bindTC
        ; catchTC; checkType; con
        ; def
        ; ErrorPart
        ; hidden
        ; instance′; inferType
        ; modality
        ; Name; normalise
        ; pi
        ; Quantity; quantity-ω
        ; reduce; Relevance; relevant; returnTC
        ; strErr
        ; TC; Term; termErr; typeError
        ; unify; unknown
        ; Visibility; visible
        )

-- Bring the monad ops for TC into scope so '>>=' works.
infixl 1 _>>=_ _>>_
_>>=_ = bindTC

_>>_ : ∀ {a b} {A : Set a} {B : Set b} → TC A → TC B → TC B
m >> n = m >>= λ _ → n

unit : ∀ {a} {A : Set a} → A → TC A
unit = returnTC

-- Portable alias: if later Agda version exposes 'whnf', replace this definition.
whnf : Term → TC Term
whnf = reduce
-- For Agda versions without 'whnf', 'reduce' is a reasonable stand-in.


-- open import AgdaJang.Refine public
