-- | TimeoutFixture.agda
--
-- File: agda-native-air/agda-mcp/test/resources/TimeoutFixture.agda
--
-- Description:
--   Fixture for the tier-1 timeout tests (issue #77).
--
--   Those tests run fill_hole against `fake-slow-agda.sh` rather than a real
--   Agda, so nothing here is ever typechecked by the suite; what matters is that
--   the file has exactly one hole — the one in `wanted` — for fill_hole to
--   patch, and that its bytes are stable so a timed-out call can be shown to
--   restore it exactly.  No comment in this file may spell out the hole token
--   literally: the scanner does not parse comments, so a spelled-out token
--   would be indexed as a second hole and fill_hole at index 0 would patch
--   this header instead of `wanted` (a Copilot review catch on PR #89).
--
--   It is deliberately a *separate* fixture from TwoHoles.agda: that one backs
--   the fill_hole verdict tests (tier 2c), and keeping the byte-exactness
--   assertion on its own file means a failure points at one cause rather than
--   two.  The module is self-contained (Agda.Builtin only) so it still
--   typechecks if anyone points a real Agda at it.

module TimeoutFixture where

open import Agda.Builtin.Nat

wanted : Nat
wanted = {!!}
