"""
test_report_parser.py

File: agda-dojang/python/tests/test_report_parser.py

What:
  Unit tests for the log parser that reads AgdaDojang’s reporting macros output.
  The macros (`applyReport⟨_⟩`, `applySolveReport⟨_⟩`) emit a BEGIN/END block
  to stderr with lines like:
      AGDADOJANG_GOAL:0:visible: Nat

Why:
  - This is the backbone of dataset creation and CLI UX: we rely on a stable
    parse to turn Agda's subgoal report into machine-readable JSON.
  - It also guards against regressions if we tweak markers or whitespace.

How to run:
  nix develop
  cd agda-dojang
  PYTHONPATH=python pytest -q

Expected:
  - `has_markers` detects BEGIN/END.
  - `parse_marked_report` extracts (index, visibility, type) triples.
"""

import re
from tools.report_parser import parse_marked_report, has_markers, extract_policy_request_from_output

_SAMPLE = """Checking TrySandbox (...)
TrySandbox.agda:10.5-23: error: [GenericDocError]
AGDADOJANG_SUBGOALS_BEGIN
AGDADOJANG_GOAL:0:visible: Nat
AGDADOJANG_GOAL:1:visible: Nat
AGDADOJANG_SUBGOALS_END
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


def test_extract_policy_request_line_protocol_multiline():
    out = """
noise
AGDADOJANG_REQ_BEGIN
AGDADOJANG_GOAL: ¬ (x ∧ y) ≈
  ¬ x ∨ ¬ y
AGDADOJANG_CTX_BEGIN
AGDADOJANG_CTX:0:visible:y: Bool
AGDADOJANG_CTX:1:visible:x: Bool
AGDADOJANG_CTX_END
AGDADOJANG_REQ_END
more noise
"""
    req = extract_policy_request_from_output(out)
    assert req is not None
    assert "goal" in req and "context" in req

    goal = req["goal"]
    assert "¬" in goal
    assert ("∨" in goal) or ("_∨_" in goal)
    assert ("∧" in goal) or ("_∧_" in goal)

    ctx = req["context"]
    # accept either order
    by_name = {e["name"]: e["type"] for e in ctx}
    assert set(by_name.keys()) == {"x", "y"}
    assert re.search(r"\bBool\b", by_name["x"])
    assert re.search(r"\bBool\b", by_name["y"])


def test_extract_policy_request_fixture_lambda_ctx_type_is_A():
    """
    Regression guard for dependent binders:
      foo : {A : Set} → A → A
      foo = λ x → {!!}

    The reported context must include x : A (not x : x).
    """
    out = """
noise
AGDADOJANG_REQ_BEGIN
AGDADOJANG_GOAL: A
AGDADOJANG_CTX_BEGIN
AGDADOJANG_CTX:0:visible:x: A
AGDADOJANG_CTX:1:hidden:A: Set₀
AGDADOJANG_REQ_END
more noise
"""
    req = extract_policy_request_from_output(out)
    assert req is not None
    by_name = {e["name"]: e["type"] for e in req["context"]}
    assert by_name["x"].strip() == "A"
    assert by_name["A"].strip().startswith("Set")
