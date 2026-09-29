#!/usr/bin/env python3
"""
File: scripts/python/demo/numbers.py

Description: The demo page's numbers, regenerated from the archived run
  reports and checked against ADR 0001 § 9 (Issues #85, #215, and #219).

  § 9 states two tables the page carries, each twice: once as first measured,
  with the fixture headers' hints in view, and once re-measured without them
  (Issue #219).  The page carries the header-free pair.  The agent table
  gives the two arms whose sessions the page replays, Sonnet 5 and Opus 5
  with the server.  The attribution table gives the control (Issue #162):
  the same model with a shell and the same `agda` in place of the server,
  with the server, and with both; its `mcp` column is the Sonnet arm of the
  agent table, one run held to both tables.  Each table is found by the
  caption line the ADR sets above it (`AGENT_CAPTION`, `CONTROL_CAPTION`),
  since the dated tables share their headers.  Transcribing either table
  would be how a page and a decision record come to disagree, so every
  figure is recomputed
  here from the runs' own `report.json` and then compared with the ADR's
  tables cell for cell.  The comparison is `validate`, which reads the five
  reports and the ADR and nothing else; `make demo-check` (this module's
  `main`, which writes nothing) runs it alone, and `build`, which `make
  demo-data` and the tests run, runs it first, so a number that drifts
  fails a build rather than a reading.  Only those two tables are compared:
  the page's other figures (by tier, by tool, per arm) are regenerated from
  the same reports and have no table in the ADR to be compared with.

  Two of the agent table's columns are not the agents': "loop fixed" and
  "loop retrieval" are the proof-search loop's solve counts on the same suite,
  a different instrument with no model in it and its own final check, and
  they have no machine-readable source in this repository.  They are taken
  from the ADR, which is their record, and the page says so where it prints
  them.  The one check they admit is the ADR's own arithmetic: the page
  prints their sums as its total row, so the ADR's total row must equal the
  sums of its strata, or the two would disagree unnoticed.

  The attribution table's cells are prose, `9 solved, 2 restated`, where the
  agent table's are one number each.  `control_table` reads them with one
  pattern and refuses any cell it does not match, the way `adr_table` refuses
  a renamed column: a cell in another form is an error, never a guess.

  Beyond the two tables the page is handed what it says about the runs in
  words, each read from the same reports: which tools each run's subjects
  were presented (from their own isolation audits, not the harness's
  allowlist, which omits the fourteenth tool the attribution arms' subjects
  were shown), how many sessions ended on their own, the judge's
  original-in-view counts (Issue #188), and the day each run began (from its
  first subject's transcript, since a re-judge rewrites the report's own
  timestamp).  The archive's own size is counted here too, for the same
  reason: it grows with every run, and a figure typed into the page went
  stale within a week.

  Every field of a report that the page reads is declared in
  `REPORT_FIELDS` (and `OUTCOME_FIELDS`) and required when the reports are
  loaded, before anything reads them.  The readers below default an absent
  field to zero or to nothing, so without that check a report missing a
  field would have printed a zero no run recorded.

Usage:

    PYTHONPATH=. python3 -m scripts.python.demo.numbers [--repo .]

Design Principles:
  +  One canonical stratum order.  `report.json` is a JSON object, so its key
     order is an artifact of how the harness wrote it; the table's order is
     declared here and the ADR's rows are matched to it by name.
  +  The ADR is parsed, not assumed.  `_table` finds the one table in the
     document under a given caption line and requires its header to carry a
     given column set, so a dated table with the same columns cannot be
     picked up by accident, a caption that moves off its table is refused,
     and a renamed column fails loudly.
  +  Differences are values.  `compare` and `compare_control` return the
     list of disagreements rather than raising, so a caller can print all of
     them at once, both tables' together.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

from scripts.python.demo.transcript import load as load_transcript
from scripts.python.utils.file_ops import load_json, ls_dir_special, read_text
from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
    sequence_results,
)

#: Where the archive and the decision record live, relative to the
#: repository root.
ARCHIVE = Path("reports/agent-bench")
ADR = Path("docs/adr/0001-proof-search-on-agda-mcp.md")

#: The shape of the numbers file this module writes.  v1 (Issue #215) added
#: the control, the archive's size, and the arms' days, tools, and readings;
#: v2 (Issue #219) dropped the control's archived column, since its `mcp`
#: arm is now the replayed Sonnet arm itself.  `build_site` refuses a file of
#: any other shape rather than render it.
SCHEMA = "agda-native-air.demo.numbers.v2"

#: The run ids of the two arms the page replays, and the model each ran:
#: the header-free re-runs of Issue #219.
SONNET_RUN = "suite219-sonnet5-mcp-1"
OPUS_RUN = "suite219-opus5-mcp-1"

#: The three arms of the control (Issue #162), one instrument each, re-run
#: header-free.  The `mcp` arm is the Sonnet arm the page replays: the four
#: runs of Issue #219 share one protocol, so one run serves both tables.
SHELL_RUN = "suite219-sonnet5-shell-1"
MCP_RUN = SONNET_RUN
BOTH_RUN = "suite219-sonnet5-both-1"

#: The Sonnet arm first measured with the fixture headers' hints in view
#: (Issue #154), the same model, server arm, and obligations.  The page reads
#: one thing from it, how the haystack tier was solved while each header
#: named its needle, and sets it beside the header-free arm's; no table
#: reads it.
HINTED_RUN = "agent-sonnet5-1"

#: Every run the page reads, each read once.
RUNS: Tuple[str, ...] = tuple(dict.fromkeys(
    (SONNET_RUN, OPUS_RUN, SHELL_RUN, MCP_RUN, BOTH_RUN, HINTED_RUN)))

#: The stratum rows, in the order the table prints them.
STRATA: Tuple[str, ...] = (
    "agda-stdlib",
    "agda-stdlib/haystack",
    "agda-algebras/using",
    "agda-algebras/wholesale",
)

#: The difficulty tiers, in order.
TIERS: Tuple[str, ...] = ("routine", "compositional", "non-obvious")

#: The ADR's name for the total row.
TOTAL = "total"

#: The caption lines that identify § 9's two header-free tables, as the ADR
#: writes them above each table (emphasis markers aside).  The dated tables
#: carry the same headers under captions of their own, so the caption, not
#: the header, is what tells them apart.
AGENT_CAPTION = ("The agent table, 2026-09-29, fixture headers stripped of "
                 "hints.")
CONTROL_CAPTION = ("The attribution table, 2026-09-29, fixture headers "
                   "stripped of hints.")

#: The header cells § 9's agent table must carry, lower-cased.
ADR_HEADER: Tuple[str, ...] = (
    "stratum", "n", "loop fixed", "loop retrieval",
    "sonnet 5 solved", "sonnet 5 restated",
    "opus 5 solved", "opus 5 restated",
)

#: § 9's attribution table: its arm columns, in the table's order, and the
#: run each one reports.  The `mcp` column is the same run the agent table's
#: Sonnet columns come from, so that one run is held to both tables.
CONTROL: Tuple[Tuple[str, str], ...] = (
    ("shell", SHELL_RUN),
    ("mcp", MCP_RUN),
    ("both", BOTH_RUN),
)

#: The header cells that identify the attribution table, lower-cased and with
#: the backticks the ADR sets the arm names in dropped.
CONTROL_HEADER: Tuple[str, ...] = ("stratum", "n") + tuple(
    column for column, _ in CONTROL)

#: One cell of the attribution table.  The ADR writes a tally in prose,
#: `9 solved` or `9 solved, 2 restated`, and leaves a zero restated count out
#: everywhere but the total row.
TALLY = re.compile(r"^(\d+) solved(?:, (\d+) restated)?$")

#: A caption line as the ADR writes it: the text, in emphasis or not.
CAPTION = re.compile(r"^\s*[*_]*(.+?)[*_]*\s*$")

#: A Markdown table row: the cells between the outer pipes.
ROW = re.compile(r"^\s*\|(.+)\|\s*$")

#: One cell of a table's delimiter row, the line under its header.
DELIMITER = re.compile(r"^:?-{3,}:?$")

#: How the harness names the server's tools in a transcript.
AGDA_PREFIX = "mcp__agda__"

#: A transcript record's `timestamp` opens with the UTC day it was written.
DAY = re.compile(r"^\d{4}-\d{2}-\d{2}")

#: How the harness records a session that ended on its own (the client's
#: `success`), as against a cap (`max_turns`, `budget`, `wall_cap`) or a
#: crash; see `Audit.terminalOf` in strux-driver.
COMPLETED = "completed"

#: The tier built so that the loop's fixed space cannot reach its needle
#: (Issue #129), which the page says measures a ranker and not a model.
HAYSTACK = "agda-stdlib/haystack"

#: The calls a session needs to read the staged file, edit it, and check it.
#: A session that made no others asked Agda nothing before its final check.
LEAST = frozenset({"Read", "Edit", AGDA_PREFIX + "check_file"})


@dataclass(frozen=True)
class Row:
    """One line of the agent table, as the page prints it."""

    stratum: str
    n: int
    loop_fixed: int
    loop_retrieval: int
    sonnet_solved: int
    sonnet_restated: int
    opus_solved: int
    opus_restated: int

    def as_dict(self) -> Dict[str, Any]:
        return {
            "stratum": self.stratum,
            "n": self.n,
            "loopFixed": self.loop_fixed,
            "loopRetrieval": self.loop_retrieval,
            "sonnetSolved": self.sonnet_solved,
            "sonnetRestated": self.sonnet_restated,
            "opusSolved": self.opus_solved,
            "opusRestated": self.opus_restated,
        }

    def agent_cells(self) -> Tuple[Tuple[str, int], ...]:
        """The cells this module recomputes, for `compare` to check."""
        return (
            ("n", self.n),
            ("Sonnet 5 solved", self.sonnet_solved),
            ("Sonnet 5 restated", self.sonnet_restated),
            ("Opus 5 solved", self.opus_solved),
            ("Opus 5 restated", self.opus_restated),
        )


@dataclass(frozen=True)
class Tally:
    """One arm over one slice: a cell of § 9's attribution table."""

    solved: int
    restated: int

    def __str__(self) -> str:
        return f"{self.solved} solved, {self.restated} restated"


