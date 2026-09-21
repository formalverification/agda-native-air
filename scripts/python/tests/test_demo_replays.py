"""
Tests for `scripts/python/demo/replays.py` and `build_data.py`.

File: scripts/python/tests/test_demo_replays.py

Description
-----------
These run the real build over the committed archive, because the properties
worth pinning are properties of what gets published.

+  No absolute path reaches the page.  `paths.check_clean` is asserted on the
   encoded output of every replay, not only on the transcript it came from:
   `outcome.json` carries the machine's paths too, in the isolation audit's
   record of a refused Read.
+  Every verdict on the page is the archive's.  Each replay's verdict fields
   are compared with the `outcome.json` they were read from, so no later
   convenience can turn a restatement into a solve on the way to the HTML.
+  The four contrasts the page is built around still hold.  If the archive is
   ever regenerated and `algebras-kernels-ker-con` stops being a solve beside
   a restatement, the page's claim about it becomes false, and this is where
   that is found out.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_demo_replays.py`
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

from scripts.python.demo.build_data import ARCHIVE, INDEX, manifest, run
from scripts.python.demo.paths import check_clean
from scripts.python.demo.replays import (
    ROSTER,
    index_rows,
    marked_diff,
    tag_value,
    tag_values,
)

REPO = Path(__file__).resolve().parents[3]


# --------------------------------------------------------------- pure

def test_marked_diff_marks_only_what_changed() -> None:
    before = "a\nb\nc"
    after = "a\nB\nc\nd"
    marked = marked_diff(before, after)
    assert (" ", "a") in marked
    assert ("-", "b") in marked
    assert ("+", "B") in marked
    assert ("+", "d") in marked
    # ndiff's intra-line hint lines would render as noise and are dropped.
    assert all(mark in " +-" for mark, _ in marked)


def test_marked_diff_of_an_unchanged_file_marks_nothing() -> None:
    marked = marked_diff("a\nb", "a\nb")
    assert {mark for mark, _ in marked} == {" "}


def test_tags_are_read_by_prefix() -> None:
    tags = ["stratum:using", "restates:M.f", "target:M.g", "target:M.h"]
    assert tag_value(tags, "restates") == "M.f"
    assert tag_value(tags, "absent") is None
    assert tag_values(tags, "target") == ("M.g", "M.h")


def test_the_manifest_lists_the_roster_in_order() -> None:
    replays = [{"id": f"r{i}", "label": "l", "modelLabel": "m",
                "subject": "s", "run": "x", "verdict": {"kind": "solved"}}
               for i in range(3)]
    listed = manifest(replays)["replays"]
    assert [entry["file"] for entry in listed] == \
        ["r0.json", "r1.json", "r2.json"]


# --------------------------------------------------- against the archive

def _built(tmp_path: Path) -> Dict[str, Dict[str, Any]]:
    outcome = run(REPO, tmp_path)
    assert outcome.is_ok, str(outcome.unwrap_err())
    return {path.stem: json.loads(path.read_text(encoding="utf-8"))
            for path in tmp_path.glob("*.json")}


def test_the_build_writes_one_file_per_replay_and_the_table(tmp_path: Path) -> None:
    built = _built(tmp_path)
    assert len(built) == len(ROSTER) + 2          # + manifest and numbers
    listed = built["manifest"]["replays"]
    assert [entry["id"] for entry in listed] == \
        [f"{choice.run}--{choice.subject}" for choice in ROSTER]
    for entry in listed:
        assert entry["id"] in built


def test_no_absolute_path_reaches_the_page(tmp_path: Path) -> None:
    for name, data in _built(tmp_path).items():
        encoded = json.dumps(data, ensure_ascii=False)
        problem = check_clean(encoded)
        assert problem.is_ok, f"{name}: {problem.unwrap_err()}"


def test_every_verdict_is_the_archives(tmp_path: Path) -> None:
    built = _built(tmp_path)
    for choice in ROSTER:
        replay = built[f"{choice.run}--{choice.subject}"]
        outcome = json.loads(
            (REPO / ARCHIVE / choice.run / "subjects" / choice.subject
             / "outcome.json").read_text(encoding="utf-8"))
        verdict = replay["verdict"]
        assert verdict["solved"] == bool(outcome["solved"])
        assert verdict["restated"] == bool(outcome["restated"])
        assert verdict["gate"] == outcome.get("gate")
        assert verdict["turns"] == outcome["turns"]
        assert verdict["toolCalls"] == outcome["toolCallsTotal"]
        assert verdict["agdaExit"] == outcome["agdaExit"]
        assert verdict["restatementEvidence"] == \
            (outcome.get("restatementEvidence") or [])


def test_the_final_file_on_the_page_is_the_one_the_judge_read(tmp_path: Path) -> None:
    built = _built(tmp_path)
    for choice in ROSTER:
        replay = built[f"{choice.run}--{choice.subject}"]
        on_disk = (REPO / replay["final"]["path"]).read_text(encoding="utf-8")
        assert replay["final"]["text"] == on_disk
        obligation = (REPO / replay["obligation"]["path"]).read_text(
            encoding="utf-8")
        assert replay["obligation"]["text"] == obligation
        # The marked listing is the diff of those two and nothing else.
        assert [tuple(pair) for pair in replay["final"]["marked"]] == \
            list(marked_diff(obligation, on_disk))


def test_each_replay_has_an_exchange_with_an_answer(tmp_path: Path) -> None:
    for choice in ROSTER:
        replay = _built(tmp_path)[f"{choice.run}--{choice.subject}"]
        calls = [s for s in replay["session"]["steps"] if s["kind"] == "call"]
        assert calls, choice.subject
        assert all(call["answer"] is not None for call in calls)
        # Every session ends on a check the server answered.
        assert calls[-1]["display"] == "check_file"
        assert calls[-1]["answer"]["headline"][0] == ["success", "true"]
        assert replay["session"]["serverStatus"] == "connected"
        # The call count the page shows is the judge's own tally.
        assert len(calls) == replay["verdict"]["toolCalls"]


def test_the_flagship_contrast_still_holds(tmp_path: Path) -> None:
    # The page's central claim: one obligation, the same thirteen tools, two
    # verdicts.  If the archive ever stops saying that, the page is wrong.
    built = _built(tmp_path)
    opus = built["agent-opus5-1--algebras-kernels-ker-con"]
    sonnet = built["agent-sonnet5-1--algebras-kernels-ker-con"]
    assert opus["obligation"]["path"] == sonnet["obligation"]["path"]
    assert opus["verdict"]["kind"] == "solved"
    assert sonnet["verdict"]["kind"] == "restated"
    assert sonnet["verdict"]["agdaExit"] == 0
    assert sonnet["verdict"]["restatementEvidence"] == \
        ["ref Setoid.Homomorphisms.Kernels.kercon"]
    assert "kercon h" in sonnet["final"]["text"]
    assert "mkcon" in opus["final"]["text"]


def test_the_gate_contrast_still_holds(tmp_path: Path) -> None:
    # Both arms needed `trans`; the two final files differ by one import
    # line, and that line is the whole difference between a solve and a gate.
    built = _built(tmp_path)
    opus = built["agent-opus5-1--stdlib-nat-mul-comm"]
    sonnet = built["agent-sonnet5-1--stdlib-nat-mul-comm"]
    assert opus["verdict"]["kind"] == "solved"
    assert opus["verdict"]["addedImports"] == [
        "open import Relation.Binary.PropositionalEquality using ( trans )"]
    assert sonnet["verdict"]["kind"] == "gate"
    assert sonnet["verdict"]["gate"] == "preservation"
    assert sonnet["verdict"]["agdaExit"] == 0
    assert sonnet["verdict"]["addedImports"] == []
    added = [text for mark, text in marked_diff(opus["final"]["text"],
                                                sonnet["final"]["text"])
             if mark == "+"]
    assert any("; trans )" in line for line in added)


def test_the_composition_contrast_still_holds(tmp_path: Path) -> None:
    # A wholesale row solved through two answers that were errors: an
    # `exports_of` on a module not in scope, and a `type_of` whose NotInScope
    # answer suggested the name the proof ends up using.
    replay = _built(tmp_path)[
        "agent-opus5-1--algebras-subalgebras-sub-trans-iso"]
    assert replay["verdict"]["kind"] == "solved"
    assert replay["obligation"]["stratum"] == "agda-algebras/wholesale"
    calls = [s for s in replay["session"]["steps"] if s["kind"] == "call"]
    not_in_scope = [call for call in calls
                    if ["error.code", "NotInScope"]
                    in call["answer"]["headline"]]
    assert {call["display"] for call in not_in_scope} == \
        {"exports_of", "type_of"}
    suggesting = [call for call in not_in_scope
                  if "⊙-hom" in call["answer"]["body"]]
    assert suggesting, "the suggestion the session acted on is gone"
    assert "⊙-hom" in replay["final"]["text"]


def test_the_index_row_of_every_replay_exists() -> None:
    rows = index_rows(REPO / INDEX)
    assert rows.is_ok
    known = rows.unwrap()
    for choice in ROSTER:
        assert choice.subject in known
