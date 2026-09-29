"""
Tests for `scripts/python/site/figures_hook.py`: a page's figures, read from
the archived run reports.

File: scripts/python/tests/test_site_figures.py

Description
-----------
The pure half of the hook, in three parts.  JSON pointers resolve as RFC
6901 says, and only a count is a figure.  Each derived figure counts what
its docstring says, on a synthetic report built to separate it from its
neighbors, and the hard tier's headline is pinned against the archive
itself, since that is the figure that `totals.solved` gets wrong.  Then the
page: markers are replaced, a marker the hook cannot resolve fails with
every problem named, code is never touched, and a marker on a page that did
not opt in is refused.  The last case reads the landing page as committed
and resolves every marker in it against the archive, so a figure the page
cites and the archive lacks fails here as well as in the build.

The build-level failure (an unresolved marker stopping `mkdocs build
--strict`) is in test_site_build.py, which needs MkDocs.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_site_figures.py`
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict

from scripts.python.site.figures_hook import (
    DERIVED,
    MARKER,
    count,
    figure,
    final_checks_statement_kept,
    haystack_unqueried,
    knowledge_tool_calls,
    report_loader,
    resolve_pointer,
    rows_with_original,
    rows_without_original,
    solved_with_original,
    substitute_figures,
)
from scripts.python.utils.pipeline_types import ErrorType, PipelineError, Result

REPO = Path(__file__).resolve().parents[3]


def _outcome(**fields: Any) -> Dict[str, Any]:
    base: Dict[str, Any] = {"benchmarkId": "row", "solved": False, "original": None,
                            "agdaExit": 0, "statement": {"equal": True},
                            "stratum": "agda-stdlib", "toolCalls": {"Read": 1}}
    return {**base, **fields}


#: A report whose rows separate every derived figure from its neighbors.
REPORT: Dict[str, Any] = {
    "totals": {"total": 5, "solved": 2, "solvedOriginalInView": 1},
    "perStratum": {"agda-algebras/using": {"solved": 1},
                   "a~b": {"solved": 7}},
    "perTool": {"mcp__agda__check_file": 9, "mcp__agda__fill_hole": 4,
                "mcp__agda__type_of": 3, "mcp__agda__search_by_name": 2,
                "mcp__agda__search_in_scope": 1, "Bash": 50, "Read": 8},
    "rate": 1.5,
    "flag": True,
    "outcomes": [
        # solved, with an original
        _outcome(benchmarkId="a", solved=True, original={"inView": True}),
        # failed a session gate, but the file is sound: kept, not solved
        _outcome(benchmarkId="b", gate="isolation"),
        # does not type-check
        _outcome(benchmarkId="c", agdaExit=1),
        # type-checks with the statement changed
        _outcome(benchmarkId="d", statement={"equal": False}, original={"inView": False}),
        # solved, no original
        _outcome(benchmarkId="e", solved=True),
        # haystack rows: solved asking nothing; solved after a search; unsolved
        _outcome(benchmarkId="h1", solved=True, stratum="agda-stdlib/haystack",
                 toolCalls={"Read": 1, "Edit": 1, "mcp__agda__check_file": 1}),
        _outcome(benchmarkId="h2", solved=True, stratum="agda-stdlib/haystack",
                 toolCalls={"Read": 1, "mcp__agda__search_by_name": 1,
                            "mcp__agda__check_file": 1}),
        _outcome(benchmarkId="h3", stratum="agda-stdlib/haystack",
                 toolCalls={"Read": 1, "Edit": 1}),
    ],
}


def _loader(reports: Dict[str, Any]):
    def load(run: str) -> Result[Any, PipelineError]:
        return (Result.ok(reports[run]) if run in reports
                else Result.err(PipelineError(ErrorType.FILE_NOT_FOUND, f"no {run}")))
    return load


LOAD = _loader({"run-1": REPORT})


# ------------------------------------------------------------ JSON pointers

def test_pointers_resolve_with_their_escapes() -> None:
    assert resolve_pointer(REPORT, "/totals/solved").unwrap() == 2
    assert resolve_pointer(REPORT, "/perStratum/agda-algebras~1using/solved").unwrap() == 1
    assert resolve_pointer(REPORT, "/perStratum/a~0b/solved").unwrap() == 7
    assert resolve_pointer(REPORT, "/outcomes/4/benchmarkId").unwrap() == "e"
    assert resolve_pointer(REPORT, "").unwrap() is REPORT


def test_a_pointer_to_nothing_says_where_it_stopped() -> None:
    assert "no key 'solvd'" in resolve_pointer(REPORT, "/totals/solvd").unwrap_err()
    assert "no index 9" in resolve_pointer(REPORT, "/outcomes/9").unwrap_err()
    assert resolve_pointer(REPORT, "/outcomes/01").is_err
    assert resolve_pointer(REPORT, "totals").is_err


def test_only_a_count_is_a_figure() -> None:
    assert count(0).unwrap_or(-1) == 0
    assert "the number 1.5" in count(1.5).unwrap_err()
    assert "the boolean true" in count(True).unwrap_err()
    assert "null" in count(None).unwrap_err()
    assert "the string" in count("54").unwrap_err()
    assert figure(REPORT, "/rate").is_err and figure(REPORT, "/flag").is_err


# ---------------------------------------------------------- derived figures

def test_the_derived_figures_count_what_they_say() -> None:
    assert final_checks_statement_kept(REPORT).unwrap() == 6   # a, b, e, h1-h3
    assert rows_with_original(REPORT).unwrap() == 2            # a, d
    assert rows_without_original(REPORT).unwrap() == 6         # b, c, e, h1-h3
    assert haystack_unqueried(REPORT).unwrap() == 1            # h1
    assert solved_with_original(REPORT).unwrap() == 1          # a
    assert knowledge_tool_calls(REPORT).unwrap() == 6          # type_of, search_by_name, search_in_scope


def test_a_derived_figure_refuses_a_report_without_its_fields() -> None:
    bare = {"outcomes": [{"benchmarkId": "x", "solved": True}]}
    assert "'agdaExit'" in final_checks_statement_kept(bare).unwrap_err()
    assert "'original'" in rows_with_original(bare).unwrap_err()
    assert knowledge_tool_calls({}).is_err
    assert final_checks_statement_kept({}).is_err
    assert "'stratum'" in haystack_unqueried(bare).unwrap_err()


def test_the_haystack_figure_is_the_demos_quiet_count() -> None:
    # The landing page's haystack bullet and the demo's haystack section
    # count one thing; on the archive the two readings must agree, for a run
    # with the needle named in the header and one without (Issue #219).
    from scripts.python.demo.numbers import quiet
    load = report_loader(REPO)
    for run, expected in (("agent-sonnet5-1", 11),
                          ("suite219-sonnet5-mcp-1", 3)):
        report = load(run).unwrap()
        assert haystack_unqueried(report).unwrap() == expected
        assert quiet(report)["quiet"] == expected


def test_every_derived_figure_is_reachable_by_name() -> None:
    assert all(figure(REPORT, name).is_ok for name in DERIVED)
    assert "neither a JSON pointer" in figure(REPORT, "solved").unwrap_err()


def test_the_hard_tier_headline_is_not_the_solved_count() -> None:
    # The trap the derived figure exists for, on the archive itself: every
    # arm's final files type-check with their statements kept, while the
    # solved column is lowered by the isolation gate on the shell arms.
    load = report_loader(REPO)
    runs = ("hard-opus5-shell-1", "hard-opus5-mcp-1", "hard-opus5-both-1")
    reports = [load(run).unwrap() for run in runs]
    assert [final_checks_statement_kept(r).unwrap() for r in reports] == [14, 14, 14]
    assert [r["totals"]["solved"] for r in reports] == [8, 14, 8]


def test_the_header_free_tiers_headline_is_not_the_solved_count() -> None:
    # The same trap on the runs the landing page quotes since issues #160
    # and #219: the hard tier's header-free arms, and the composition tier's
    # Sonnet arms, whose solved column the preservation gate lowers too.
    load = report_loader(REPO)
    hard = ("hard219-opus5-shell-1", "hard219-opus5-mcp-1", "hard219-opus5-both-1")
    comp = ("comp-sonnet5-shell-1", "comp-sonnet5-mcp-1", "comp-sonnet5-both-1")
    hard_reports = [load(run).unwrap() for run in hard]
    comp_reports = [load(run).unwrap() for run in comp]
    assert [final_checks_statement_kept(r).unwrap() for r in hard_reports] == [14, 14, 14]
    assert [r["totals"]["solved"] for r in hard_reports] == [10, 14, 10]
    assert [final_checks_statement_kept(r).unwrap() for r in comp_reports] == [12, 12, 12]
    assert [r["totals"]["solved"] for r in comp_reports] == [6, 3, 5]


# --------------------------------------------------------------- the page

def test_markers_are_replaced_by_their_figures() -> None:
    page = ("Solved @fig(run-1 /totals/solved) of @fig(run-1 /totals/total); "
            "kept @fig(run-1 final-checks-statement-kept).\n")
    assert substitute_figures(page, True, LOAD).unwrap() == "Solved 2 of 5; kept 6.\n"


def test_a_page_without_markers_is_returned_as_is() -> None:
    page = "No figures here, and `@fig(run-1 /x)` is code.\n"
    assert substitute_figures(page, True, LOAD).unwrap() == page
    assert substitute_figures(page, False, LOAD).unwrap() == page


def test_every_unresolved_marker_is_named_with_its_line() -> None:
    page = ("@fig(run-1 /totals/solvd)\n"
            "@fig(run-2 /totals/solved)\n"
            "@fig(run-1 /rate)\n"
            "@fig(run-1 nonsense)\n"
            "@fig(run-1)\n"
            "@fig(run-1 /totals/solved\n")
    problems = substitute_figures(page, True, LOAD, "index.md").unwrap_err()
    assert len(problems) == 6
    assert any(p.startswith("index.md:1:") and "solvd" in p for p in problems)
    assert any(p.startswith("index.md:2:") and "no report for run 'run-2'" in p for p in problems)
    assert any(p.startswith("index.md:3:") and "not a count" in p for p in problems)
    assert any(p.startswith("index.md:4:") and "neither a JSON pointer" in p for p in problems)
    assert any(p.startswith("index.md:5:") and "expected @fig(" in p for p in problems)
    assert any(p.startswith("index.md:6:") and "not closed" in p for p in problems)


def test_a_run_id_cannot_reach_outside_the_runs_directory() -> None:
    problems = substitute_figures("@fig(../run-1 /totals/solved)", True, LOAD).unwrap_err()
    assert "expected @fig(" in problems[0]


def test_code_is_never_touched() -> None:
    page = ("`@fig(run-1 /totals/solved)` and\n"
            "```agda\ninstance-arg : {{ _ : Eq A }} → @fig(run-1 /totals/solved)\n```\n"
            "<!-- @fig(nowhere /x) -->\n"
            "but @fig(run-1 /totals/solved) here.\n")
    out = substitute_figures(page, True, LOAD).unwrap()
    assert out == page.replace("but @fig(run-1 /totals/solved) here", "but 2 here")


def test_a_marker_on_a_page_that_did_not_opt_in_is_refused() -> None:
    problems = substitute_figures("x @fig(run-1 /totals/solved)", False, LOAD,
                                  "notes/x.md").unwrap_err()
    assert "does not set `figures: true`" in problems[0]
    assert problems[0].startswith("notes/x.md:1:")


def test_the_landing_page_opts_in_and_every_figure_resolves() -> None:
    page = (REPO / "docs" / "index.md").read_text(encoding="utf-8")
    assert re.search(r"^figures:\s*true\s*$", page, re.M), "index.md does not opt in"
    body = page.split("\n---\n", 1)[1]
    assert MARKER.search(body), "the landing page cites no figure"
    result = substitute_figures(body, True, report_loader(REPO), "index.md")
    assert result.is_ok, result.unwrap_err() if result.is_err else ""
    assert "@fig(" not in result.unwrap()