@dataclass(frozen=True)
class ControlRow:
    """One line of the attribution table, one entry per arm in `CONTROL`
    order.  Each arm reports its own `n`, and each is checked."""

    stratum: str
    ns: Tuple[int, ...]
    tallies: Tuple[Tally, ...]

    def as_dict(self) -> Dict[str, Any]:
        return {
            "stratum": self.stratum,
            "n": self.ns[0],
            "cells": [{"column": column, "runId": run,
                       "solved": tally.solved, "restated": tally.restated}
                      for (column, run), tally in zip(CONTROL, self.tallies)],
        }


#: The attribution table as the ADR states it: stratum to (n, one tally per
#: arm in `CONTROL` order).
Stated = Dict[str, Tuple[int, Tuple[Tally, ...]]]


# ------------------------------------------------------- reading the ADR

def _cells(line: str) -> Optional[List[str]]:
    """The cells of a Markdown table row, bold markers stripped."""
    match = ROW.match(line)
    if match is None:
        return None
    return [cell.strip().strip("*").strip() for cell in
            match.group(1).split("|")]


def _header(cells: Sequence[str]) -> Tuple[str, ...]:
    """A header row as it is matched: lower-cased, backticks dropped."""
    return tuple(cell.replace("`", "").lower() for cell in cells)


