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
    assert goals[0]["index"] == 0 and goals[0]["visibility"] == "visible" and goals[0]["type"] == "Nat"
    assert goals[1]["index"] == 1 and goals[1]["visibility"] == "visible" and goals[1]["type"] == "Nat"
    # keep a raw copy for debugging
    assert "stderr" in doc["raw"]
