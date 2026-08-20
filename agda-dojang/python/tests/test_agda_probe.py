#!/usr/bin/env python3

"""
test_agda_probe.py

File: agda-dojang/python/tests/test_agda_probe.py

Description:
    Tests for `utils/agda_probe.py`, specifically the verdict-reading half:
    the "only unsolved metas" judgement and the position extraction it rests on.
    These are what keep a candidate that merely defers the goal (`_`, `?`) from
    being scored as a solution, so they are critical to the incremental-hole
    workflow.

Provenance:
    Carried over from `test_agent_bridge.py` when the legacy Python bridge
    retired (issue #109); the subject moved from `tools/agent_bridge.py` to
    `utils/agda_probe.py` and the names it tests are public there.  The tests
    need no Agda, so they belong to the pure unit-test lane rather than the
    integration lane that used to run them.
"""

from __future__ import annotations

from utils.agda_probe import (
    HoleSpan,
    filled_hole_still_unsolved,
    only_unsolved_metas,
    unsolved_meta_positions,
)

_SAMPLE = """Checking Foo (/tmp/Foo.agda).
/tmp/Foo.agda:90.26-93.26: error: [UnsolvedInteractionMetas]
Unsolved interaction metas at the following locations:
  /tmp/Foo.agda:90.26-30
  /tmp/Foo.agda:93.22-26
"""

def test_unsolved_meta_positions_parsed():
    pos = unsolved_meta_positions(_SAMPLE)
    assert (90, 26) in pos
    assert (93, 22) in pos

def test_only_unsolved_metas_true():
    assert only_unsolved_metas(_SAMPLE)

def test_filled_hole_still_unsolved_detected():
    hole = HoleSpan(start=0, end=0, line=90, col=26)
    assert filled_hole_still_unsolved(hole, _SAMPLE)

def test_only_unsolved_metas_false_on_a_real_type_error():
    out = (
        "Checking Foo (/tmp/Foo.agda).\n"
        "/tmp/Foo.agda:3.7-11: error: [UnequalTerms]\n"
        "true != zero of type Nat\n"
    )
    assert not only_unsolved_metas(out)