def _caption(line: str) -> str:
    """A line's text with the emphasis markers around it dropped."""
    match = CAPTION.match(line)
    return match.group(1).strip() if match else ""


def _table(markdown: str, caption: str, header: Tuple[str, ...],
           name: str) -> Result[Dict[str, List[str]], PipelineError]:
    """The table under the line `caption`, as a map from its first cell to
    the rest.

    The caption must occur on exactly one line, the first line after it that
    is not blank must be the table's header, and that header must carry
    `header`'s cells: a caption that has moved off its table, or a table
    whose columns were renamed, is an error rather than a guess (Issue #219
    put two tables with one header set in § 9, the dated one and the
    header-free one, and a reader that searched by header would take
    whichever came first).  The cells exclude the first, so they line up
    with `header` from index 1.  The table is every row between its
    delimiter line and the first line that is not a table row, and it is
    read strictly: a missing delimiter, a row with the wrong number of
    cells, and a first cell that repeats are each an error naming the line.
    A lenient reader would end the table at a short row, so every row after
    it would be reported missing, and would let a repeated row silently
    replace the one before it.
    """
    lines = markdown.splitlines()

    def problem(number: int, why: str) -> Result[Dict[str, List[str]],
                                                 PipelineError]:
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR,
            f"ADR 0001's {name}, line {number}: {why}"))

    captions = [index for index, line in enumerate(lines)
                if _caption(line) == caption]
    if not captions:
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR,
            f"ADR 0001 has no table captioned {caption!r}"))
    if len(captions) > 1:
        return problem(captions[1] + 1, f"a second caption {caption!r}")
    found = next((index for index in range(captions[0] + 1, len(lines))
                  if lines[index].strip()), None)
    cells = _cells(lines[found]) if found is not None else None
    if found is None or cells is None:
        return problem(captions[0] + 1, f"the caption {caption!r} is not "
                                        "followed by a table")
    if _header(cells) != header:
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR,
            f"ADR 0001 has no table headed {' | '.join(header)} under "
            f"{caption!r} (line {found + 1} is headed "
            f"{' | '.join(_header(cells))})"))

    delimiter = _cells(lines[found + 1]) if found + 1 < len(lines) else None
    if delimiter is None or not all(DELIMITER.match(cell)
                                    for cell in delimiter):
        return problem(found + 2, "the line under the header is not the "
                                  "table's delimiter row")
    table: Dict[str, List[str]] = {}
    for number, body in enumerate(lines[found + 2:], start=found + 3):
        row = _cells(body)
        if row is None:
            break
        if len(row) != len(header):
            return problem(number, f"{len(row)} cells where the header has "
                                   f"{len(header)}: {body.strip()}")
        if row[0].lower() in table:
            return problem(number, f"a second row for {row[0]!r}")
        table[row[0].lower()] = row[1:]
    if not table:
        return problem(found + 1, "a header and no rows")
    return Result.ok(table)


def _counts(table: Dict[str, List[str]]
            ) -> Result[Dict[str, List[str]], PipelineError]:
    """The agent table, if every cell after the stratum is a count.

    The loop's columns are read from here as integers, so a cell that is
    not one would otherwise end the build in a traceback rather than a
    problem naming it.
    """
    bad = next(((stratum, ADR_HEADER[at + 1], cell)
                for stratum, cells in table.items()
                for at, cell in enumerate(cells) if not cell.isdigit()), None)
    if bad is not None:
        stratum, column, cell = bad
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR,
            f"ADR 0001's agent table, {stratum} / {column}: {cell!r} is not "
            "a count"))
    return Result.ok(table)


def adr_table(markdown: str) -> Result[Dict[str, List[str]], PipelineError]:
    """§ 9's agent table, as a map from stratum name to its cells."""
    return _table(markdown, AGENT_CAPTION, ADR_HEADER,
                  "agent table").and_then(_counts)


