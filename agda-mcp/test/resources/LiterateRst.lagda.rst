.. LiterateRst.lagda.rst
.. File: agda-native-air/agda-mcp/test/resources/LiterateRst.lagda.rst
.. Regression fixture for issues #71/#73 (reStructuredText literate
.. flavour): prose above and below the indented code block carries decoy
.. hole tokens that must never be counted.

Prose above the code with decoy hole tokens: {!!} and {! zero !} and a
lone ? that must never be counted.

The code follows::

  module LiterateRst where

  open import Agda.Builtin.Nat

  n : Nat
  n = {! zero !}

Prose below the hole with another decoy {!!} token.
