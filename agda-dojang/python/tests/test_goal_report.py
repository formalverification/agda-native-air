"""
test_goal_report.py

File: agda-dojang/python/tests/test_goal_report.py

What:
  Unit tests for `utils/goal_report.py`, which reads the goal/context request
  block that `AgdaDojang.Debug.reportGoalCtx` writes between the markers
  AGDADOJANG_REQ_BEGIN / AGDADOJANG_REQ_END.

Why:
  The proof-completion evaluator's whole first step is this parse: whatever it
  reads here becomes the policy request.  These tests pin the two properties
  that have actually broken in practice, namely that a goal wrapped across
  several lines is rejoined, and that a dependent binder keeps its declared
  type rather than its own name.

Provenance:
  Carried over from `test_report_parser.py` when the legacy Python bridge
  retired (issue #109).  The two tests that covered the separate
  AGDADOJANG_SUBGOALS report did not come along: their subject,
  `report_parser.parse_marked_report`, had `dojang_try.py` as its only caller
  and retired with it.

How to run:
  nix develop
  cd agda-dojang
  PYTHONPATH=python pytest -q python/tests/test_goal_report.py
"""

import re

from utils.goal_report import extract_policy_request_from_output


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


def test_extract_policy_request_returns_none_without_markers():
    assert extract_policy_request_from_output("Checking Foo (/tmp/Foo.agda).\n") is None