def _tally(stratum: str, column: str,
           cell: str) -> Result[Tally, PipelineError]:
    """One prose cell, read, or an error that quotes it."""
    match = TALLY.match(cell)
    if match is None:
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR,
            f"ADR 0001 § 9's attribution table, {stratum} / {column}: "
            f"{cell!r} is neither 'N solved' nor 'N solved, M restated'"))
    return Result.ok(Tally(int(match.group(1)), int(match.group(2) or 0)))


def _stated_row(stratum: str, cells: Sequence[str]
                ) -> Result[Tuple[int, Tuple[Tally, ...]], PipelineError]:
    """One row of the attribution table, every cell read."""
    if not cells[0].isdigit():
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR,
            f"ADR 0001 § 9's attribution table, {stratum} / n: "
            f"{cells[0]!r} is not a count"))
    tallies = sequence_results([
        _tally(stratum, column, cell)
        for (column, _), cell in zip(CONTROL, cells[1:])])
    return tallies.map(lambda read: (int(cells[0]), tuple(read)))


def control_table(markdown: str) -> Result[Stated, PipelineError]:
    """§ 9's attribution table, each prose cell read as a tally."""

    def read(table: Dict[str, List[str]]) -> Result[Stated, PipelineError]:
        names = list(table)
        rows = sequence_results([_stated_row(name, table[name])
                                 for name in names])
        return rows.map(lambda read_rows: dict(zip(names, read_rows)))

    return _table(markdown, CONTROL_CAPTION, CONTROL_HEADER,
                  "attribution table").and_then(read)


# ------------------------------------------------------ the agent table

def _stratum(report: Dict[str, Any], name: str) -> Dict[str, Any]:
    """One stratum's block of a run report, or an empty one."""
    block = (report.get("perStratum") or {}).get(name)
    return block if isinstance(block, dict) else {}


def _slice(report: Dict[str, Any], name: str) -> Dict[str, Any]:
    """A stratum's block, or the run's totals for the total row."""
    if name == TOTAL:
        totals = report.get("totals")
        return totals if isinstance(totals, dict) else {}
    return _stratum(report, name)


def rows_from_reports(sonnet: Dict[str, Any],
                      opus: Dict[str, Any],
                      loop: Dict[str, Tuple[int, int]]) -> Tuple[Row, ...]:
    """The table, with the agent columns taken from the two run reports.

    `loop` supplies the two columns the reports cannot: the proof-search
    loop's fixed-space and retrieval solve counts per stratum.
    """
    rows: List[Row] = []
    for name in STRATA:
        s, o = _stratum(sonnet, name), _stratum(opus, name)
        fixed, retrieval = loop.get(name, (0, 0))
        rows.append(Row(
            stratum=name,
            n=int(s.get("total", 0)),
            loop_fixed=fixed,
            loop_retrieval=retrieval,
            sonnet_solved=int(s.get("solved", 0)),
            sonnet_restated=int(s.get("restated", 0)),
            opus_solved=int(o.get("solved", 0)),
            opus_restated=int(o.get("restated", 0)),
        ))
    totals_s = sonnet.get("totals") or {}
    totals_o = opus.get("totals") or {}
    rows.append(Row(
        stratum=TOTAL,
        n=int(totals_s.get("total", 0)),
        loop_fixed=sum(row.loop_fixed for row in rows),
        loop_retrieval=sum(row.loop_retrieval for row in rows),
        sonnet_solved=int(totals_s.get("solved", 0)),
        sonnet_restated=int(totals_s.get("restated", 0)),
        opus_solved=int(totals_o.get("solved", 0)),
        opus_restated=int(totals_o.get("restated", 0)),
    ))
    return tuple(rows)


def loop_columns(table: Dict[str, List[str]]) -> Dict[str, Tuple[int, int]]:
    """The ADR's loop columns, which no report in this repository carries."""
    out: Dict[str, Tuple[int, int]] = {}
    for name in STRATA:
        cells = table.get(name.lower())
        if cells is None or len(cells) < 3:
            continue
        out[name] = (int(cells[1]), int(cells[2]))
    return out


def compare(rows: Sequence[Row],
            table: Dict[str, List[str]]) -> Tuple[str, ...]:
    """Every disagreement between the regenerated rows and the ADR's table.

    The columns this module recomputes are checked cell by cell.  The loop
    columns are read *from* the ADR's strata, so the one check they admit is
    the ADR's own arithmetic: the page prints their sums in its total row,
    and the ADR's total row must say the same.
    """
    #: The ADR column each recomputed cell sits in, as an index into the
    #: cells after the stratum name.
    at = {"n": 0, "Sonnet 5 solved": 3, "Sonnet 5 restated": 4,
          "Opus 5 solved": 5, "Opus 5 restated": 6}
    problems: List[str] = []
    for row in rows:
        cells = table.get(row.stratum.lower())
        if cells is None:
            problems.append(
                f"ADR 0001 § 9 has no row for stratum {row.stratum!r}")
            continue
        for column, value in row.agent_cells():
            stated = cells[at[column]]
            if stated != str(value):
                problems.append(
                    f"{row.stratum} / {column}: the archive says {value}, "
                    f"ADR 0001 § 9 says {stated}")
    for name in table:
        if name not in {row.stratum.lower() for row in rows}:
            problems.append(
                f"ADR 0001 § 9 has a row {name!r} the archive does not")
    total = next((row for row in rows if row.stratum == TOTAL), None)
    stated = table.get(TOTAL)
    if total is not None and stated is not None:
        for column, summed, said in (("loop fixed", total.loop_fixed,
                                      stated[1]),
                                     ("loop retrieval", total.loop_retrieval,
                                      stated[2])):
            if said != str(summed):
                problems.append(
                    f"total / {column}: the strata's cells sum to {summed}, "
                    f"ADR 0001 § 9's total says {said}")
    return tuple(problems)


