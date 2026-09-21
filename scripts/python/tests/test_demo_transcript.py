"""
Tests for `scripts/python/demo/transcript.py`.

File: scripts/python/tests/test_demo_transcript.py

Description
-----------
Reading a `stream-json` transcript is mostly a filtering problem, and the
filter's mistakes are silent: a dropped turn still renders, a mis-attributed
thinking estimate still prints a number.  So the cases below pin the three
readings that a change could get wrong without failing anything else.

+  A turn is not a record.  The client emits one record per content block, so
   a turn that issues two calls arrives as two `assistant` records; what ends
   a turn is the `user` record carrying the answers.
+  A thinking estimate belongs to a passage only if the estimate stream and
   the thinking blocks agree on how many passages there were.  The archive
   has a real case where they do not (Sonnet's `algebras-kernels-ker-con`:
   five blocks, four estimate runs), and there the page must say nothing.
+  A headline quotes named fields.  An error field is always among them, so
   no abbreviation can hide a failed answer behind a shorter one.

The last case runs over the committed archive itself, which is what makes it
a check on the page and not only on the code.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_demo_transcript.py`
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

from scripts.python.demo.paths import PathMap
from scripts.python.demo.transcript import (
    answers_of,
    display_name,
    headline_of,
    load,
    read_session,
    steps_of,
    thinking_runs,
    totals_of,
    turn_index,
)

REPO = Path(__file__).resolve().parents[3]
ARCHIVE = REPO / "reports" / "agent-bench"

PMAP = PathMap(repo_root="/r", work_dir="/r/w")


def _assistant(*blocks: Dict[str, Any]) -> Dict[str, Any]:
    return {"type": "assistant", "message": {"role": "assistant",
                                             "content": list(blocks)}}


def _user(*blocks: Dict[str, Any]) -> Dict[str, Any]:
    return {"type": "user", "message": {"role": "user",
                                        "content": list(blocks)}}


def _call(call_id: str, name: str, **kwargs: Any) -> Dict[str, Any]:
    return {"type": "tool_use", "id": call_id, "name": name, "input": kwargs}


def _answer(call_id: str, text: str, error: bool = False) -> Dict[str, Any]:
    return {"type": "tool_result", "tool_use_id": call_id,
            "is_error": error, "content": [{"type": "text", "text": text}]}


def _tokens(n: int) -> Dict[str, Any]:
    return {"type": "system", "subtype": "thinking_tokens",
            "estimated_tokens": n}


# ---------------------------------------------------------------- turns

def test_a_turn_survives_the_records_it_is_split_across() -> None:
    records = [
        {"type": "system", "subtype": "init", "cwd": "/r/w"},
        _assistant({"type": "thinking", "thinking": ""}),
        _assistant(_call("a", "mcp__agda__get_goal")),
        _assistant(_call("b", "mcp__agda__type_of")),
        _user(_answer("a", "{}")),
        _user(_answer("b", "{}")),
        _assistant(_call("c", "mcp__agda__check_file")),
        _user(_answer("c", "{}")),
    ]
    assert turn_index(records) == [0, 1, 1, 1, 1, 1, 2, 2]
    calls = [s for s in steps_of(records, PMAP) if s.kind == "call"]
    assert [s.in_turn for s in calls] == [2, 2, 1]


def test_a_thinking_estimate_between_two_turns_does_not_join_them() -> None:
    records = [
        _assistant(_call("a", "Read")),
        _user(_answer("a", "ok")),
        _tokens(50), _tokens(150),
        _assistant(_call("b", "Edit")),
        _user(_answer("b", "ok")),
    ]
    calls = [s for s in steps_of(records, PMAP) if s.kind == "call"]
    assert [s.in_turn for s in calls] == [1, 1]


# ------------------------------------------------------------- thinking

def test_thinking_runs_splits_on_the_drop() -> None:
    stream = [50, 100, 250, 50, 100, 155, 50, 100, 1100]
    records = [_tokens(n) for n in stream]
    assert thinking_runs(records) == (250, 155, 1100)


def test_a_passage_keeps_its_estimate_when_the_counts_agree() -> None:
    records = [
        _tokens(50), _tokens(250),
        _assistant({"type": "thinking", "thinking": ""}),
        _tokens(50), _tokens(900),
        _assistant({"type": "thinking", "thinking": ""}),
    ]
    thoughts = [s for s in steps_of(records, PMAP) if s.kind == "thinking"]
    assert [s.tokens for s in thoughts] == [250, 900]


def test_a_passage_says_nothing_when_the_counts_disagree() -> None:
    # Two blocks, one estimate run: the archive's Sonnet ker-con subject is
    # exactly this shape.  Attaching 250 to the first would be a guess.
    records = [
        _tokens(50), _tokens(250),
        _assistant({"type": "thinking", "thinking": ""}),
        _assistant({"type": "thinking", "thinking": ""}),
    ]
    thoughts = [s for s in steps_of(records, PMAP) if s.kind == "thinking"]
    assert [s.tokens for s in thoughts] == [None, None]


# ------------------------------------------------------------- headlines

def test_an_object_answer_quotes_its_named_fields() -> None:
    is_json, headline = headline_of(json.dumps({
        "success": True, "holesCount": 0, "diagnosticsTotal": 2,
        "verdict": {"exitCode": 1}, "diagnostics": ["a", "b"],
        "elapsedMs": 12, "project": {"noise": 1},
    }))
    assert is_json
    pairs = dict(headline)
    assert pairs["success"] == "true"
    assert pairs["verdict.exitCode"] == "1"
    assert pairs["diagnostics"] == "2"
    assert "project" not in pairs


def test_an_error_code_is_always_in_the_headline() -> None:
    _, headline = headline_of(json.dumps({
        "expr": "∘-hom", "scope": "toplevel",
        "error": {"code": "NotInScope", "message": "long\nmessage"},
    }))
    assert ("error.code", "NotInScope") in headline


def test_an_array_answer_reports_its_length() -> None:
    is_json, headline = headline_of(json.dumps([{"a": 1}, {"a": 2}]))
    assert is_json
    assert headline == (("results", "2"),)


def test_a_plain_answer_previews_its_first_line() -> None:
    is_json, headline = headline_of("Definition not found: kercon\nmore")
    assert not is_json
    assert headline == (("", "Definition not found: kercon"),)


def test_a_long_plain_answer_is_marked_where_it_was_cut() -> None:
    _, headline = headline_of("x" * 400)
    assert headline[0][1].endswith("…")
    assert len(headline[0][1]) <= 121


def test_an_object_with_nothing_named_falls_back_to_its_text() -> None:
    _, headline = headline_of(json.dumps({"unheard": "of"}))
    assert headline and headline[0][0] == ""


# ------------------------------------------------------------ the rest

def test_display_name_strips_only_the_server_prefix() -> None:
    assert display_name("mcp__agda__type_of") == "type_of"
    assert display_name("Read") == "Read"


def test_answers_are_paired_by_id_and_carry_the_error_flag() -> None:
    records = [_user(_answer("a", "boom", error=True), _answer("b", "{}"))]
    answers = answers_of(records, PMAP)
    assert answers["a"].is_error and not answers["b"].is_error
    assert answers["b"].is_json


def test_answers_and_arguments_are_normalized() -> None:
    records = [
        _assistant(_call("a", "Read", file_path="/r/w/M.agda")),
        _user(_answer("a", "read /r/w/M.agda")),
    ]
    call = [s for s in steps_of(records, PMAP) if s.kind == "call"][0]
    assert call.args == (("file_path", "<work>/M.agda"),)
    assert call.answer is not None
    assert call.answer.body == "read <work>/M.agda"


def test_totals_come_from_the_result_record() -> None:
    records = [{"type": "result", "num_turns": 10, "total_cost_usd": 0.35,
                "duration_ms": 62671, "terminal_reason": "completed",
                "usage": {"output_tokens_details": {"thinking_tokens": 1768}}}]
    assert totals_of(records) == {
        "turns": 10, "costUsd": 0.35, "wallMs": 62671,
        "terminal": "completed", "thinkingTokens": 1768}


def test_a_transcript_without_an_init_record_is_refused() -> None:
    outcome = read_session([_assistant({"type": "text", "text": "hi"})], {})
    assert outcome.is_err
    assert "init" in str(outcome.unwrap_err())


# --------------------------------------------------- against the archive

def test_the_archive_holds_no_thinking_text() -> None:
    # The page must never present a paraphrase as the model's reasoning, and
    # the reason it shows a marker instead of a passage is that there is no
    # passage: every archived thinking block carries a signature and an empty
    # string.  If a future archive does carry the text, this fails and the
    # page's treatment of thinking has to be revisited on purpose.
    found = 0
    for path in sorted(ARCHIVE.glob("agent-*/subjects/*/transcript.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if '"thinking"' not in line:
                continue
            record = json.loads(line)
            content = (record.get("message") or {}).get("content") or []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "thinking":
                    found += 1
                    assert block.get("thinking") == "", (
                        f"{path} carries thinking text; the page's thinking "
                        "marker assumes there is none")
    assert found > 0, "no thinking blocks found; the glob is wrong"


def test_every_archived_transcript_reads() -> None:
    # The roster can change; the reader must not fall over on any subject of
    # the arms the page quotes.
    subjects = sorted(ARCHIVE.glob("agent-*/subjects/*"))
    assert len(subjects) == 165
    for subject in subjects:
        records = load(subject / "transcript.jsonl")
        assert records.is_ok, str(records.unwrap_err())
        mcp = json.loads((subject / "mcp.json").read_text(encoding="utf-8"))
        session = read_session(records.unwrap(), mcp)
        assert session.is_ok, f"{subject}: {session.unwrap_err()}"
        read = session.unwrap()
        assert read.server_status == "connected"
        assert len(read.tools) == 15
        assert any(step.kind == "call" for step in read.steps)
