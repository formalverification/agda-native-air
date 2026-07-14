#!/usr/bin/env python3
# =============================================================================
# normalize_bench_report.py
#
# File: scripts/python/normalize_bench_report.py
#
# Purpose
# -------
# Normalize a benchmark gold-verification report (as written by
# struxdriver.benchmark.EvalBenchmark --verify-gold) for determinism
# comparison.  The report intentionally records wall-clock timing as a metric —
# a top-level `timestamp` and a per-obligation `elapsedMs` — which legitimately
# varies between runs.  This filter strips exactly those fields and re-emits the
# report as canonical JSON (sorted keys, stable indentation), so that two runs
# over the same inputs are byte-identical.
#
# In other words: the benchmark is deterministic *modulo* wall-clock.  Wall-clock
# is kept in the raw report; only the determinism *comparison* ignores it.  This
# mirrors the agda-dojang determinism lane in CI, which pops `elapsedMs` before
# diffing.
#
# Usage
# -----
#   normalize_bench_report.py <report.json>      # writes canonical JSON to stdout
# =============================================================================
"""Strip wall-clock fields from a benchmark report and emit canonical JSON."""

import json
import signal
import sys

# Emit cleanly when piped into a reader that closes early (e.g. `| head`).
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):  # SIGPIPE is unavailable on some platforms.
    pass


def normalize(report: dict) -> dict:
    """Strip the volatile wall-clock fields from the report (in place) and return it."""
    report.pop("timestamp", None)
    for result in report.get("results", []):
        if isinstance(result, dict):
            result.pop("elapsedMs", None)
    return report


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: normalize_bench_report.py <report.json>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as handle:
        report = json.load(handle)
    json.dump(
        normalize(report),
        sys.stdout,
        ensure_ascii=False,
        sort_keys=True,
        indent=2,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