# ------------------------------------------------ the attribution table

def control_rows(reports: Mapping[str, Dict[str, Any]]) -> Tuple[ControlRow, ...]:
    """The attribution table, every cell taken from its run's report."""
    def row(name: str) -> ControlRow:
        blocks = [_slice(reports.get(run) or {}, name) for _, run in CONTROL]
        return ControlRow(
            stratum=name,
            ns=tuple(int(block.get("total", 0)) for block in blocks),
            tallies=tuple(Tally(int(block.get("solved", 0)),
                                int(block.get("restated", 0)))
                          for block in blocks))
    return tuple(row(name) for name in STRATA + (TOTAL,))


def compare_control(rows: Sequence[ControlRow],
                    stated: Stated) -> Tuple[str, ...]:
    """Every disagreement between the regenerated attribution table and the
    ADR's, each naming the run whose report disagrees."""
    problems: List[str] = []
    for row in rows:
        found = stated.get(row.stratum.lower())
        if found is None:
            problems.append(f"ADR 0001 § 9's attribution table has no row "
                            f"for stratum {row.stratum!r}")
            continue
        n, tallies = found
        for (column, run), rn, tally, said in zip(CONTROL, row.ns,
                                                  row.tallies, tallies):
            if rn != n:
                problems.append(
                    f"{row.stratum} / n ({run}): the archive says {rn}, "
                    f"ADR 0001 § 9 says {n}")
            if tally != said:
                problems.append(
                    f"{row.stratum} / {column} ({run}): the archive says "
                    f"{tally}, ADR 0001 § 9 says {said}")
    names = {row.stratum.lower() for row in rows}
    problems += [f"ADR 0001 § 9's attribution table has a row {name!r} the "
                 "archive does not" for name in stated if name not in names]
    return tuple(problems)


# ------------------------------------------------- what the page is told

def per_tier(sonnet: Dict[str, Any], opus: Dict[str, Any]) -> Tuple[Dict[str, Any], ...]:
    """The by-tier counts, which the page prints beside the table."""
    def block(report: Dict[str, Any], tier: str) -> Dict[str, Any]:
        found = (report.get("perTier") or {}).get(tier)
        return found if isinstance(found, dict) else {}
    return tuple({
        "tier": tier,
        "n": int(block(sonnet, tier).get("total", 0)),
        "sonnetSolved": int(block(sonnet, tier).get("solved", 0)),
        "opusSolved": int(block(opus, tier).get("solved", 0)),
    } for tier in TIERS)


def _outcomes(report: Dict[str, Any]) -> List[Dict[str, Any]]:
    return [o for o in report.get("outcomes") or [] if isinstance(o, dict)]


def presented(report: Dict[str, Any]) -> Tuple[str, ...]:
    """The server's tools the run's subjects were presented, by bare name.

    Read from each subject's own isolation audit rather than from
    `config.tools`, which is the harness's allowlist: the attribution arms'
    allowlist names thirteen tools, and their subjects were presented
    fourteen (`search_in_scope`, from PR #161, is the one it omits).
    """
    names = {str(tool) for outcome in _outcomes(report)
             for tool in (outcome.get("isolation") or {})
             .get("agdaToolsPresented") or []}
    return tuple(sorted(_bare(name) for name in names))


def with_original(report: Dict[str, Any]) -> Dict[str, int]:
    """The rows with a library original, and the judge's reading of them.

    A stratum has an original when its rows restate a lemma the library
    proves (every agda-algebras row); its `solvedOriginalInView` is then a
    count, and null otherwise.  `inView` counts the solves for which a line
    of the original's own proof came back in a tool answer before the last
    edit (Issue #188); `reads` counts the successful calls that named the
    original's file, and `refusedReads` the ones the client refused.
    """
    strata = [block for block in (report.get("perStratum") or {}).values()
              if isinstance(block, dict)
              and block.get("solvedOriginalInView") is not None]
    originals = [o["original"] for o in _outcomes(report)
                 if isinstance(o.get("original"), dict)]
    return {
        "rows": sum(int(block.get("total", 0)) for block in strata),
        "solved": sum(int(block.get("solved", 0)) for block in strata),
        "inView": sum(int(block.get("solvedOriginalInView") or 0)
                      for block in strata),
        "reads": sum(int(o.get("reads") or 0) for o in originals),
        "refusedReads": sum(int(o.get("refusedReads") or 0)
                            for o in originals),
    }


