"""
Tests for `scripts/python/demo/numbers.py`.

File: scripts/python/tests/test_demo_numbers.py

Description
-----------
The demo page prints the 55-row table that ADR 0001 § 9 states.  It
regenerates the agent columns from each arm's own `report.json` rather than
transcribing them, and `test_the_page_agrees_with_adr_0001` is the check that
makes that worth anything: it compares the regenerated table with the ADR's,
cell by cell, over the committed archive.  That is the "mechanically, not by
eye" requirement of Issue #85, and it runs in CI with the rest of this suite.

The synthetic cases around it pin the parser and the comparison itself: a
check that cannot fail is not a check, so one case perturbs a report and
asserts the disagreement is reported with both numbers in it.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_demo_numbers.py`
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

from scripts.python.demo.numbers import (
    OPUS_RUN,
    SONNET_RUN,
    STRATA,
    adr_table,
    build,
    compare,
    loop_columns,
    per_tool,
    rows_from_reports,
)

REPO = Path(__file__).resolve().parents[3]
ARCHIVE = REPO / "reports" / "agent-bench"
ADR = REPO / "docs" / "adr" / "0001-proof-search-on-agda-mcp.md"

MARKDOWN = """
Prose before.

| stratum | n | loop fixed | loop retrieval | Sonnet 5 solved | Sonnet 5 restated | Opus 5 solved | Opus 5 restated |
|---|---|---|---|---|---|---|---|
| agda-stdlib | 22 | 6 | 6 | 21 | 0 | 22 | 0 |
| agda-stdlib/haystack | 12 | 0 | 6 | 12 | 0 | 12 | 0 |
| agda-algebras/using | 11 | 2 | 2 | 9 | 2 | 11 | 0 |
| agda-algebras/wholesale | 10 | 0 | 0 | 4 | 6 | 9 | 1 |
| **total** | 55 | 8 | 14 | **46** | 8 | **54** | 1 |

Prose after.

