-- Fixture05.agda
--
-- File: data/agda/Fixture05.agda
--
module Fixture05 where

open import Agda.Builtin.Unit
open import Agda.Builtin.Equality
open import AgdaDojang.Debug

-- Explicit universe parameter. Goal is A; ctx includes x : A.
id2 : (A : Set) → A → A
id2 A x = {!!}

-- Another equality refl.
refl5 : {A : Set} (x : A) → x ≡ x
refl5 x = {!!}

-- ⊤ again.
trivial5 : ⊤
trivial5 = {!!}