def _bare(tool: str) -> str:
    """A tool's name without the prefix the client gives the server's."""
    return tool[len(AGDA_PREFIX):] if tool.startswith(AGDA_PREFIX) else tool


def quiet(report: Dict[str, Any], stratum: str = HAYSTACK) -> Dict[str, Any]:
    """How a run solved one stratum without asking Agda anything before its
    final check.

    `quiet` counts the solved rows whose sessions made no call beyond
    reading the file, editing it, and checking it, and `quietTurns` the turn
    counts those sessions took; `queries` totals every other call the
    stratum's remaining sessions made, by tool.
    """
    rows = [o for o in _outcomes(report) if o.get("stratum") == stratum]
    silent = [o for o in rows if o.get("solved")
              and set(o.get("toolCalls") or {}) <= LEAST]
    others = [o for o in rows if o not in silent]
    asked = sum((Counter({_bare(str(tool)): int(n) for tool, n
                          in (o.get("toolCalls") or {}).items()
                          if tool not in LEAST})
                 for o in others), Counter())
    return {
        "rows": len(rows),
        "solved": sum(1 for o in rows if o.get("solved")),
        "quiet": len(silent),
        "quietTurns": sorted({int(o.get("turns") or 0) for o in silent}),
        "others": [str(o.get("benchmarkId")) for o in others],
        "queries": dict(sorted(asked.items())),
    }


def arm_summary(report: Dict[str, Any], run_id: str) -> Dict[str, Any]:
    """One arm's headline totals, as the page states them."""
    totals = report.get("totals") or {}
    config = report.get("config") or {}
    tools = presented(report)
    return {
        "runId": run_id,
        "arm": config.get("arm"),
        "model": config.get("model"),
        "clientVersion": config.get("claudeVersion"),
        "turnCap": config.get("maxTurns"),
        "wallCapSec": config.get("wallCapSec"),
        "budgetCapUsd": config.get("maxBudgetUsd"),
        "parallelism": config.get("parallelism"),
        "agdaTools": list(tools),
        "toolCount": len(tools),
        "total": totals.get("total"),
        "solved": totals.get("solved"),
        "restated": totals.get("restated"),
        "gates": totals.get("gates") or {},
        "anomalies": totals.get("anomalies"),
        "completed": sum(1 for o in _outcomes(report)
                         if o.get("terminal") == COMPLETED),
        "turns": totals.get("turns"),
        "toolCalls": totals.get("toolCalls"),
        "costUsd": totals.get("costUsd"),
        "withOriginal": with_original(report),
        "haystack": quiet(report),
        "verdictVia": report.get("perVerdictVia") or {},
        "perShell": report.get("perShell") or {},
    }


def per_tool(report: Dict[str, Any]) -> Tuple[Tuple[str, int], ...]:
    """A run's per-tool call counts, most-called first."""
    counts = report.get("perTool") or {}
    return tuple(sorted(((str(k), int(v)) for k, v in counts.items()),
                        key=lambda pair: (-pair[1], pair[0])))


def _first_stamp(records: Sequence[Dict[str, Any]],
                 where: Path) -> Result[str, PipelineError]:
    """The first timestamp a transcript's records carry."""
    found = next((str(record["timestamp"]) for record in records
                  if DAY.match(str(record.get("timestamp") or ""))), None)
    if found is None:
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR, f"{where}: no record carries a timestamp"))
    return Result.ok(found)


def started_on(archive: Path, run: str,
               report: Dict[str, Any]) -> Result[str, PipelineError]:
    """The UTC day a run began: the earliest of its subjects' first stamps.

    `report.json` keeps no date a re-judge leaves alone (its `timestamp` is
    the re-judge's), and the transcripts are the run's own record of when it
    ran.  Every subject is read, not the first the report lists: the report
    is in index order, and the harness launches subjects in its own (in
    `agent-sonnet5-1` the report's first subject is the eleventh to start).
    The timestamps are ISO 8601 in UTC, so the least string is the earliest.
    """
    paths = [archive / run / str(o.get("transcriptPath"))
             for o in _outcomes(report) if o.get("transcriptPath")]
    if not paths:
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR, f"{run}: report.json names no transcript"))
    stamps = sequence_results([
        load_transcript(path).and_then(
            lambda records, where=path: _first_stamp(records, where))
        for path in paths])
    return stamps.map(lambda found: min(found)[:10])


# ----------------------------------------------------------------- build

@dataclass(frozen=True)
class Record:
    """What ADR 0001 § 9 states: the two tables this module checks."""

    agent: Dict[str, List[str]]
    control: Stated


@dataclass(frozen=True)
class Tables:
    """The two tables, regenerated from the archive."""

    rows: Tuple[Row, ...]
    control: Tuple[ControlRow, ...]


#: The kinds of value a report field may hold.  A count is an `int` and never
#: a `bool`, which Python would otherwise accept as one.
Kind = Tuple[type, ...]
COUNT: Kind = (int,)
NUMBER: Kind = (int, float)
TEXT: Kind = (str,)
TABLE: Kind = (dict,)
FLAG: Kind = (bool,)