| something | else |
|---|---|
| a | b |
"""


def _report(solved: Dict[str, int], restated: Dict[str, int]) -> Dict[str, Any]:
    strata = {name: {"total": n, "solved": solved[name],
                     "restated": restated[name]}
              for name, n in (("agda-stdlib", 22),
                              ("agda-stdlib/haystack", 12),
                              ("agda-algebras/using", 11),
                              ("agda-algebras/wholesale", 10))}
    return {
        "perStratum": strata,
        "totals": {"total": 55,
                   "solved": sum(solved.values()),
                   "restated": sum(restated.values())},
    }


SONNET = _report({"agda-stdlib": 21, "agda-stdlib/haystack": 12,
                  "agda-algebras/using": 9, "agda-algebras/wholesale": 4},
                 {"agda-stdlib": 0, "agda-stdlib/haystack": 0,
                  "agda-algebras/using": 2, "agda-algebras/wholesale": 6})
OPUS = _report({"agda-stdlib": 22, "agda-stdlib/haystack": 12,
                "agda-algebras/using": 11, "agda-algebras/wholesale": 9},
               {"agda-stdlib": 0, "agda-stdlib/haystack": 0,
                "agda-algebras/using": 0, "agda-algebras/wholesale": 1})


def test_the_right_table_is_found_among_several() -> None:
    table = adr_table(MARKDOWN)
    assert table.is_ok
    rows = table.unwrap()
    assert set(rows) == {name.lower() for name in STRATA} | {"total"}
    assert rows["total"] == ["55", "8", "14", "46", "8", "54", "1"]


def test_a_document_without_the_table_is_refused() -> None:
    outcome = adr_table("# Just prose\n\n| a | b |\n|---|---|\n| 1 | 2 |\n")
    assert outcome.is_err
    assert "no table headed" in str(outcome.unwrap_err())


def test_the_loop_columns_come_from_the_adr() -> None:
    # They have no machine-readable source in the repository: the loop's
    # sweeps are the ADR's record, and the page says so where it prints them.
    loop = loop_columns(adr_table(MARKDOWN).unwrap())
    assert loop == {"agda-stdlib": (6, 6), "agda-stdlib/haystack": (0, 6),
                    "agda-algebras/using": (2, 2),
                    "agda-algebras/wholesale": (0, 0)}


def test_the_regenerated_rows_are_in_the_declared_order() -> None:
    rows = rows_from_reports(SONNET, OPUS,
                             loop_columns(adr_table(MARKDOWN).unwrap()))
    assert [row.stratum for row in rows] == list(STRATA) + ["total"]
    assert rows[-1].n == 55
    assert (rows[-1].sonnet_solved, rows[-1].opus_solved) == (46, 54)
    assert (rows[-1].loop_fixed, rows[-1].loop_retrieval) == (8, 14)


def test_an_agreeing_pair_reports_nothing() -> None:
    table = adr_table(MARKDOWN).unwrap()
    rows = rows_from_reports(SONNET, OPUS, loop_columns(table))
    assert compare(rows, table) == ()


def test_a_disagreement_names_both_numbers() -> None:
    table = adr_table(MARKDOWN).unwrap()
    moved = json.loads(json.dumps(OPUS))
    moved["perStratum"]["agda-algebras/wholesale"]["solved"] = 8
    rows = rows_from_reports(SONNET, moved, loop_columns(table))
    problems = compare(rows, table)
    assert len(problems) == 1
    assert "agda-algebras/wholesale" in problems[0]
    assert "says 8" in problems[0] and "says 9" in problems[0]


def test_a_stratum_the_adr_does_not_have_is_reported() -> None:
    table = {k: v for k, v in adr_table(MARKDOWN).unwrap().items()
             if k != "agda-stdlib/haystack"}
    rows = rows_from_reports(SONNET, OPUS, {})
    problems = compare(rows, table)
    assert any("no row for stratum" in problem for problem in problems)


def test_per_tool_is_ordered_by_call_count() -> None:
    counts = per_tool({"perTool": {"a": 1, "b": 9, "c": 9}})
    assert counts == (("b", 9), ("c", 9), ("a", 1))


# --------------------------------------------------- against the archive

def test_the_page_agrees_with_adr_0001() -> None:
    # The check Issue #85 asks for: the table the page prints is regenerated
    # from the arms' own reports and must equal ADR 0001 § 9 cell for cell.
    outcome = build(ARCHIVE, ADR)
    assert outcome.is_ok, str(outcome.unwrap_err())
    table = outcome.unwrap()
    total = table["rows"][-1]
    assert total["stratum"] == "total"
    assert (total["n"], total["sonnetSolved"], total["sonnetRestated"],
            total["opusSolved"], total["opusRestated"]) == (55, 46, 8, 54, 1)
    assert (total["loopFixed"], total["loopRetrieval"]) == (8, 14)
    assert table["arms"]["sonnet"]["runId"] == SONNET_RUN
    assert table["arms"]["opus"]["runId"] == OPUS_RUN
    assert table["arms"]["opus"]["toolCount"] == 13
    assert table["arms"]["sonnet"]["anomalies"] == 0
    assert table["arms"]["opus"]["anomalies"] == 0


def test_the_check_would_notice_a_drifted_report(tmp_path: Path) -> None:
    # A copy of the archive with one cell moved must fail the build, or the
    # agreement above would be a coincidence rather than a check.
    for run in (SONNET_RUN, OPUS_RUN):
        (tmp_path / run).mkdir(parents=True)
        report = json.loads(
            (ARCHIVE / run / "report.json").read_text(encoding="utf-8"))
        if run == SONNET_RUN:
            report["perStratum"]["agda-stdlib"]["restated"] = 3
        (tmp_path / run / "report.json").write_text(
            json.dumps(report), encoding="utf-8")
    outcome = build(tmp_path, ADR)
    assert outcome.is_err
    assert "Sonnet 5 restated" in str(outcome.unwrap_err())
