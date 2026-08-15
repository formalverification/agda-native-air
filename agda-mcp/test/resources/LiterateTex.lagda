% LiterateTex.lagda
% File: agda-native-air/agda-mcp/test/resources/LiterateTex.lagda
% Regression fixture for issues #71/#73 (TeX literate flavour, also used for
% .lagda.tex): prose above and below the \begin{code} block carries decoy
% hole tokens that must never be counted.

Prose above the code with decoy hole tokens: {!!} and {! zero !} and a
lone ? that must never be counted.
% A commented-out block is not code: \begin{code}

\begin{code}
module LiterateTex where

open import Agda.Builtin.Nat

n : Nat
n = {! zero !}
\end{code}

Prose below the hole with another decoy {!!} token.