#: Every field of a run's `report.json` that the page reads, and what it must
#: hold.  A report that lacks one is refused before anything reads it: the
#: readers below would otherwise default it (to zero, to nothing), and a
#: default standing in for a field the run never recorded is how a page comes
#: to print a zero, or "neither arm produced an anomaly", that no run measured.
REPORT_FIELDS: Tuple[Tuple[str, Kind], ...] = (
    ("config.model", TEXT), ("config.claudeVersion", TEXT),
    ("config.arm", TEXT), ("config.maxTurns", COUNT),
    ("config.wallCapSec", COUNT), ("config.maxBudgetUsd", NUMBER),
    ("config.parallelism", COUNT),
    ("totals.total", COUNT), ("totals.solved", COUNT),
    ("totals.restated", COUNT), ("totals.anomalies", COUNT),
    ("totals.turns", COUNT), ("totals.toolCalls", COUNT),
    ("totals.costUsd", NUMBER), ("totals.gates", TABLE),
    ("perTool", TABLE), ("perVerdictVia", TABLE), ("perShell", TABLE),
) + tuple(
    (f"perStratum.{name}.{field}", kind) for name in STRATA
    for field, kind in (("total", COUNT), ("solved", COUNT),
                        ("restated", COUNT),
                        ("solvedOriginalInView", COUNT + (type(None),)))
) + tuple(
    (f"perTier.{tier}.{field}", COUNT) for tier in TIERS
    for field in ("total", "solved"))

#: The same, for each row of a report's `outcomes`, and for a row's
#: `original` block when it has one (Issue #188).
OUTCOME_FIELDS: Tuple[Tuple[str, Kind], ...] = (
    ("benchmarkId", TEXT), ("stratum", TEXT), ("solved", FLAG),
    ("terminal", TEXT), ("turns", COUNT), ("toolCalls", TABLE),
    ("transcriptPath", TEXT), ("isolation.agdaToolsPresented", (list,)),
    ("original", (dict, type(None))),
)
ORIGINAL_FIELDS: Tuple[Tuple[str, Kind], ...] = (
    ("inView", FLAG), ("reads", COUNT), ("refusedReads", COUNT))

#: Marks a field that is not there, as distinct from one that holds `None`.
_ABSENT = object()


def _field(node: Any, path: str) -> Any:
    """The value at a dotted path (stratum names hold no dot), or _ABSENT."""
    for key in path.split("."):
        if not isinstance(node, dict) or key not in node:
            return _ABSENT
        node = node[key]
    return node


def _holds(value: Any, kind: Kind) -> bool:
    return isinstance(value, kind) and not (isinstance(value, bool)
                                            and bool not in kind)


def _missing(where: str, node: Any,
             fields: Sequence[Tuple[str, Kind]]) -> List[str]:
    """Each field of `fields` that `node` lacks or holds a wrong value in."""
    values = [(path, _field(node, path), kind) for path, kind in fields]
    return [f"{where}: no {path}" if value is _ABSENT
            else f"{where}: {path} is {value!r}"
            for path, value, kind in values
            if value is _ABSENT or not _holds(value, kind)]


def report_problems(run: str, report: Dict[str, Any]) -> Tuple[str, ...]:
    """Every field the page reads that a run's report lacks or holds wrongly."""
    where = f"{run}/report.json"
    outcomes = report.get("outcomes")
    if not isinstance(outcomes, list) or not outcomes:
        return tuple(_missing(where, report, REPORT_FIELDS)
                     + [f"{where}: no outcomes"])
    rows = [(f"{where}, outcome {at} ({_field(o, 'benchmarkId')})", o)
            for at, o in enumerate(outcomes)]
    return tuple(
        _missing(where, report, REPORT_FIELDS)
        + [p for row, o in rows for p in _missing(row, o, OUTCOME_FIELDS)]
        + [p for row, o in rows
           if isinstance(_field(o, "original"), dict)
           for p in _missing(row + ", original", o["original"],
                             ORIGINAL_FIELDS)])


def _well_formed(reports: Dict[str, Dict[str, Any]]
                 ) -> Result[Dict[str, Dict[str, Any]], PipelineError]:
    """The reports, or every field any of them lacks, listed at once."""
    problems = [problem for run, report in reports.items()
                for problem in report_problems(run, report)]
    if problems:
        shown = problems[:12] + (
            [f"and {len(problems) - 12} more"] if len(problems) > 12 else [])
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR,
            "the run reports lack what the page reads:\n  "
            + "\n  ".join(shown)))
    return Result.ok(reports)


def load_reports(archive: Path) -> Result[Dict[str, Dict[str, Any]], PipelineError]:
    """Every run's report, by run id, each holding every field the page
    reads (`REPORT_FIELDS`), or every field that one of them lacks."""
    return (sequence_results([load_json(archive / run / "report.json")
                              for run in RUNS])
            .map(lambda loaded: dict(zip(RUNS, loaded)))
            .and_then(_well_formed))


def read_record(adr: Path) -> Result[Record, PipelineError]:
    """Both of § 9's tables, read."""
    return read_text(adr).and_then(
        lambda text: adr_table(text).and_then(
            lambda agent: control_table(text).map(
                lambda control: Record(agent, control))))


