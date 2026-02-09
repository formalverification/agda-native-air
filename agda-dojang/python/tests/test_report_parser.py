"""
test_report_parser.py

File: agda-jang/python/tests/test_report_parser.py

What:
  Unit tests for the log parser that reads AgdaJang’s reporting macros output.
  The macros (`applyReport⟨_⟩`, `applySolveReport⟨_⟩`) emit a BEGIN/END block
  to stderr with lines like:
      AGDAJANG_GOAL:0:visible: Nat

Why:
  - This is the backbone of dataset creation and CLI UX: we rely on a stable
    parse to turn Agda's subgoal report into machine-readable JSON.
  - It also guards against regressions if we tweak markers or whitespace.

How to run:
  nix develop
  cd agda-jang
  PYTHONPATH=python pytest -q

Expected:
  - `has_markers` detects BEGIN/END.
  - `parse_marked_report` extracts (index, visibility, type) triples.
"""

from tools.report_parser import parse_marked_report, has_markers

_SAMPLE = """Checking TrySandbox (...)
TrySandbox.agda:10.5-23: error: [GenericDocError]
AGDAJANG_SUBGOALS_BEGIN
AGDAJANG_GOAL:0:visible: Nat
AGDAJANG_GOAL:1:visible: Nat
AGDAJANG_SUBGOALS_END
when checking that the expression
unquote applyReport⟨ quoteTerm _+_ ⟩ has type Nat
"""

def test_has_markers_true():
    assert has_markers(_SAMPLE)

def test_parse_marked_report_basic():
    doc = parse_marked_report(_SAMPLE, source="applyReport")
    assert doc["kind"] == "subgoal-report"
    assert doc["source"] == "applyReport"
    goals = doc["goals"]
    assert len(goals) == 2
    assert goals[0] == {"index": 0, "visibility": "visible", "type": "Nat"}
    assert goals[1] == {"index": 1, "visibility": "visible", "type": "Nat"}
    # keep raw stderr for debugging
    assert "stderr" in doc["raw"]
