#!/usr/bin/env python3
"""
test_policy_contract.py

File: agda-dojang/python/tests/test_policy_fixture.py

Description:
    Tests for the policy fixture defined in tools/policy_fixture.py, ensuring it
    adheres to the contract defined in policy_contract.py.  Locks down the "policy
    recognizes goal despite printing differences" behavior.
"""

from __future__ import annotations

from tools.policy_fixture import propose_terms, CtxEntry

def _ctx_xy_bool():
    return [CtxEntry(name="x", type="Bool"), CtxEntry(name="y", type="Bool")]

def test_demorgan1_unqualified_goal_prefers_oracle():
    goal = "¬ (x ∧ y) ≈ ¬ x ∨ ¬ y"
    cands = propose_terms(goal, _ctx_xy_bool(), req={"goal": goal, "context": []}, k=5)
    terms = [c["term"] for c in cands]
    assert terms, "expected at least one candidate"
    assert terms[0].startswith("oracle-deMorgan₁"), f"top term was {terms[0]!r}"
    assert "x" in terms[0] and "y" in terms[0]

def test_demorgan1_qualified_goal_still_prefers_oracle():
    goal = "Data.Bool.Base.not (x Data.Bool.Base.∧ y) ≈ Data.Bool.Base.not x Data.Bool.Base.∨ ¬ y"
    cands = propose_terms(goal, _ctx_xy_bool(), req={"goal": goal, "context": []}, k=5)
    terms = [c["term"] for c in cands]
    assert terms, "expected at least one candidate"
    assert terms[0].startswith("oracle-deMorgan₁"), f"top term was {terms[0]!r}"

def test_policy_matches_qualified_demorgan1_goal():
    goal = "Data.Bool.Base.not (x Data.Bool.Base.∧ y) ≈ Data.Bool.Base.not x Data.Bool.Base.∨ ¬ y"
    ctx = [CtxEntry("x", "Bool"), CtxEntry("y", "Bool")]
    cands = propose_terms(goal, ctx, req={"goal": goal, "context": []}, k=5)
    terms = [c["term"] for c in cands]
    assert any(t.startswith("oracle-deMorgan₁") or t.startswith("deMorgan₁") for t in terms), terms

def test_bottom_top_goal_emits_oracle_then_stdlib():
    goal = "¬ ⊥ ≈ ⊤"
    cands = propose_terms(goal, [], req={"goal": goal, "context": []}, k=5)
    terms = [c["term"] for c in cands]
    assert "oracle-¬⊥≈⊤" in terms
    assert "⊥≉⊤" in terms
