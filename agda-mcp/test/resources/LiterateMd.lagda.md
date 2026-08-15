<!-- LiterateMd.lagda.md
     File: agda-native-air/agda-mcp/test/resources/LiterateMd.lagda.md
     Regression fixture for issues #71/#73: a .lagda.md whose only hole is a
     {! zero !} inside the one Agda code fence.  The prose above and below,
     and the non-Agda fenced block, carry decoy hole tokens that must never
     be counted or filled. -->

# LiterateMd

Prose above the code with decoy hole tokens: {!!} and {! zero !} and a
lone ? that must never be counted.

module Example where — this prose line must not be mistaken for the
module header when get_goal injects its debug import.

```agda
module LiterateMd where

open import Agda.Builtin.Nat

n : Nat
n = {! zero !}
```

Prose below the hole with another decoy {!!} token.

```haskell
main = print "a non-Agda code block with a decoy {!!} token"
```

Closing prose mentioning {!!} one more time.
