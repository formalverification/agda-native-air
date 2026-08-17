<!-- TwoHolesLiterate.lagda.md
     File: agda-native-air/agda-mcp/test/resources/TwoHolesLiterate.lagda.md
     Regression fixture for issue #79: the literate twin of TwoHoles.agda —
     two holes in one Agda code fence, with decoy hole tokens in the prose
     around them.  Filling the first hole renumbers the second (index 1
     becomes index 0) but does not move it, so this is where a by-position
     handle earns its keep, in literate-file coordinates.  The declarations
     are deliberately identical to the plain twin's, so the two files differ
     only in flavour and in where their holes sit. -->

# TwoHolesLiterate

Prose above the code, carrying decoy tokens that must never be addressable —
neither by index nor by position: {!!} and {! zero !} and a lone ? .

```agda
module TwoHolesLiterate where

open import Agda.Builtin.Nat

g : Nat
g = {!!}

h : Nat
h = {!!}
```

Prose below the holes, with one more decoy {!!} token.
