#!/usr/bin/env python3
"""
File: scripts/python/demo/build_data.py

Description: `make demo-data`.  Read the committed agent-bench archive and
  write the demo site's data (Issue #85).

  The archive is 1,051 files and 14 MB, and none of it is shipped to a
  browser.  This step reduces it to what the page states: one JSON per replay
  (the roster in `replays.ROSTER`), and one JSON holding the benchmark table
  and the two arms' headline totals.  Both are written under `data/demo/`,
  which is gitignored: the page is rebuilt from the archive, never from a
  committed copy of its own output.

  The step refuses to write anything if a number disagrees with ADR 0001 § 9
  or if an absolute path survived normalization, so a page that cannot be
  trusted is a build failure rather than a published claim.

Usage:

    PYTHONPATH=. python3 -m scripts.python.demo.build_data [--out data/demo]

Design Principles:
  +  `main` parses arguments and turns a `Result` into an exit code; every
     other function here is total and returns a `Result`.
  +  One report read per arm, not per subject: the arm's model id is a
     property of the run, and the replays are handed it.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

from scripts.python.demo import numbers
from scripts.python.demo.replays import ROSTER, build_replay, index_rows
from scripts.python.utils.file_ops import load_json, write_text
from scripts.python.utils.pipeline_types import (
    PipelineError,
    Result,
    sequence_results,
)

#: Where the archive, the index, and the decision record live, relative to the
#: repository root.
ARCHIVE = Path("reports/agent-bench")
INDEX = Path("data/benchmarks/benchmark-index.jsonl")
ADR = Path("docs/adr/0001-proof-search-on-agda-mcp.md")

#: The default output directory, gitignored like every other `data/` output.
DEFAULT_OUT = Path("data/demo")

DATA_SCHEMA = "agda-native-air.demo.v0"


def write_pretty(path: Path, data: Any) -> Result[None, PipelineError]:
    """Write JSON without escaping the astral glyphs the content is full of.

    `file_ops.write_json` is `json.dumps`' default, which would turn every
    `𝑨` and `≅` into a `\\uXXXX` pair: correct JSON, but it triples the file
    and makes the generated data unreadable to anyone checking it by eye.
    """
    return write_text(path, json.dumps(data, ensure_ascii=False, indent=2,
                                       sort_keys=False) + "\n")


def arm_models(archive: Path) -> Result[Dict[str, str], PipelineError]:
    """Each arm's model id, read once from its run report."""
    runs = sorted({choice.run for choice in ROSTER})
    reports = [load_json(archive / run / "report.json") for run in runs]
    return sequence_results(reports).map(
        lambda loaded: {run: str((report.get("config") or {}).get("model", ""))
                        for run, report in zip(runs, loaded)})


def build_replays(archive: Path, repo: Path,
                  rows: Dict[str, Dict[str, Any]],
                  models: Dict[str, str]) -> Result[List[Dict[str, Any]], PipelineError]:
    """Every replay of the roster, in tab order."""
    return sequence_results([
        build_replay(archive, repo, rows, choice, models.get(choice.run, ""))
        for choice in ROSTER
    ])


def manifest(replays: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    """The index the page's builder reads: one entry per replay, in order."""
    return {
        "schema": DATA_SCHEMA,
        "command": "make demo-data",
        "archive": str(ARCHIVE),
        "replays": [
            {
                "file": f"{replay['id']}.json",
                "id": replay["id"],
                "label": replay["label"],
                "modelLabel": replay["modelLabel"],
                "subject": replay["subject"],
                "run": replay["run"],
                "verdict": replay["verdict"]["kind"],
            }
            for replay in replays
        ],
    }


def emit(out: Path, replays: Sequence[Dict[str, Any]],
         table: Dict[str, Any]) -> Result[List[Path], PipelineError]:
    """Write the manifest, every replay, and the table.

    Each write is mapped to the path it wrote before the list is sequenced:
    `write_text` succeeds with `None`, and `Result.unwrap` (which
    `sequence_results` calls) treats a `None` success as an invalid state.
    """
    files = [(out / "manifest.json", manifest(replays))]
    files += [(out / f"{replay['id']}.json", replay) for replay in replays]
    files.append((out / "numbers.json", table))
    return sequence_results([write_pretty(path, data).map(lambda _, p=path: p)
                             for path, data in files])


def run(repo: Path, out: Path) -> Result[Tuple[int, int], PipelineError]:
    """Build everything; on success report how many replays and rows landed."""
    archive = repo / ARCHIVE

    def with_rows(rows: Dict[str, Dict[str, Any]]) -> Result[Tuple[int, int], PipelineError]:
        return (arm_models(archive)
                .and_then(lambda models: build_replays(archive, repo, rows,
                                                       models))
                .and_then(lambda replays:
                          numbers.build(archive, repo / ADR)
                          .and_then(lambda table:
                                    emit(out, replays, table)
                                    .map(lambda _: (len(replays),
                                                    len(table["rows"]))))))

    return index_rows(repo / INDEX).and_then(with_rows)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build the demo site's data from reports/agent-bench/.")
    parser.add_argument("--repo", type=Path, default=Path("."),
                        help="the repository root (default: .)")
    parser.add_argument("--out", type=Path, default=None,
                        help=f"output directory (default: {DEFAULT_OUT})")
    args = parser.parse_args(argv)
    out = args.out if args.out is not None else args.repo / DEFAULT_OUT

    outcome = run(args.repo, out)
    if outcome.is_err:
        print(f"demo-data: {outcome.unwrap_err()}", file=sys.stderr)
        return 1
    replays, rows = outcome.unwrap()
    print(f"demo-data: {replays} replays and a {rows}-row table -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
