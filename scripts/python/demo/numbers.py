#!/usr/bin/env python3
"""
File: scripts/python/demo/numbers.py

Description: The demo page's benchmark table, regenerated from the archived
  run reports and checked against ADR 0001 § 9 (Issue #85).

  The page carries the 55-row table that ADR 0001 § 9, "The agent in the
  loop", states.  Transcribing it would be how a page and a decision record
  come to disagree, so the agent columns are recomputed here from each arm's
  own `report.json` and then compared with the ADR's table cell for cell.  The
  comparison is `compare`, which `make demo-check` and a pytest case both run,
  so a number that drifts fails a build rather than a reading.

  Two of the table's columns are not the agents': "loop fixed" and "loop
  retrieval" are the proof-search loop's solve counts under the same suite and
  the same verifier, and they have no machine-readable source in this
  repository.  They are taken from the ADR, which is their record, and the
  page says so where it prints them.

Design Principles:
  +  One canonical stratum order.  `report.json` is a JSON object, so its key
     order is an artifact of how the harness wrote it; the table's order is
     declared here and the ADR's rows are matched to it by name.
  +  The ADR is parsed, not assumed.  `adr_table` finds the one table in the
     document whose header carries this column set, so a new table elsewhere
     in § 9 cannot be picked up by accident and a renamed column fails loudly.
  +  Differences are values.  `compare` returns the list of disagreements
     rather than raising, so a caller can print all of them at once.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from scripts.python.utils.file_ops import load_json, read_text
from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
)

#: The run ids of the two arms the ADR quotes, and the model each ran.
SONNET_RUN = "agent-sonnet5-1"
OPUS_RUN = "agent-opus5-1"

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

#: The header cells that identify § 9's agent table, lower-cased.  The
#: document has many tables; this is the only one with these columns.
ADR_HEADER: Tuple[str, ...] = (
    "stratum", "n", "loop fixed", "loop retrieval",
    "sonnet 5 solved", "sonnet 5 restated",
    "opus 5 solved", "opus 5 restated",
)

#: A Markdown table row: the cells between the outer pipes.
ROW = re.compile(r"^\s*\|(.+)\|\s*$")


@dataclass(frozen=True)
class Row:
    """One line of the table, as the page prints it."""

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


def _cells(line: str) -> Optional[List[str]]:
    """The cells of a Markdown table row, bold markers stripped."""
    match = ROW.match(line)
    if match is None:
        return None
    return [cell.strip().strip("*").strip() for cell in
            match.group(1).split("|")]


def adr_table(markdown: str) -> Result[Dict[str, List[str]], PipelineError]:
    """§ 9's agent table, as a map from stratum name to its cells.

    The cells exclude the stratum itself, so they line up with `ADR_HEADER`
    from index 1.
    """
    lines = markdown.splitlines()
    for index, line in enumerate(lines):
        cells = _cells(line)
        if cells is None:
            continue
        if tuple(cell.lower() for cell in cells) != ADR_HEADER:
            continue
        table: Dict[str, List[str]] = {}
        for body in lines[index + 2:]:
            row = _cells(body)
            if row is None or len(row) != len(ADR_HEADER):
                break
            table[row[0].lower()] = row[1:]
        if not table:
            return Result.err(PipelineError(
                ErrorType.PARSING_ERROR,
                "ADR 0001's agent table has a header and no rows"))
        return Result.ok(table)
    return Result.err(PipelineError(
        ErrorType.PARSING_ERROR,
        "ADR 0001 has no table headed " + " | ".join(ADR_HEADER)))


def _stratum(report: Dict[str, Any], name: str) -> Dict[str, Any]:
    """One stratum's block of a run report, or an empty one."""
    block = (report.get("perStratum") or {}).get(name)
    return block if isinstance(block, dict) else {}


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

    Only the columns this module recomputes are checked: the loop columns are
    read *from* the ADR, so checking them against it would prove nothing.
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
    return tuple(problems)


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


def arm_summary(report: Dict[str, Any], run_id: str) -> Dict[str, Any]:
    """One arm's headline totals, as the page's caption states them."""
    totals = report.get("totals") or {}
    config = report.get("config") or {}
    return {
        "runId": run_id,
        "model": config.get("model"),
        "clientVersion": config.get("claudeVersion"),
        "turnCap": config.get("maxTurns"),
        "wallCapSec": config.get("wallCapSec"),
        "budgetCapUsd": config.get("maxBudgetUsd"),
        "toolCount": len([t for t in (config.get("tools") or [])
                          if str(t).startswith("mcp__agda__")]),
        "total": totals.get("total"),
        "solved": totals.get("solved"),
        "restated": totals.get("restated"),
        "gates": totals.get("gates") or {},
        "anomalies": totals.get("anomalies"),
        "turns": totals.get("turns"),
        "toolCalls": totals.get("toolCalls"),
        "costUsd": totals.get("costUsd"),
    }


def per_tool(report: Dict[str, Any]) -> Tuple[Tuple[str, int], ...]:
    """A run's per-tool call counts, most-called first."""
    counts = report.get("perTool") or {}
    return tuple(sorted(((str(k), int(v)) for k, v in counts.items()),
                        key=lambda pair: (-pair[1], pair[0])))


def build(archive: Path, adr: Path) -> Result[Dict[str, Any], PipelineError]:
    """The whole table block, regenerated and checked, or the first failure."""

    def with_reports(sonnet: Dict[str, Any]) -> Result[Dict[str, Any], PipelineError]:
        return (load_json(archive / OPUS_RUN / "report.json")
                .and_then(lambda opus: read_text(adr)
                          .and_then(adr_table)
                          .and_then(lambda table:
                                    _assemble(sonnet, opus, table))))

    return (load_json(archive / SONNET_RUN / "report.json")
            .and_then(with_reports))


def _assemble(sonnet: Dict[str, Any], opus: Dict[str, Any],
              table: Dict[str, List[str]]) -> Result[Dict[str, Any], PipelineError]:
    """Build the rows, then refuse to emit them if the ADR disagrees."""
    rows = rows_from_reports(sonnet, opus, loop_columns(table))
    problems = compare(rows, table)
    if problems:
        return Result.err(PipelineError(
            ErrorType.VALIDATION_ERROR,
            "the archive and ADR 0001 § 9 disagree:\n  "
            + "\n  ".join(problems)))
    return Result.ok({
        "schema": "agda-native-air.demo.numbers.v0",
        "checkedAgainst": "docs/adr/0001-proof-search-on-agda-mcp.md § 9",
        "rows": [row.as_dict() for row in rows],
        "perTier": list(per_tier(sonnet, opus)),
        "arms": {
            "sonnet": arm_summary(sonnet, SONNET_RUN),
            "opus": arm_summary(opus, OPUS_RUN),
        },
        "perTool": {
            "sonnet": [list(pair) for pair in per_tool(sonnet)],
            "opus": [list(pair) for pair in per_tool(opus)],
        },
    })
