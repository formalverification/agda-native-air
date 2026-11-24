-- File: agda-native-air/agda-mcp/test/resources/PatchUnits.agda
--
-- Fixture for fill_hole's patch and apply (issue 136): one hole of each
-- syntax, placed so that a position counted in the wrong unit lands on other
-- text.  The glyph named A below is U+1D468, one code point, two UTF-16
-- units, and four UTF-8 bytes, so on its lines a column, a UTF-16 offset,
-- and a byte offset are three different numbers.
--
-- The suite reads this file as it is (LF line ends, no byte-order mark) and
-- writes three more copies of it to a scratch directory, with CR LF line
-- ends, with a leading byte-order mark, and with both: Agda places the holes
-- of all four at the same lines and columns, and the server's patch must
-- too.  It imports nothing, so it checks under any flags.

module PatchUnits where

data Nat : Set where
  zero : Nat
  suc  : Nat → Nat

𝑨 : Nat
𝑨 = zero

f : Nat → Nat → Nat
f x y = x

-- A hole after the glyph.
g : Nat
g = f 𝑨 {!!}

-- A question-mark hole after the glyph.
h : Nat
h = f 𝑨 ?

-- A hole with contents before the glyph: its span is ten characters.
k : Nat
k = f {! zero !} 𝑨

-- Two question-mark holes after two glyphs.  The second one's column, read
-- as a count of UTF-16 units, is the first one's place, where the same text
-- sits: a client that counts in the wrong unit patches the wrong hole, and
-- the text it finds there does not warn it.
q : Nat
q = f 𝑨 (f 𝑨 (f ? ?))
