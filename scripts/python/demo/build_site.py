#!/usr/bin/env python3
"""
File: scripts/python/demo/build_site.py

Description: `make demo-site`.  Render the demo page from the data
  `make demo-data` wrote, and copy the page's own assets beside it (Issue
  #85).

  The output is a directory a static host can serve as it stands: one HTML
  file with every session's text already in it, plus the stylesheet, the
  replay script, and a favicon.  Nothing is fetched at page load, from this
  origin or any other, so the page works behind a firewall, from a file://
  URL, and in a crawler.

  Both the output directory and the data directory are gitignored.  The page
  is rebuilt from the committed archive, in CI and by anyone who runs the two
  targets; a generated page is never a commit.

Usage:

    PYTHONPATH=. python3 -m scripts.python.demo.build_site \\
        [--data data/demo] [--out site]

Design Principles:
  +  Refuse rather than publish something stale.  The build reads the
     manifest `make demo-data` wrote and fails if a replay it lists is
     missing, so a half-written data directory cannot become a page.
  +  Assets are copied, not inlined.  A reader can view the stylesheet and
     the script, and a browser can cache them; the *content* is inline, which
     is what makes the page complete without JavaScript.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, Dict, List, Sequence

from scripts.python.demo import render
from scripts.python.utils.file_ops import (
    cp_file,
    ensure_dir_exists,
    load_json,
    write_text,
)
from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
    sequence_results,
)

#: Committed page assets, relative to the repository root.
ASSETS = Path("web/assets")

#: Defaults, matching `build_data`'s and the Makefile's.
DEFAULT_DATA = Path("data/demo")
DEFAULT_OUT = Path("site")


def read_data(data: Path) -> Result[Dict[str, Any], PipelineError]:
    """The manifest and everything it lists, decoded."""

    def with_manifest(manifest: Dict[str, Any]) -> Result[Dict[str, Any], PipelineError]:
        listed = manifest.get("replays")
        if not isinstance(listed, list) or not listed:
            return Result.err(PipelineError(
                ErrorType.VALIDATION_ERROR,
                f"{data}/manifest.json lists no replays; run `make demo-data`"))
        replays = sequence_results(
            [load_json(data / str(entry.get("file"))) for entry in listed])
        return replays.and_then(
            lambda loaded: load_json(data / "numbers.json").map(
                lambda numbers: {"manifest": manifest,
                                 "replays": loaded,
                                 "numbers": numbers}))

    return load_json(data / "manifest.json").and_then(with_manifest)


def copy_assets(repo: Path, out: Path) -> Result[List[Path], PipelineError]:
    """The stylesheet, the script, and the favicon, beside the page."""
    source = repo / ASSETS
    if not source.is_dir():
        return Result.err(PipelineError(
            ErrorType.FILE_NOT_FOUND, f"no page assets at {source}"))
    files = sorted(path for path in source.iterdir() if path.is_file())
    if not files:
        return Result.err(PipelineError(
            ErrorType.FILE_NOT_FOUND, f"{source} holds no assets"))
    return ensure_dir_exists(out / "assets").and_then(
        lambda target: sequence_results(
            [cp_file(path, target / path.name) for path in files]))


def build(repo: Path, data: Path, out: Path) -> Result[int, PipelineError]:
    """Render the page and copy the assets; report the page's size in bytes."""

    def with_data(loaded: Dict[str, Any]) -> Result[int, PipelineError]:
        html = render.page(loaded)
        return (copy_assets(repo, out)
                .and_then(lambda _: write_text(out / "index.html", html))
                .map(lambda _: len(html.encode("utf-8"))))

    return read_data(data).and_then(with_data)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Render the demo page from the data build's output.")
    parser.add_argument("--repo", type=Path, default=Path("."),
                        help="the repository root (default: .)")
    parser.add_argument("--data", type=Path, default=None,
                        help=f"input directory (default: {DEFAULT_DATA})")
    parser.add_argument("--out", type=Path, default=None,
                        help=f"output directory (default: {DEFAULT_OUT})")
    args = parser.parse_args(argv)
    data = args.data if args.data is not None else args.repo / DEFAULT_DATA
    out = args.out if args.out is not None else args.repo / DEFAULT_OUT

    outcome = build(args.repo, data, out)
    if outcome.is_err:
        print(f"demo-site: {outcome.unwrap_err()}", file=sys.stderr)
        return 1
    print(f"demo-site: {outcome.unwrap():,} bytes -> {out}/index.html")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
