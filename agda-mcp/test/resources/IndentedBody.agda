-- IndentedBody.agda
--
-- File: agda-native-air/agda-mcp/test/resources/IndentedBody.agda
--
-- Description:
--   Regression fixture from Copilot's third review of PR 105: a module whose
--   header sits at column 1 while its body is indented.  That is legal Agda —
--   Agda checks this file and reports exactly one interaction point — but
--   get_goal used to give the debug import it injects the *header's*
--   indentation, landing it at column 1 above declarations at column 3.  Agda
--   then reads those declarations as continuations of the import and answers
--   [ParseError], so get_goal failed on a file that type-checks (measured).
--   The import now takes the indentation of the module's body instead, which is
--   what makes it a layout sibling of the declarations it joins.
module IndentedBody where
  open import Agda.Builtin.Nat

  n : Nat
  n = {! zero !}
