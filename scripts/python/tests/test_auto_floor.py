"""
Tests for `scripts/python/auto_floor.py`.

File: scripts/python/tests/test_auto_floor.py

Description
-----------
The floor script's core is pure: the requests each phase sends are a
function of the index, and the rows are a function of the answers.  These
pin the hole line (code before a line comment only), the JSON-RPC batch, the
reading of an answer (JSON inside the text, or prose for a refusal), the
needle filter (only names Agda typed at the hole are passed on), the call
each phase makes, a bound the server would refuse refused up front, a row
for each outcome, every failure named in its row and never read as a
verdict, and the per-tier summary.  The answers below are shaped as
agda-mcp answered them on the benchmark (issue #205), trimmed to the fields
the script reads.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_auto_floor.py`
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from typing import Any, Dict

from scripts.python.auto_floor import (
    Answer,
    Obligation,
    Options,
    answers_of,
    auto_call,
    failed_rows,
    found_term,
    hole_line,
    judge_call,
    nameable_needles,
    needle_calls,
    obligation_of,
    parse_options,
    record_of,
    rpc_input,
    selected,
    summary_of,
)

REPO = Path("/repo")


def options(**kw: Any) -> Options:
    base: Dict[str, Any] = dict(repo=REPO, index=REPO / "i.jsonl", server=REPO / "bin/agda-mcp",
                                out_dir=REPO / "out", run_id="t", hints="none",
                                tiers=None, ids=None, timeout_ms=None)
    base.update(kw)
    return Options(**base)


def ob(oid: str = "comp-x", tier: str = "agda-algebras-composition-v0",
       needles: tuple = ()) -> Obligation:
    return Obligation(id=oid, tier=tier, source="agda-algebras", difficulty="non-obvious",
                      path=REPO / "data/benchmarks" / tier / "obligations/X.agda", needles=needles)


def response(n: int, payload: Any, is_error: bool = False) -> str:
    text = payload if isinstance(payload, str) else json.dumps(payload)
    result: Dict[str, Any] = {"content": [{"type": "text", "text": text}]}
    if is_error:
        result["isError"] = True
    return json.dumps({"jsonrpc": "2.0", "id": n, "result": result})


def test_obligation_of_reads_tier_and_needles() -> None:
    row = {"id": "comp-x", "source": "agda-algebras", "difficulty": "non-obvious",
           "obligation": "data/benchmarks/agda-algebras-composition-v0/obligations/X.agda",
           "tags": ["stratum:composition", "needle:A.f", "needle:B.g"]}
    o = obligation_of(REPO, row)
    assert o.tier == "agda-algebras-composition-v0"
    assert o.needles == ("A.f", "B.g")
    assert o.path == REPO / row["obligation"]


def test_selected_filters_by_tier_and_id() -> None:
    o = ob()
    assert selected(options(), o)
    assert selected(options(tiers=frozenset({o.tier})), o)
    assert not selected(options(tiers=frozenset({"agda-stdlib-v0"})), o)
    assert not selected(options(ids=frozenset({"other"})), o)


def test_hole_line_reads_code_only() -> None:
    src = "-- a {!!} in a comment\nmodule M where\nf : A\nf = {!!} -- the hole\n"
    assert hole_line(src) == 4
    assert hole_line("module M where\n") is None


def test_rpc_input_numbers_calls_after_initialize() -> None:
    lines = [json.loads(ln) for ln in rpc_input([("auto", {"filePath": "/f", "holeIndex": 0})]).splitlines()]
    assert [r["id"] for r in lines] == [0, 1]
    assert lines[0]["method"] == "initialize"
    assert lines[1]["params"] == {"name": "auto", "arguments": {"filePath": "/f", "holeIndex": 0}}


def test_answers_of_decodes_json_and_keeps_prose() -> None:
    out = "\n".join([
        json.dumps({"jsonrpc": "2.0", "id": 0, "result": {"instructions": "..."}}),
        response(1, {"outcome": "found", "term": "m , n"}),
        response(2, "timeoutMs 2000 reaches this server's --timeout", is_error=True),
    ])
    got = answers_of(out)
    assert set(got) == {1, 2}
    assert got[1] == Answer(False, {"outcome": "found", "term": "m , n"})
    assert got[2].is_error and isinstance(got[2].body, str)


def test_answers_of_reads_a_cut_line_and_an_rpc_error_as_no_answer_and_a_failure() -> None:
    # A server cut off mid-line must not cost the phase a traceback, and a
    # JSON-RPC error is a failure, not an empty success (PR #230).
    out = "\n".join([
        response(1, {"outcome": "found", "term": "refl"}),
        json.dumps({"jsonrpc": "2.0", "id": 2, "error": {"code": -32602, "message": "bad params"}}),
        '{"jsonrpc":"2.0","id":3,"res',
    ])
    got = answers_of(out)
    assert set(got) == {1, 2}
    assert got[2] == Answer(True, "bad params")


def test_needles_pass_only_when_typed_at_the_hole() -> None:
    a = ob("a", needles=("A.f", "A.g"))
    b = ob("b", needles=("B.h",))
    calls = needle_calls([a, b], {"a": 30, "b": 12})
    assert [c[1]["expr"] for c in calls] == ["A.f", "A.g", "B.h"]
    assert all(c[0] == "type_of" for c in calls) and calls[2][1]["line"] == 12
    got = {1: Answer(False, {"type": "X"}),
           2: Answer(False, {"error": {"stage": "expression", "code": "NotInScope"}}),
           3: Answer(True, "lane timeout")}
    assert nameable_needles([a, b], got) == {"a": ("A.f",), "b": ()}


def test_auto_call_sends_only_what_is_set() -> None:
    o = ob()
    assert auto_call(o, (), None) == ("auto", {"filePath": str(o.path), "holeIndex": 0})
    assert auto_call(o, ("A.f",), 500)[1] == {"filePath": str(o.path), "holeIndex": 0,
                                              "hints": ["A.f"], "timeoutMs": 500}


def test_timeout_outside_the_servers_bounds_is_refused_before_running() -> None:
    # The server refuses each of these on every call, so a run would write a
    # tool failure per row and a summary of 0 solved (measured, PR #230).
    base = ["--server", "bin/agda-mcp", "--run-id", "t"]
    for bad in ("0", "-5", "300000"):
        with pytest.raises(SystemExit) as exit_info:
            parse_options(base + [f"--timeout-ms={bad}"])
        assert exit_info.value.code == 2, bad
    assert parse_options(base + ["--timeout-ms", "299999"]).timeout_ms == 299999
    assert parse_options(base).timeout_ms is None


def test_found_term_and_its_judgment() -> None:
    assert found_term(Answer(False, {"outcome": "found", "term": "refl"})) == "refl"
    assert found_term(Answer(False, {"outcome": "no-solution", "message": "No solution found"})) is None
    assert found_term(Answer(True, "refused")) is None
    assert found_term(None) is None
    assert judge_call(ob(), "a , b")[1]["candidate"] == "(a , b)"


def test_record_of_each_outcome() -> None:
    o = ob(needles=("A.f", "A.g"))
    solved = record_of(o, ("A.f",), Answer(False, {"outcome": "found", "term": "A.f x", "searchMs": 4}),
                       Answer(False, {"status": "ok"}))
    assert solved["solved"] and solved["fillHole"] == "ok"
    assert solved["unnamedHints"] == ["A.g"]
    refused = record_of(o, (), Answer(False, {"outcome": "found", "term": "t"}),
                        Answer(False, {"status": "type_error"}))
    assert not refused["solved"] and refused["fillHole"] == "type_error"
    oos = record_of(o, (), Answer(False, {"outcome": "out-of-scope",
                                          "error": {"stage": "term", "code": "NotInScope",
                                                    "message": "Not in scope:\n  A.B.f at 1.4-9"}}), None)
    assert (oos["outcome"], oos["errorCode"], oos["fillHole"]) == ("out-of-scope", "NotInScope", None)
    assert oos["errorMessage"].startswith("Not in scope:")
    assert solved["errorMessage"] is None
    failed = record_of(o, (), Answer(True, "the lane timed out"), None)
    assert failed["outcome"] == "tool-failure" and "timed out" in failed["failure"]


def test_record_of_names_every_failure_and_never_reads_one_as_a_verdict() -> None:
    # Measured before the fix: each of these rows carried no reason, and the
    # two judge failures read as a found term the judge had refused (PR #230).
    o = ob()
    found = Answer(False, {"outcome": "found", "term": "refl"})
    missing = record_of(o, (), None, None)
    assert missing["outcome"] == "tool-failure" and "no answer" in missing["failure"]
    shapeless = record_of(o, (), Answer(False, {"lane": {}}), None)
    assert shapeless["outcome"] == "tool-failure" and "no outcome" in shapeless["failure"]
    refused = record_of(o, (), found, Answer(True, "Invalid arguments: no hole"))
    assert (refused["outcome"], refused["fillHole"], refused["solved"]) == ("found", None, False)
    assert refused["judgeFailure"] == "Invalid arguments: no hole"
    unanswered = record_of(o, (), found, None)
    assert "no answer" in unanswered["judgeFailure"]
    judged = record_of(o, (), found, Answer(False, {"status": "type_error"}))
    assert "judgeFailure" not in judged and "failure" not in judged
    nothing_to_judge = record_of(o, (), Answer(False, {"outcome": "no-solution"}), None)
    assert "judgeFailure" not in nothing_to_judge
    assert failed_rows([missing, refused, unanswered, judged, nothing_to_judge]) == ["comp-x"] * 3


def test_summary_counts_per_tier_in_order() -> None:
    rows = [
        {"tier": "agda-stdlib-v0", "solved": True, "outcome": "found"},
        {"tier": "agda-stdlib-v0", "solved": False, "outcome": "no-solution"},
        {"tier": "agda-algebras-v0", "solved": False, "outcome": "out-of-scope"},
        {"id": "x4", "tier": "agda-algebras-v0", "solved": False, "outcome": "found", "judgeFailure": "no answer"},
    ]
    s = summary_of(options(), rows, "bin/agda-mcp")
    assert list(s["perTier"]) == ["agda-stdlib-v0", "agda-algebras-v0"]
    assert s["perTier"]["agda-stdlib-v0"] == {"solved": 1, "total": 2, "unjudged": 0,
                                              "outcomes": {"found": 1, "no-solution": 1}}
    assert s["perTier"]["agda-algebras-v0"]["unjudged"] == 1
    assert s["unmeasured"] == ["x4"]
    assert s["total"]["solved"] == 1 and s["total"]["total"] == 4
    assert s["config"]["server"] == "bin/agda-mcp" and "--safe" in s["config"]["judgeFlags"]
