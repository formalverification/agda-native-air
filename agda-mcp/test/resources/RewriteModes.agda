-- RewriteModes.agda
--
-- File: agda-native-air/agda-mcp/test/resources/RewriteModes.agda
--
-- Description:
--   Fixture for issue #248, the display mode of get_goal and type_of.  The
--   hole's context holds a module parameter of a defined type, `p : Pair Nat`,
--   which the display modes print differently: Simplified, the default (what
--   an editor sends), keeps the name, and Normalised unfolds it into the Σ
--   type it abbreviates, as it unfolded `Group α ρ` on the #243 field hole.
--   On the Nat fixtures the lane was first probed on every mode prints the
--   same thing, which is how the old default went unnoticed.
--
--   `b : Box` is the control: a record type is not a definition that
--   reduces, so every mode prints it as written.  A record type alone would
--   not tell the modes apart.
module RewriteModes where

open import Agda.Builtin.Nat
open import Agda.Builtin.Sigma

Pair : Set → Set
Pair A = Σ A (λ _ → A)

record Box : Set where
  field contents : Nat

module _ (p : Pair Nat) (b : Box) where

  first : Nat
  first = {!!}
