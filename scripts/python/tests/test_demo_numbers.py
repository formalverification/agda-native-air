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

Issue #215 adds the second table § 9 states, the attribution arms of Issue
#162, whose cells are prose (`9 solved, 2 restated`) rather than one number
each.  The same three kinds of case pin it: the reader, which refuses a cell
it cannot read rather than guessing; the comparison against the committed
archive; and a copy of the ADR with one wrong cell, which must fail the build.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_demo_numbers.py`
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Callable, Dict

from scripts.python.demo.numbers import ADR as ADR_REL
from scripts.python.demo.numbers import ARCHIVE as ARCHIVE_REL
from scripts.python.demo.numbers import (
    BOTH_RUN,
    CONTROL,
    MCP_RUN,
    OPUS_RUN,
    SHELL_RUN,
    SONNET_RUN,
    STRATA,
    Tally,
    adr_table,
    archive_size,
    arm_summary,
    build,
    compare,
    compare_control,
    control_rows,
    control_table,
    loop_columns,
    main,
    per_tool,
    report_problems,
    rows_from_reports,
    validate,
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

Prose between.

| stratum | n | archive `mcp` | `shell` | `mcp` | `both` |
|---|---|---|---|---|---|
| agda-stdlib | 22 | 21 solved | 20 solved | 21 solved | 20 solved |
| agda-stdlib/haystack | 12 | 12 solved | 12 solved | 12 solved | 12 solved |
| agda-algebras/using | 11 | 9 solved, 2 restated | 9 solved | 9 solved, 1 restated | 11 solved |
| agda-algebras/wholesale | 10 | 4 solved, 6 restated | 9 solved | 5 solved, 5 restated | 8 solved, 2 restated |
| **total** | 55 | **46 solved, 8 restated** | **50 solved, 0 restated** | **47 solved, 6 restated** | **51 solved, 2 restated** |

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


#: Every run the build reads: the two arms the page replays, and the three
#: attribution arms of Issue #162 beside them.
RUNS = (SONNET_RUN, OPUS_RUN, SHELL_RUN, MCP_RUN, BOTH_RUN)

Edit = Callable[[str, Dict[str, Any]], Dict[str, Any]]


def _unchanged(run: str, report: Dict[str, Any]) -> Dict[str, Any]:
    return report


def _archive_copy(tmp_path: Path, edit: Edit = _unchanged) -> Path:
    """A copy of every report the build reads, each passed through `edit`.

    The subjects are reached through a link rather than copied: the build
    reads one transcript per run for the day the run started, and 14 MB of
    transcripts would buy a test nothing.
    """
    for run in RUNS:
        (tmp_path / run).mkdir(parents=True)
        (tmp_path / run / "subjects").symlink_to(ARCHIVE / run / "subjects")
        report = json.loads(
            (ARCHIVE / run / "report.json").read_text(encoding="utf-8"))
        (tmp_path / run / "report.json").write_text(
            json.dumps(edit(run, report)), encoding="utf-8")
    return tmp_path


def _moved(target: str, stratum: str, field: str, value: int) -> Edit:
    """An edit that moves one cell of one run's report."""
    def edit(run: str, report: Dict[str, Any]) -> Dict[str, Any]:
        if run != target:
            return report
        moved = json.loads(json.dumps(report))
        block = moved["totals"] if stratum == "total" else \
            moved["perStratum"][stratum]
        block[field] = value
        return moved
    return edit


def test_the_check_would_notice_a_drifted_report(tmp_path: Path) -> None:
    # A copy of the archive with one cell moved must fail the build, or the
    # agreement above would be a coincidence rather than a check.
    archive = _archive_copy(
        tmp_path, _moved(SONNET_RUN, "agda-stdlib", "restated", 3))
    outcome = build(archive, ADR)
    assert outcome.is_err
    assert "Sonnet 5 restated" in str(outcome.unwrap_err())


def test_an_unchanged_copy_of_the_archive_builds(tmp_path: Path) -> None:
    # The control for the drift cases: the copy itself is not what fails.
    outcome = build(_archive_copy(tmp_path), ADR)
    assert outcome.is_ok, str(outcome.unwrap_err())


# ------------------------------------ the attribution table (Issue #215)

def test_the_attribution_table_is_read_as_tallies() -> None:
    table = control_table(MARKDOWN)
    assert table.is_ok, str(table.unwrap_err())
    rows = table.unwrap()
    assert set(rows) == {name.lower() for name in STRATA} | {"total"}
    # A restated count the ADR leaves out is zero; one it writes, bold or
    # not, is read as written.
    assert rows["agda-stdlib"] == (22, (Tally(21, 0), Tally(20, 0),
                                        Tally(21, 0), Tally(20, 0)))
    assert rows["total"] == (55, (Tally(46, 8), Tally(50, 0),
                                  Tally(47, 6), Tally(51, 2)))


def test_the_columns_are_the_runs_they_name() -> None:
    # The archived `mcp` column is the Sonnet arm the page replays, so that
    # one run is held to both of § 9's tables.
    assert CONTROL == (("archive mcp", SONNET_RUN), ("shell", SHELL_RUN),
                       ("mcp", MCP_RUN), ("both", BOTH_RUN))


def test_a_cell_that_is_not_a_tally_is_refused() -> None:
    # The guide writes the same table as `9 (2 restated)`; the ADR does not,
    # and a cell in any form but the ADR's is an error, never a guess.
    broken = MARKDOWN.replace("| 9 solved, 1 restated |",
                              "| 9 (1 restated) |")
    outcome = control_table(broken)
    assert outcome.is_err
    message = str(outcome.unwrap_err())
    assert "agda-algebras/using" in message and "mcp" in message
    assert "9 (1 restated)" in message


def test_a_renamed_arm_column_is_refused() -> None:
    renamed = MARKDOWN.replace("| `shell` |", "| `bash` |")
    outcome = control_table(renamed)
    assert outcome.is_err
    assert "no table headed" in str(outcome.unwrap_err())


def test_the_agent_table_is_still_found_beside_the_other() -> None:
    # Two tables in one document share their first two columns; each is
    # found by its whole header, and neither is taken for the other.
    assert adr_table(MARKDOWN).unwrap()["total"] == \
        ["55", "8", "14", "46", "8", "54", "1"]


def _reports() -> Dict[str, Dict[str, Any]]:
    """Synthetic reports for the four columns, agreeing with MARKDOWN."""
    stated = control_table(MARKDOWN).unwrap()
    return {
        run: _report({name: stated[name][1][at].solved for name in STRATA},
                     {name: stated[name][1][at].restated for name in STRATA})
        for at, (_, run) in enumerate(CONTROL)
    }


def test_an_agreeing_control_reports_nothing() -> None:
    rows = control_rows(_reports())
    assert compare_control(rows, control_table(MARKDOWN).unwrap()) == ()


def test_a_control_disagreement_names_the_run_and_both_tallies() -> None:
    reports = _reports()
    reports[MCP_RUN]["perStratum"]["agda-algebras/wholesale"]["restated"] = 4
    reports[MCP_RUN]["totals"]["restated"] = 5
    problems = compare_control(control_rows(reports),
                               control_table(MARKDOWN).unwrap())
    assert len(problems) == 2
    wholesale = next(p for p in problems if "wholesale" in p)
    assert MCP_RUN in wholesale
    assert "5 solved, 4 restated" in wholesale
    assert "5 solved, 5 restated" in wholesale


def test_the_control_agrees_with_adr_0001() -> None:
    # Issue #215: the control's numbers are read from the three attribution
    # arms' reports and must equal § 9's attribution table cell for cell.
    outcome = build(ARCHIVE, ADR)
    assert outcome.is_ok, str(outcome.unwrap_err())
    control = outcome.unwrap()["control"]
    total = next(row for row in control["rows"] if row["stratum"] == "total")
    assert [(cell["runId"], cell["solved"], cell["restated"])
            for cell in total["cells"]] == [
        (SONNET_RUN, 46, 8), (SHELL_RUN, 50, 0),
        (MCP_RUN, 47, 6), (BOTH_RUN, 51, 2)]
    assert [arm["arm"] for arm in control["arms"]] == \
        ["mcp", "shell", "mcp", "both"]
    assert all(arm["anomalies"] == 0 for arm in control["arms"])


def test_a_copy_of_the_adr_with_one_wrong_cell_fails(tmp_path: Path) -> None:
    # The kick-off's case: the committed archive, and a copy of ADR 0001
    # whose attribution table has one cell moved, must not build.
    text = ADR.read_text(encoding="utf-8")
    row = ("| agda-algebras/wholesale | 10 | 4 solved, 6 restated "
           "| 9 solved | 5 solved, 5 restated | 8 solved, 2 restated |")
    assert text.count(row) == 1, "the row this test edits has moved"
    wrong = tmp_path / "adr.md"
    wrong.write_text(text.replace(row, row.replace("| 9 solved |",
                                                   "| 8 solved |")),
                     encoding="utf-8")
    outcome = build(ARCHIVE, wrong)
    assert outcome.is_err
    message = str(outcome.unwrap_err())
    assert "agda-algebras/wholesale / shell" in message
    assert "9 solved, 0 restated" in message
    assert "8 solved, 0 restated" in message


def test_a_drifted_control_report_fails(tmp_path: Path) -> None:
    archive = _archive_copy(
        tmp_path, _moved(BOTH_RUN, "total", "restated", 3))
    outcome = build(archive, ADR)
    assert outcome.is_err
    assert f"total / both ({BOTH_RUN})" in str(outcome.unwrap_err())


# ------------------------------------------- what the page is handed

def test_the_tools_presented_are_read_from_the_subjects_not_the_allowlist() -> None:
    # The attribution arms' `config.tools` lists thirteen agda tools, the
    # harness's allowlist; their subjects were presented fourteen, and
    # `search_in_scope` is the one the list omits.  The count the page
    # prints is the subjects'.
    config = json.loads((ARCHIVE / MCP_RUN / "report.json")
                        .read_text(encoding="utf-8"))["config"]["tools"]
    assert len([t for t in config if t.startswith("mcp__agda__")]) == 13
    report = json.loads((ARCHIVE / MCP_RUN / "report.json")
                        .read_text(encoding="utf-8"))
    summary = arm_summary(report, MCP_RUN)
    assert summary["toolCount"] == 14
    assert "search_in_scope" in summary["agdaTools"]
    table = build(ARCHIVE, ADR).unwrap()
    assert table["arms"]["opus"]["toolCount"] == 13
    assert "search_in_scope" not in table["arms"]["opus"]["agdaTools"]


def test_original_in_view_is_counted_over_the_strata_that_have_one() -> None:
    # The judge's `original` column (Issue #188): solves on rows with an
    # original, and how many of them had its proof in view.  The archived
    # arm could read no original; the attribution arms could read every one.
    arms = {arm["runId"]: arm["withOriginal"]
            for arm in build(ARCHIVE, ADR).unwrap()["control"]["arms"]}
    assert (arms[SONNET_RUN]["solved"], arms[SONNET_RUN]["inView"]) == (13, 0)
    assert arms[SONNET_RUN]["reads"] == 0
    assert arms[SONNET_RUN]["refusedReads"] > 0
    assert (arms[SHELL_RUN]["solved"], arms[SHELL_RUN]["inView"]) == (18, 15)
    assert (arms[MCP_RUN]["solved"], arms[MCP_RUN]["inView"]) == (14, 4)
    assert (arms[BOTH_RUN]["solved"], arms[BOTH_RUN]["inView"]) == (19, 16)
    assert all(arms[run]["refusedReads"] == 0
               for run in (SHELL_RUN, MCP_RUN, BOTH_RUN))


def test_every_arm_started_on_the_day_its_first_transcript_says() -> None:
    table = build(ARCHIVE, ADR).unwrap()
    assert table["arms"]["sonnet"]["startedOn"] == "2026-09-15"
    assert table["arms"]["opus"]["startedOn"] == "2026-09-15"
    assert {arm["runId"]: arm["startedOn"]
            for arm in table["control"]["arms"]} == {
        SONNET_RUN: "2026-09-15", SHELL_RUN: "2026-09-21",
        MCP_RUN: "2026-09-21", BOTH_RUN: "2026-09-21"}


def test_every_session_of_the_replayed_arms_ended_on_its_own() -> None:
    # The page says no subject reached a cap; `terminal` is the harness's
    # reading of how each session ended, and `completed` is the client's
    # own `success`.
    arms = build(ARCHIVE, ADR).unwrap()["arms"]
    assert arms["sonnet"]["completed"] == arms["sonnet"]["total"] == 55
    assert arms["opus"]["completed"] == arms["opus"]["total"] == 55


def test_the_archive_is_measured_not_quoted(tmp_path: Path) -> None:
    # The page once said 1,051 files and 14 MB, and the archive grew five
    # times over without the sentence noticing.  It is counted now, in bytes
    # of content rather than the file system's blocks.
    (tmp_path / "run" / "subjects").mkdir(parents=True)
    (tmp_path / "run" / "report.json").write_text("{}", encoding="utf-8")
    (tmp_path / "run" / "subjects" / "t.jsonl").write_text(
        "abc", encoding="utf-8")
    assert archive_size(tmp_path).unwrap() == {"files": 2, "bytes": 5}
    measured = build(ARCHIVE, ADR).unwrap()["archive"]
    on_disk = [path for path in ARCHIVE.glob("**/*") if path.is_file()]
    assert measured["files"] == len(on_disk) > 1051
    assert measured["bytes"] == sum(path.stat().st_size for path in on_disk)


# ------------------------------------------ make demo-check (Issue #215)

def _reports_only(root: Path, adr_text: str) -> Path:
    """A repository root holding only what `make demo-check` may read: the
    five run reports and ADR 0001, with no transcript and no other file."""
    for run in RUNS:
        (root / ARCHIVE_REL / run).mkdir(parents=True)
        (root / ARCHIVE_REL / run / "report.json").write_text(
            (ARCHIVE / run / "report.json").read_text(encoding="utf-8"),
            encoding="utf-8")
    (root / ADR_REL).parent.mkdir(parents=True)
    (root / ADR_REL).write_text(adr_text, encoding="utf-8")
    return root


def test_demo_check_reads_only_the_reports_and_the_adr(tmp_path: Path,
                                                        capsys) -> None:
    # Copilot's review of PR #217: `make demo-check` ran the whole build, so
    # a transcript the comparison never uses could fail it.  With nothing but
    # the five reports and the ADR, the comparison passes and the full build,
    # which needs the transcripts, does not.
    root = _reports_only(tmp_path, ADR.read_text(encoding="utf-8"))
    assert main(["--repo", str(root)]) == 0
    assert "run reports agree with" in capsys.readouterr().out
    assert validate(root / ARCHIVE_REL, root / ADR_REL).is_ok
    assert build(root / ARCHIVE_REL, root / ADR_REL).is_err


def test_demo_check_fails_on_a_wrong_cell(tmp_path: Path, capsys) -> None:
    text = ADR.read_text(encoding="utf-8")
    cell = "**47 solved, 6 restated**"
    assert text.count(cell) == 1, "the cell this test edits has moved"
    root = _reports_only(tmp_path,
                         text.replace(cell, "**47 solved, 5 restated**"))
    assert main(["--repo", str(root)]) == 1
    assert f"total / mcp ({MCP_RUN})" in capsys.readouterr().err


# ------------------------- reading the ADR strictly (PR #217, round two)

ATTRIBUTION_HEAD = ("| stratum | n | archive `mcp` | `shell` | `mcp` | "
                    "`both` |\n|---|---|---|---|---|---|\n")
CONTROL_STDLIB = ("| agda-stdlib | 22 | 21 solved | 20 solved | 21 solved | "
                  "20 solved |")
AGENT_STDLIB = "| agda-stdlib | 22 | 6 | 6 | 21 | 0 | 22 | 0 |"


def test_a_row_with_a_missing_cell_is_named_not_dropped() -> None:
    # A lenient reader ended the table at the short row and reported every
    # row after it missing; the row itself is the problem, and is named.
    row = ("| agda-algebras/using | 11 | 9 solved, 2 restated | 9 solved | "
           "9 solved, 1 restated | 11 solved |")
    assert MARKDOWN.count(row) == 1
    short = row.replace("| 9 solved, 1 restated |", "|")
    message = str(control_table(MARKDOWN.replace(row, short)).unwrap_err())
    assert "5 cells where the header has 6" in message
    assert "agda-algebras/using" in message


def test_a_repeated_row_is_refused_in_either_table() -> None:
    # A lenient reader let the second row replace the first, so a wrong row
    # followed by a right one passed.
    for read, row, wrong in (
            (control_table, CONTROL_STDLIB,
             CONTROL_STDLIB.replace("| 20 solved |", "| 19 solved |", 1)),
            (adr_table, AGENT_STDLIB,
             AGENT_STDLIB.replace("| 21 |", "| 20 |"))):
        assert MARKDOWN.count(row) == 1 and wrong != row
        outcome = read(MARKDOWN.replace(row, wrong + "\n" + row))
        assert outcome.is_err
        assert "a second row for 'agda-stdlib'" in str(outcome.unwrap_err())


def test_a_table_without_its_delimiter_row_is_refused() -> None:
    assert MARKDOWN.count(ATTRIBUTION_HEAD) == 1
    header_only = ATTRIBUTION_HEAD.split("\n")[0] + "\n"
    outcome = control_table(MARKDOWN.replace(ATTRIBUTION_HEAD, header_only))
    assert outcome.is_err
    assert "not the table's delimiter row" in str(outcome.unwrap_err())


def test_a_non_numeric_agent_cell_is_refused_not_raised() -> None:
    # The loop's columns are read as integers; a cell that is not one used
    # to end the build in a ValueError traceback.
    broken = MARKDOWN.replace("| agda-stdlib | 22 | 6 | 6 |",
                              "| agda-stdlib | 22 | 6 | six |")
    outcome = adr_table(broken)
    assert outcome.is_err
    assert "agda-stdlib / loop retrieval: 'six' is not a count" in \
        str(outcome.unwrap_err())


def test_the_loop_total_must_be_the_sum_of_its_strata() -> None:
    moved = MARKDOWN.replace("| **total** | 55 | 8 | 14 |",
                             "| **total** | 55 | 8 | 15 |")
    table = adr_table(moved).unwrap()
    rows = rows_from_reports(SONNET, OPUS, loop_columns(table))
    assert compare(rows, table) == (
        "total / loop retrieval: the strata's cells sum to 14, "
        "ADR 0001 § 9's total says 15",)


def test_a_copy_of_the_adr_with_the_loop_total_moved_fails(tmp_path: Path,
                                                          capsys) -> None:
    # Copilot's Balanced review of PR #217: moving only the ADR's loop total
    # (14 to 15) passed `make demo-check`, while the page printed 14.
    text = ADR.read_text(encoding="utf-8")
    total = "| **total** | 55 | 8 | 14 | **46** | 8 | **54** | 1 |"
    assert text.count(total) == 1, "the row this test edits has moved"
    root = _reports_only(tmp_path,
                         text.replace(total, total.replace("| 14 |", "| 15 |")))
    assert main(["--repo", str(root)]) == 1
    assert "total / loop retrieval: the strata's cells sum to 14" in \
        capsys.readouterr().err


# ------------------------- a report's fields are required (round three)

def _reports_edited(root: Path, edit: Edit) -> Path:
    """What `make demo-check` reads, the five reports passed through `edit`
    and the committed ADR, under a scratch repository root."""
    for run in RUNS:
        (root / ARCHIVE_REL / run).mkdir(parents=True)
        report = json.loads(
            (ARCHIVE / run / "report.json").read_text(encoding="utf-8"))
        (root / ARCHIVE_REL / run / "report.json").write_text(
            json.dumps(edit(run, report)), encoding="utf-8")
    (root / ADR_REL).parent.mkdir(parents=True)
    (root / ADR_REL).write_text(ADR.read_text(encoding="utf-8"),
                                encoding="utf-8")
    return root


def _dropped(runs, *path: str) -> Edit:
    """An edit that deletes one field from the named runs' reports."""
    def edit(run: str, report: Dict[str, Any]) -> Dict[str, Any]:
        if run not in runs:
            return report
        copy = json.loads(json.dumps(report))
        node = copy
        for key in path[:-1]:
            node = node[key]
        del node[path[-1]]
        return copy
    return edit


def _refusal(root: Path) -> str:
    outcome = validate(root / ARCHIVE_REL, root / ADR_REL)
    assert outcome.is_err, "a report missing a field the page reads passed"
    return str(outcome.unwrap_err())


def test_a_report_missing_a_compared_field_is_refused(tmp_path: Path) -> None:
    # Copilot's third review of PR #217: with `restated` gone from the stdlib
    # stratum of all four control reports, the reader defaulted it to zero,
    # the ADR says zero there, and `demo-check` passed a zero no run recorded.
    control = {run for _, run in CONTROL}
    message = _refusal(_reports_edited(
        tmp_path, _dropped(control, "perStratum", "agda-stdlib", "restated")))
    assert f"{SHELL_RUN}/report.json: no perStratum.agda-stdlib.restated" \
        in message


def test_the_agent_tables_reports_are_held_to_the_same_fields(
        tmp_path: Path) -> None:
    message = _refusal(_reports_edited(
        tmp_path,
        _dropped({SONNET_RUN}, "perStratum", "agda-stdlib", "restated")))
    assert f"{SONNET_RUN}/report.json: no perStratum.agda-stdlib.restated" \
        in message


def test_a_field_the_page_prints_but_never_compares_is_required(
        tmp_path: Path) -> None:
    # No ADR cell holds an arm's anomaly count, so no comparison would catch
    # its absence; the page would have said "neither arm produced an anomaly".
    message = _refusal(_reports_edited(
        tmp_path, _dropped({OPUS_RUN}, "totals", "anomalies")))
    assert f"{OPUS_RUN}/report.json: no totals.anomalies" in message


def test_a_count_of_the_wrong_kind_is_refused(tmp_path: Path) -> None:
    def edit(run: str, report: Dict[str, Any]) -> Dict[str, Any]:
        if run != MCP_RUN:
            return report
        copy = json.loads(json.dumps(report))
        copy["totals"]["solved"] = True
        copy["outcomes"][0]["turns"] = "4"
        return copy
    message = _refusal(_reports_edited(tmp_path, edit))
    assert f"{MCP_RUN}/report.json: totals.solved is True" in message
    assert "outcome 0 (stdlib-nat-plus-identity-l): turns is '4'" in message


def test_every_committed_report_has_every_field_the_page_reads() -> None:
    for run in RUNS:
        report = json.loads(
            (ARCHIVE / run / "report.json").read_text(encoding="utf-8"))
        assert report_problems(run, report) == (), run
