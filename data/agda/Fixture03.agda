-- Fixture03.agda
--
-- File: data/agda/Fixture03.agda
--
module Fixture03 where

open import Agda.Builtin.Unit
open import Agda.Builtin.Equality
open import AgdaJang.Debug

-- Goal is A; ctx includes a : A, b : B → policy proposes "a"
const : {A B : Set} → A → B → A
const a b = {!!}

-- Goal is ⊤; ctx includes u : ⊤ (policy may pick u or tt)
unitId : ⊤ → ⊤
unitId u = {!!}

-- Goal is x ≡ x; ctx includes x
refl3 : {A : Set} (x : A) → x ≡ x
refl3 x = {!!}