def regenerate(reports: Mapping[str, Dict[str, Any]],
               record: Record) -> Tables:
    """Both tables from the archive; the loop columns from the record."""
    return Tables(
        rows=rows_from_reports(reports[SONNET_RUN], reports[OPUS_RUN],
                               loop_columns(record.agent)),
        control=control_rows(reports))


def check(tables: Tables, record: Record) -> Result[Tables, PipelineError]:
    """The regenerated tables, or every disagreement with the ADR at once."""
    problems = compare(tables.rows, record.agent) + \
        compare_control(tables.control, record.control)
    if problems:
        return Result.err(PipelineError(
            ErrorType.VALIDATION_ERROR,
            "the archive and ADR 0001 § 9 disagree:\n  "
            + "\n  ".join(problems)))
    return Result.ok(tables)


def start_days(archive: Path, reports: Mapping[str, Dict[str, Any]]
               ) -> Result[Dict[str, str], PipelineError]:
    """The day each run began, by run id."""
    return (sequence_results([started_on(archive, run, reports[run])
                              for run in RUNS])
            .map(lambda days: dict(zip(RUNS, days))))


def archive_size(archive: Path) -> Result[Dict[str, int], PipelineError]:
    """How many files the archive holds, and how many bytes of content.

    Bytes, not disk blocks: `du` reports more, and a page that said "14 MB"
    of an archive holding 9.3 MB of content was quoting the file system.
    """
    return ls_dir_special(archive, recursive=True).map(
        lambda files: {"files": len(files),
                       "bytes": sum(path.stat().st_size for path in files)})


@dataclass(frozen=True)
class Checked:
    """The run reports, and the two tables regenerated from them and found
    to agree with ADR 0001 § 9."""

    reports: Dict[str, Dict[str, Any]]
    tables: Tables


def validate(archive: Path, adr: Path) -> Result[Checked, PipelineError]:
    """The comparison alone: the five run reports and the ADR, and nothing
    else read.  `make demo-check` is this, so no file the comparison does
    not use (a transcript, the rest of the archive) can fail it."""
    return load_reports(archive).and_then(
        lambda reports: read_record(adr)
        .and_then(lambda record: check(regenerate(reports, record), record))
        .map(lambda tables: Checked(reports, tables)))


def build(archive: Path, adr: Path) -> Result[Dict[str, Any], PipelineError]:
    """Everything the page prints about the runs, or the first failure:
    `validate`, then what the page says in words, which also reads every
    subject's transcript (the day each run began) and walks the archive
    (its size)."""
    return validate(archive, adr).and_then(
        lambda checked: start_days(archive, checked.reports)
        .and_then(lambda days: archive_size(archive)
                  .map(lambda size: _assemble(checked.reports, checked.tables,
                                              days, size))))


def _arm(reports: Mapping[str, Dict[str, Any]], days: Mapping[str, str],
         run: str) -> Dict[str, Any]:
    return {**arm_summary(reports[run], run), "startedOn": days[run]}


def _assemble(reports: Mapping[str, Dict[str, Any]], tables: Tables,
              days: Mapping[str, str],
              size: Mapping[str, int]) -> Dict[str, Any]:
    """The numbers block the page is rendered from."""
    sonnet, opus = reports[SONNET_RUN], reports[OPUS_RUN]
    return {
        "schema": SCHEMA,
        "checkedAgainst": f"{ADR} § 9",
        "archive": {"path": str(ARCHIVE), **size},
        "rows": [row.as_dict() for row in tables.rows],
        "perTier": list(per_tier(sonnet, opus)),
        "arms": {
            "sonnet": _arm(reports, days, SONNET_RUN),
            "opus": _arm(reports, days, OPUS_RUN),
        },
        "perTool": {
            "sonnet": [list(pair) for pair in per_tool(sonnet)],
            "opus": [list(pair) for pair in per_tool(opus)],
        },
        "hinted": {"runId": HINTED_RUN,
                   "startedOn": days[HINTED_RUN],
                   "haystack": quiet(reports[HINTED_RUN])},
        "control": {
            "checkedAgainst": f"{ADR} § 9, the attribution arms",
            "columns": [column for column, _ in CONTROL],
            "arms": [_arm(reports, days, run) for _, run in CONTROL],
            "rows": [row.as_dict() for row in tables.control],
            "perTool": {run: [list(pair) for pair in per_tool(reports[run])]
                        for _, run in CONTROL},
        },
    }


# ------------------------------------------------------------------ main

def main(argv: Optional[Sequence[str]] = None) -> int:
    """`make demo-check`: `validate`, writing nothing."""
    parser = argparse.ArgumentParser(
        description="Check the demo page's two § 9 tables against ADR 0001.")
    parser.add_argument("--repo", type=Path, default=Path("."),
                        help="the repository root (default: .)")
    args = parser.parse_args(argv)

    outcome = validate(args.repo / ARCHIVE, args.repo / ADR)
    if outcome.is_err:
        print(f"demo-check: {outcome.unwrap_err()}", file=sys.stderr)
        return 1
    tables = outcome.unwrap().tables
    print(f"demo-check: {len(RUNS)} run reports agree with {ADR} § 9: the "
          f"agent table's {len(tables.rows)} rows and the attribution "
          f"table's {len(tables.control)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
