"""
Tests for `scripts/python/demo/needles.py` and the composition table of
`scripts/python/demo/numbers.py` (Issue #224).

File: scripts/python/tests/test_demo_needles.py

Description
-----------
The demo page carries the composition tier (Issue #160): a table ADR 0001
§ 9 states, and where each needle of each row first appeared in each
session.  Three kinds of case pin it, as the mined tables' are pinned in
`test_demo_numbers.py`.

+  The rule.  `needles` ports `needle-source.py` from the sweeps skill, the
   script the guide's § 4.7 was written from.  Synthetic transcripts pin the
   rule itself (a name bounded by Agda's delimiters, the first event
   deciding, a search before a name recorded), and the committed archive
   pins the port: over all six arms it gives the per-arm figures the skill
   printed when this was written, and the figures the guide and the ADR
   quote.
+  The table.  It is found by its caption and compared cell by cell with
   the ADR, its run row holds each column to its arm, and its needle row's
   label carries the tier's needle count.
+  The refusals.  A caption moved off its table, a wrong cell, a column
   whose run is another arm, a composition row with an original or a
   `restates:` tag: each is an error naming what is wrong, never a page.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_demo_needles.py`
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List

import pytest

from scripts.python.demo import needles
from scripts.python.demo.numbers import ADR as ADR_REL
from scripts.python.demo.numbers import ARCHIVE as ARCHIVE_REL
from scripts.python.demo.numbers import (
    COMPOSITION,
    COMPOSITION_CAPTION,
    COMPOSITION_README,
    COMPOSITION_RUNS,
    EVERY_RUN,
    build,
    composition_table,
    loop_sweeps,
    main,
    usd,
    validate,
)

REPO = Path(__file__).resolve().parents[3]
ARCHIVE = REPO / ARCHIVE_REL
ADR = REPO / ADR_REL


# --------------------------------------------------------------- the rule

def _call(id_: str, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    return {"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": id_, "name": name, "input": arguments}]}}


def _answer(id_: str, text: str) -> Dict[str, Any]:
    return {"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": id_, "content": text}]}}


def _said(text: str) -> Dict[str, Any]:
    return {"type": "assistant", "message": {"content": [
        {"type": "text", "text": text}]}}


def test_a_needle_is_named_by_its_last_component_between_delimiters() -> None:
    needle = "Classical.Properties.Lattice.Lattice-Order.≤-trans"
    assert needles.short_name(needle) == "≤-trans"
    assert needles.mentions(needle, "≤-trans x≤y∨z (∨-least y≤w z≤w)")
    assert needles.mentions(needle, "using ( _≤_ ; ≤-refl ; ≤-trans )")
    assert needles.mentions(needle, "Lattice-Order.≤-trans 𝑳")
    # A neighbor is not the needle, and neither is a longer name.
    assert not needles.mentions(needle, "using ( _≤_ ; ≤-refl )")
    assert not needles.mentions(needle, "≤-trans′ x")
    assert not needles.mentions(needle, "_≤-trans_")


def test_the_first_event_that_names_a_needle_decides() -> None:
    records = [
        _said("reading the file"),
        _call("a", "mcp__agda__exports_of", {"module": "Lattice-Order"}),
        _answer("a", '{"exports":[{"name":"≤-trans"},{"name":"∨-least"}]}'),
        _said("so ∨-least and then ≤-trans"),
        _call("b", "mcp__agda__search_by_name", {"query": "⨅-≤"}),
        _answer("b", "[]"),
    ]
    found = {s.name: s for s in needles.sources(
        records, ["M.≤-trans", "M.∨-least", "M.⨅-≤", "M.absent"],
        final="f = ≤-trans p (∨-least q r)")}
    assert (found["≤-trans"].origin, found["≤-trans"].label,
            found["≤-trans"].call) == (needles.ANSWER, "exports_of", 1)
    assert found["∨-least"].used and found["≤-trans"].used
    # Named in a call before any answer showed it: the session's own, with
    # the search before it recorded.
    assert (found["⨅-≤"].origin, found["⨅-≤"].label, found["⨅-≤"].call,
            found["⨅-≤"].searched) == (needles.SUBJECT, "search_by_name", 2,
                                       True)
    assert not found["⨅-≤"].used
    assert (found["absent"].origin, found["absent"].call) == \
        (needles.NEVER, None)


def test_a_name_before_any_search_is_recorded_as_such() -> None:
    records = [_said("I will use ≤-trans here"),
               _call("a", "mcp__agda__search_by_name", {"query": "x"})]
    found = needles.sources(records, ["M.≤-trans"], final="")[0]
    assert (found.origin, found.label, found.searched) == \
        (needles.SUBJECT, "text", False)


def test_a_read_is_located_when_definition_of_named_its_file() -> None:
    path = "/nix/store/x-agda-algebras/src/Classical/Congruences.lagda.md"
    records = [
        _call("a", "mcp__agda__definition_of", {"name": "normalOf"}),
        _answer("a", json.dumps({"definitions": [{"file": path}]})),
        _call("b", "Read", {"file_path": path, "offset": 380}),
        _answer("b", "596\t  normalOf-mono : ..."),
        _call("c", "Read", {"file_path": "/elsewhere/Other.agda"}),
        _answer("c", "12\t  ≤ⁿ-trans : ..."),
    ]
    found = {s.name: s for s in needles.sources(
        records, ["M.normalOf-mono", "M.≤ⁿ-trans"], final="")}
    assert found["normalOf-mono"].located
    assert not found["≤ⁿ-trans"].located
    assert needles.group(found["normalOf-mono"]) == "read"


def test_a_shell_call_is_labeled_by_its_program() -> None:
    assert needles.label("Bash", {"command": "cd /src && grep -rn x ."}) == \
        "Bash:grep"
    assert needles.label("Bash", {"command": "/usr/bin/cat f"}) == "Bash:cat"
    assert needles.label("mcp__agda__type_of", {}) == "type_of"


# ------------------------------------------------- the port, on the archive

def _traced(run: str) -> List[needles.Source]:
    from scripts.python.demo.transcript import load
    report = json.loads((ARCHIVE / run / "report.json")
                        .read_text(encoding="utf-8"))
    found: List[needles.Source] = []
    for o in report["outcomes"]:
        records = load(ARCHIVE / run / o["transcriptPath"]).unwrap()
        final = (ARCHIVE / run / o["finalPath"]).read_text(encoding="utf-8")
        found += needles.sources(records, needles.needles_of(o["tags"]),
                                 final)
    return found


#: What `needle-source.py` printed for each arm on 2026-09-29, as its
#: closing line groups it (`answer:<label>`, `memory`, `never`).
SKILL: Dict[str, Dict[str, int]] = {
    "comp-opus5-shell-1": {"answer:Bash:cat": 16, "answer:Bash:grep": 10,
                           "never": 3, "answer:Bash:cd": 2,
                           "answer:Read": 2},
    "comp-opus5-mcp-1": {"answer:Read": 19, "answer:exports_of": 8,
                         "never": 5, "memory": 1},
    "comp-opus5-both-1": {"answer:Bash:grep": 11, "answer:Bash:cat": 9,
                          "answer:Bash:sed": 4, "answer:search_by_name": 2,
                          "never": 2, "answer:Read": 2,
                          "answer:exports_of": 2, "answer:Bash:cd": 1},
    "comp-sonnet5-shell-1": {"answer:Read": 18, "answer:Bash:grep": 5,
                             "never": 5, "answer:Bash:cat": 3,
                             "answer:Bash:sed": 2},
    "comp-sonnet5-mcp-1": {"answer:exports_of": 21, "answer:Read": 7,
                           "answer:search_by_name": 2, "memory": 2,
                           "never": 1},
    "comp-sonnet5-both-1": {"answer:Read": 22, "answer:Bash:grep": 7,
                            "never": 3, "answer:type_of": 1},
}


@pytest.fixture(scope="module")
def traced() -> Dict[str, List[needles.Source]]:
    return {run: _traced(run) for run in COMPOSITION_RUNS}


def test_the_port_gives_the_skills_figures_for_every_arm(traced) -> None:
    for run, found in traced.items():
        grouped = Counter(
            f"answer:{s.label}" if s.origin == needles.ANSWER
            else "memory" if s.origin == needles.SUBJECT else "never"
            for s in found)
        assert dict(grouped) == SKILL[run], run


def test_the_figures_the_guide_and_the_adr_quote_are_the_archives(
        traced) -> None:
    # § 4.7 and § 9: all but three needles first appear in a tool answer,
    # and the three were handed to `search_by_name`; Sonnet's `mcp` arm 21
    # of 33 from `exports_of`; Opus's 19 from a Read, 15 of them located.
    subject = [s for found in traced.values() for s in found
               if s.origin == needles.SUBJECT]
    assert len(subject) == 3
    assert {s.label for s in subject} == {"search_by_name"}
    assert {s.name for s in subject} == {"mon→≤", "⨅-≤", "≑-trans"}
    tally = {run: needles.tally(found) for run, found in traced.items()}
    assert tally["comp-sonnet5-mcp-1"]["byLabel"]["exports_of"] == 21
    assert tally["comp-opus5-mcp-1"]["byLabel"]["Read"] == 19
    assert tally["comp-opus5-mcp-1"]["located"] == 15
    assert [tally[run]["byGroup"]["shell"]
            for run in ("comp-opus5-shell-1", "comp-opus5-both-1")] == [28, 25]
    assert [tally[run]["byGroup"]["read"]
            for run in ("comp-sonnet5-shell-1", "comp-sonnet5-both-1")] == \
        [18, 22]
    assert all(t["needles"] == 33 for t in tally.values())


# ------------------------------------------------------------- the table

def test_the_composition_table_agrees_with_adr_0001() -> None:
    checked = validate(ARCHIVE, ADR)
    assert checked.is_ok, str(checked.unwrap_err())
    arms = checked.unwrap().tables.composition
    assert [arm.run for arm in arms] == list(COMPOSITION_RUNS)
    assert [arm.column for arm in arms] == [column for column, _
                                            in COMPOSITION]
    cells = {key: [arm.cell(key) for arm in arms]
             for key in ("checks", "solved", "preservation", "isolation",
                         "needles", "route", "turns", "usd")}
    assert cells == {
        "checks": ["12"] * 6,
        "solved": ["10", "12", "10", "6", "3", "5"],
        "preservation": ["0", "0", "0", "5", "9", "5"],
        "isolation": ["2", "0", "2", "1", "0", "2"],
        "needles": ["20", "20", "22", "25", "32", "26"],
        "route": ["5", "5", "6", "7", "11", "8"],
        "turns": ["130", "128", "148", "157", "206", "179"],
        "usd": ["4.14", "4.05", "4.87", "2.60", "3.55", "3.39"],
    }
    assert checked.unwrap().tables.needles == 33


def test_the_cost_is_rounded_half_up_in_decimal() -> None:
    # The trap: 4.135 is a binary float just below itself.
    assert f"{4.135:.2f}" == "4.13"
    assert (usd(4.135), usd(4.045), usd(2.595), usd(3.548)) == \
        ("4.14", "4.05", "2.60", "3.55")


def _adr_root(tmp_path: Path, text: str) -> Path:
    """A scratch repository with the real archive linked in and `text` as
    ADR 0001."""
    (tmp_path / ARCHIVE_REL).parent.mkdir(parents=True)
    (tmp_path / ARCHIVE_REL).symlink_to(ARCHIVE)
    (tmp_path / ADR_REL).parent.mkdir(parents=True)
    (tmp_path / ADR_REL).write_text(text, encoding="utf-8")
    return tmp_path


def test_a_caption_moved_off_its_table_is_refused(tmp_path: Path) -> None:
    text = ADR.read_text(encoding="utf-8")
    caption = f"*{COMPOSITION_CAPTION}*"
    assert text.count(caption) == 1, "the caption this test moves has moved"
    moved = text.replace(caption + "\n", caption + "\n\nA sentence.\n")
    outcome = validate(ARCHIVE, _adr_root(tmp_path, moved) / ADR_REL)
    assert outcome.is_err
    assert (f"the caption {COMPOSITION_CAPTION!r} is not followed by a "
            "table") in str(outcome.unwrap_err())


def test_a_wrong_composition_cell_fails_demo_check(tmp_path: Path,
                                                   capsys) -> None:
    text = ADR.read_text(encoding="utf-8")
    row = "| turns | 130 | 128 | 148 | 157 | 206 | 179 |"
    assert text.count(row) == 1, "the row this test edits has moved"
    root = _adr_root(tmp_path, text.replace(row, row.replace("206", "207")))
    assert main(["--repo", str(root)]) == 1
    assert ("composition / turns / sonnet mcp (comp-sonnet5-mcp-1): the "
            "archive says 206, ADR 0001 § 9 says 207") in \
        capsys.readouterr().err


def test_a_column_is_held_to_the_run_its_header_names(tmp_path: Path) -> None:
    # Swapping two runs in the ADR's run row moves every cell with them.
    text = ADR.read_text(encoding="utf-8")
    row = ("| run | `comp-opus5-shell-1` | `comp-opus5-mcp-1` | "
           "`comp-opus5-both-1` |")
    assert text.count(row) == 1
    swapped = text.replace(row, "| run | `comp-opus5-mcp-1` | "
                                "`comp-opus5-shell-1` | `comp-opus5-both-1` |")
    outcome = validate(ARCHIVE, _adr_root(tmp_path, swapped) / ADR_REL)
    assert outcome.is_err
    assert "composition / run / opus shell (comp-opus5-shell-1)" in \
        str(outcome.unwrap_err())


def _edited(root: Path, edit) -> Path:
    """What `make demo-check` reads, the composition reports passed through
    `edit`, under a scratch repository root."""
    for run in EVERY_RUN:
        (root / ARCHIVE_REL / run).mkdir(parents=True)
        report = json.loads((ARCHIVE / run / "report.json")
                            .read_text(encoding="utf-8"))
        (root / ARCHIVE_REL / run / "report.json").write_text(
            json.dumps(edit(run, report) if run in COMPOSITION_RUNS
                       else report), encoding="utf-8")
        if run in COMPOSITION_RUNS:
            (root / ARCHIVE_REL / run / "subjects").symlink_to(
                ARCHIVE / run / "subjects")
    (root / ADR_REL).parent.mkdir(parents=True)
    (root / ADR_REL).write_text(ADR.read_text(encoding="utf-8"),
                                encoding="utf-8")
    return root


def _refused(root: Path) -> str:
    outcome = validate(root / ARCHIVE_REL, root / ADR_REL)
    assert outcome.is_err
    return str(outcome.unwrap_err())


def test_a_run_of_another_arm_is_refused(tmp_path: Path) -> None:
    def edit(run: str, report: Dict[str, Any]) -> Dict[str, Any]:
        if run == "comp-opus5-shell-1":
            report["config"]["arm"] = "mcp"
        return report
    assert ("composition / opus shell: comp-opus5-shell-1 ran claude-opus-5 "
            "in the mcp arm") in _refused(_edited(tmp_path, edit))


def test_a_composition_row_with_an_original_is_refused(tmp_path: Path) -> None:
    def edit(run: str, report: Dict[str, Any]) -> Dict[str, Any]:
        if run == "comp-sonnet5-mcp-1":
            report["outcomes"][0]["original"] = {"inView": False}
        return report
    message = _refused(_edited(tmp_path, edit))
    assert "comp-sonnet5-mcp-1/report.json, outcome 0" in message
    assert "original is {'inView': False}" in message


def test_a_composition_row_that_restates_is_refused(tmp_path: Path) -> None:
    def edit(run: str, report: Dict[str, Any]) -> Dict[str, Any]:
        if run == "comp-opus5-mcp-1":
            report["outcomes"][3]["tags"].append("restates:M.x")
        return report
    assert "a composition row with a restates: tag" in \
        _refused(_edited(tmp_path, edit))


def test_the_needle_row_carries_the_tiers_count(tmp_path: Path) -> None:
    # One needle fewer in every arm: the ADR's "(of 33)" row is then the
    # wrong row, and the archive's "(of 32)" row is missing from the ADR.
    def edit(run: str, report: Dict[str, Any]) -> Dict[str, Any]:
        tags = report["outcomes"][0]["tags"]
        tags.remove(next(t for t in tags if t.startswith("needle:")))
        return report
    message = _refused(_edited(tmp_path, edit))
    assert "has no row 'needles in the final files (of 32)'" in message
    assert "has a row 'needles in the final files (of 33)'" in message


# ------------------------------------------------------- the loop's sweeps

def test_the_loop_sweeps_are_read_from_the_tier_readme() -> None:
    readme = (REPO / COMPOSITION_README).read_text(encoding="utf-8")
    sweeps = loop_sweeps(readme)
    assert sweeps.is_ok, str(sweeps.unwrap_err())
    assert [(s["run"], s["solved"], s["total"]) for s in sweeps.unwrap()] == [
        ("comp160-fixed-1", 0, 12), ("comp160-retrieval-1", 0, 12),
        ("comp160-retrieval-idf-1", 0, 12)]


def test_a_second_loop_table_or_an_unread_cell_is_refused() -> None:
    readme = (REPO / COMPOSITION_README).read_text(encoding="utf-8")
    head = next(line for line in readme.splitlines()
                if line.strip().startswith("| run ") and "proposer" in line)
    twice = readme + "\n" + head + "\n" + readme.splitlines()[
        readme.splitlines().index(head) + 1] + "\n| x | y | 0/1 | | | | | |\n"
    assert "a second table headed" in str(loop_sweeps(twice).unwrap_err())
    unread = readme.replace("| 0/12   | 12        | 0               | 0   "
                            "      | 29     |",
                            "| none   | 12        | 0               | 0   "
                            "      | 29     |")
    assert unread != readme, "the cell this test edits has moved"
    assert "solved 'none' is not N/M" in str(loop_sweeps(unread).unwrap_err())


def test_the_build_carries_the_tier(tmp_path: Path) -> None:
    built = build(ARCHIVE, ADR)
    assert built.is_ok, str(built.unwrap_err())
    comp = built.unwrap()["composition"]
    assert comp["rows"] == 12 and comp["needles"] == 33
    assert comp["needleRange"] == [2, 4]
    assert [arm["runId"] for arm in comp["arms"]] == list(COMPOSITION_RUNS)
    assert {arm["startedOn"] for arm in comp["arms"]} == {"2026-09-29"}
    assert [arm["provenance"]["route"] for arm in comp["arms"]] == \
        [5, 5, 6, 7, 11, 8]
