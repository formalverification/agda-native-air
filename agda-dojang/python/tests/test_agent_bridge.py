#!/usr/bin/env python3

"""
test_agent_bridge.py

File: agda-dojang/python/tests/test_agent_bridge.py

Description:
    Tests for the agent bridge utilities in tools/agent_bridge.py.
    Tests the "only unsolved metas" logic and the position extraction,
    critical to incremental-hole workflow.
"""

from __future__ import annotations

from tools.agent_bridge import HoleSpan, _only_unsolved_metas, _unsolved_meta_positions, _filled_hole_still_unsolved

_SAMPLE = """Checking Foo (/tmp/Foo.agda).
/tmp/Foo.agda:90.26-93.26: error: [UnsolvedInteractionMetas]
Unsolved interaction metas at the following locations:
  /tmp/Foo.agda:90.26-30
  /tmp/Foo.agda:93.22-26
"""

def test_unsolved_meta_positions_parsed():
    pos = _unsolved_meta_positions(_SAMPLE)
    assert (90, 26) in pos
    assert (93, 22) in pos

def test_only_unsolved_metas_true():
    assert _only_unsolved_metas(_SAMPLE)

def test_filled_hole_still_unsolved_detected():
    hole = HoleSpan(start=0, end=0, line=90, col=26)
    assert _filled_hole_still_unsolved(hole, _SAMPLE)
