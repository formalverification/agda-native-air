#!/usr/bin/env python3
"""
agent_bridge.py
===============

File: agda-jang/python/tools/agent_bridge.py

Purpose
-------
A tiny, deterministic v0 "agent loop" bridge:

  (1) locate the next hole in an Agda file
  (2) ask Agda to *report* (goal, context) at that hole
  (3) query a policy backend with (goal, context)
  (4) try top-k candidate terms by patching the hole and re-checking with Agda
  (5) repeat until we've solved N holes or there are no holes left

This is designed to make Issue #23's "propose/check/refine" loop work *before*
any ML exists, using the scripted fixture policy.

Key constraints / design choices
--------------------------------
- Non-destructive: never overwrites the input file.
- Deterministic: left-to-right, top-to-bottom hole order; deterministic policy.
- Minimal coupling: shells out to `agda` and parses tagged markers from output.
- Functional style: pure helpers for parsing/rendering; controlled side effects.

Assumptions
-----------
1) The file is typecheckable under our Agda setup (flags, libraries, includes).
2) There exists an Agda macro in scope (via imports) that emits a goal+context
   report with markers parseable by tools.report_parser.parse_goalctx_report.

   For example, our macro could be named `reportGoalCtx` and be used as:
     reportGoalCtx ?
   in a hole position (or equivalently inserted by this bridge).

CLI example (repo root, via agda-jang Makefile)
-----------------------------------------------
  PYTHONPATH=agda-jang/python \
    python3 agda-jang/python/tools/agent_bridge.py \
      --input  data/agda/FixtureHoles.agda \
      --output _build/FixtureHoles.solved.agda \
      --agda-bin agda \
      --agda-flags "-i agda --library-file=agda/libraries -l agda-jang -i data/agda" \
      --max-holes 10 \
      --k 5

Exit code
---------
0 on success (solved requested holes or file has no holes), nonzero on failure.

IMPORTANT NOTES
---------------
-  This bridge inserts `open import AgdaJang.Debug` into the working copy if missing
   (output will include it if needed).
-  It expects our macro to be available as `reportGoalCtx ?` by default; override
with `--report-macro` if you choose a different name.


"""

from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

from tools.report_parser import (
    has_req_markers,
    parse_goalctx_report,
)

# -------------------------
# Domain types (immutable)
# -------------------------

@dataclass(frozen=True)
class ProcResult:
    """Result of a subprocess invocation."""
    rc: int
    stdout: str
    stderr: str

    @property
    def combined(self) -> str:
        """Stable combined stream for marker parsing."""
        if self.stderr:
            return (self.stdout or "") + ("\n" if self.stdout and not self.stdout.endswith("\n") else "") + self.stderr
        return self.stdout or ""


@dataclass(frozen=True)
class CtxEntry:
    """A single context binder entry."""
    name: str
    type: str
    visibility: str  # "visible" | "hidden" | "instance" | ...


@dataclass(frozen=True)
class GoalCtx:
    """The (goal, context) payload we send to policies."""
    goal: str
    context: Tuple[CtxEntry, ...]


@dataclass(frozen=True)
class Candidate:
    """A single candidate proposal returned by the policy backend."""
    term: str
    score: float
    meta: Dict[str, Any]


@dataclass(frozen=True)
class BridgeCfg:
    """All configuration needed for the bridge run."""
    agda_bin: str
    agda_flags: Tuple[str, ...]
    input_path: Path
    output_path: Path
    policy_script: Path
    k: int
    max_holes: int
    keep_workdir: bool
    allow_unsolved_metas: bool
    # Which macro do we insert for goal/context reporting?
    report_macro_expr: str  # e.g. "reportGoalCtx ?"
    # Ensure these imports are present in the working file
    required_open_imports: Tuple[str, ...]


@dataclass(frozen=True)
class HoleSpan:
    """A span in a source file corresponding to a hole."""
    start: int
    end: int
    kind: str  # "braced" for "{!!}", "qmark" for "?"

    def slice(self) -> slice:
        return slice(self.start, self.end)


# -------------------------
# Small pure utilities
# -------------------------

_BOUNDARY_CHARS = set(" \t\r\n()[]{};,:.=+-*/<>|&!@#$%^~`'\\\"")


def _is_boundary(ch: str) -> bool:
    return (ch == "") or (ch in _BOUNDARY_CHARS)


def _split_flags(flags: str) -> Tuple[str, ...]:
    """
    Split a flag string into argv tokens.
    Mirrors the style used in jang_try.py (shlex-based, robust).
    """
    toks = tuple(shlex.split(flags)) if flags else tuple()
    # defensive: drop dangling "-l" which can happen in some ad-hoc scripts
    if toks and toks[-1] == "-l":
        return toks[:-1]
    return toks


def ensure_required_imports(source: str, required_open_imports: Sequence[str]) -> str:
    """
    Ensure `open import ...` lines exist in the module, inserting them after
    the `module ... where` line (first occurrence).

    Pure function: returns new source text.
    """
    req = [ln.strip() for ln in required_open_imports if ln.strip()]
    if not req:
        return source

    # Fast path: all present
    missing = [ln for ln in req if ln not in source]
    if not missing:
        return source

    lines = source.splitlines(keepends=True)

    # Find module header line
    insert_at: Optional[int] = None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("module ") and " where" in ln:
            insert_at = i + 1
            break

    # If we can’t find a module header, append at the top (still safe for demo files)
    if insert_at is None:
        insert_at = 0

    block = ""
    # Keep formatting stable: one blank line, imports, one blank line
    block += "\n" if (insert_at > 0 and (insert_at <= len(lines)) and (not lines[insert_at - 1].endswith("\n"))) else ""
    block += "\n".join(missing) + "\n\n"

    new_lines = list(lines)
    new_lines.insert(insert_at, block)
    return "".join(new_lines)


def replace_span(text: str, span: HoleSpan, replacement: str) -> str:
    """Pure string splice."""
    return text[: span.start] + replacement + text[span.end :]


def scan_next_hole(source: str) -> Optional[HoleSpan]:
    """
    Find the next hole in the file, skipping:
      - line comments starting with `--`
      - block comments delimited by `{-` ... `-}` (non-nested handling is *good enough* for v0;
        we support simple nesting anyway)
      - string literals "..."

    Hole forms supported:
      - `{!!}` (preferred for fixtures)
      - `?` (as a standalone token, best-effort boundary checks)

    Deterministic: returns first occurrence in lexical order.
    """
    i = 0
    n = len(source)

    in_line_comment = False
    in_string = False
    block_depth = 0

    while i < n:
        # Line comment
        if in_line_comment:
            if source[i] == "\n":
                in_line_comment = False
            i += 1
            continue

        # String literal
        if in_string:
            if source[i] == "\\" and i + 1 < n:
                i += 2
                continue
            if source[i] == "\"":
                in_string = False
            i += 1
            continue

        # Block comment (handle shallow nesting)
        if block_depth > 0:
            if source.startswith("{-", i):
                block_depth += 1
                i += 2
                continue
            if source.startswith("-}", i):
                block_depth -= 1
                i += 2
                continue
            i += 1
            continue

        # Enter comment/string
        if source.startswith("--", i):
            in_line_comment = True
            i += 2
            continue
        if source.startswith("{-", i):
            block_depth = 1
            i += 2
            continue
        if source[i] == "\"":
            in_string = True
            i += 1
            continue

        # Hole: {!!}
        if source.startswith("{!!}", i):
            return HoleSpan(start=i, end=i + 4, kind="braced")

        # Hole: ? (best-effort standalone token)
        if source[i] == "?":
            prev = source[i - 1] if i > 0 else ""
            nxt = source[i + 1] if i + 1 < n else ""
            if _is_boundary(prev) and _is_boundary(nxt):
                return HoleSpan(start=i, end=i + 1, kind="qmark")

        i += 1

    return None


def count_holes(source: str) -> int:
    """Count holes by repeatedly scanning; pure and deterministic."""
    cnt = 0
    s = source
    while True:
        h = scan_next_hole(s)
        if h is None:
            return cnt
        cnt += 1
        # remove the first hole to continue scanning after it
        s = replace_span(s, h, " ")  # preserve indices roughly; we just need count


# -------------------------
# Subprocess boundary
# -------------------------

def run_process(cmd: Sequence[str], timeout_s: Optional[float]) -> ProcResult:
    """
    Minimal subprocess runner.
    We always capture stdout+stderr; callers decide how to interpret rc.
    """
    p = subprocess.run(
        list(cmd),
        capture_output=True,
        text=True,
        timeout=timeout_s,
    )
    return ProcResult(rc=p.returncode, stdout=p.stdout or "", stderr=p.stderr or "")


def agda_check(
    cfg: BridgeCfg,
    file_path: Path,
    timeout_s: Optional[float],
    allow_unsolved: bool,
) -> ProcResult:
    """
    Invoke `agda` on the given file. If allow_unsolved is True, pass
    `--allow-unsolved-metas` unless already present in agda_flags.
    """
    flags = list(cfg.agda_flags)
    if allow_unsolved and "--allow-unsolved-metas" not in flags:
        flags.append("--allow-unsolved-metas")
    cmd = [cfg.agda_bin, *flags, str(file_path)]
    return run_process(cmd, timeout_s=timeout_s)


# -------------------------
# Policy boundary
# -------------------------

def parse_candidates(resp: Dict[str, Any]) -> List[Candidate]:
    """
    Parse a policy response:
      { "candidates": [ { "term": "...", "score": 1.0, "meta": {...} }, ... ] }
    """
    raw = resp.get("candidates", [])
    if not isinstance(raw, list):
        return []
    out: List[Candidate] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        term = str(item.get("term", "")).strip()
        if not term:
            continue
        score = float(item.get("score", 0.0) or 0.0)
        meta = item.get("meta", {})
        if not isinstance(meta, dict):
            meta = {}
        out.append(Candidate(term=term, score=score, meta=dict(meta)))
    return out


def call_policy(
    cfg: BridgeCfg,
    goalctx: GoalCtx,
    timeout_s: Optional[float],
) -> List[Candidate]:
    """
    Call the policy backend as a subprocess:
      python policy_fixture.py --in - --out - --k K

    Returns candidate list (possibly empty). Raises on malformed JSON output.
    """
    req: Dict[str, Any] = {
        "schemaVersion": "goalctx.v0",
        "goal": goalctx.goal,
        "context": [
            {"name": e.name, "type": e.type, "visibility": e.visibility}
            for e in goalctx.context
        ],
    }

    cmd = [
        sys.executable,
        str(cfg.policy_script),
        "--in",
        "-",
        "--out",
        "-",
        "--k",
        str(cfg.k),
    ]
    p = subprocess.run(cmd, input=json.dumps(req), capture_output=True, text=True, timeout=timeout_s)
    out = (p.stdout or "").strip()
    if not out:
        raise ValueError(f"policy produced empty stdout (rc={p.returncode})")
    resp = json.loads(out)
    if not isinstance(resp, dict):
        raise ValueError("policy response is not a JSON object")
    return parse_candidates(resp)


# -------------------------
# Bridge loop (pure-ish core)
# -------------------------

def extract_goalctx_from_report(output: str) -> GoalCtx:
    """
    Parse a tagged goal/context report from Agda output.
    Delegates to tools.report_parser.parse_goalctx_report.
    """
    rep = parse_goalctx_report(output)

    goal = str(rep.get("goal", "")).strip()
    if not goal:
        raise ValueError("goalctx report missing goal")

    ctx_list: List[CtxEntry] = []
    raw_ctx = rep.get("context", [])
    if isinstance(raw_ctx, list):
        for item in raw_ctx:
            if not isinstance(item, dict):
                continue
            ctx_list.append(
                CtxEntry(
                    name=str(item.get("name", "")).strip(),
                    type=str(item.get("type", "")).strip(),
                    visibility=str(item.get("visibility", "")).strip(),
                )
            )

    # keep only entries with names
    ctx_tuple = tuple(e for e in ctx_list if e.name)
    return GoalCtx(goal=goal, context=ctx_tuple)


def solve_one_hole(
    cfg: BridgeCfg,
    work_file: Path,
    source_text: str,
    timeout_s: Optional[float],
) -> Tuple[str, bool, Optional[str]]:
    """
    Attempt to solve the *next* hole in source_text.

    Returns:
      (new_source_text, solved?, diagnostic_message_if_failed)

    Strategy:
      1) Replace the next hole with the report macro expression, run Agda,
         parse goal+context from tagged output.
      2) Query policy; try candidates in order by patching the hole with term.
      3) Accept the first candidate that makes Agda succeed (rc == 0).
    """
    hole = scan_next_hole(source_text)
    if hole is None:
        return (source_text, True, None)  # nothing to do

    # Ensure the report macro is in scope in the working module
    base = ensure_required_imports(source_text, cfg.required_open_imports)

    # For reporting, we replace the hole with e.g. `reportGoalCtx ?`
    report_text = replace_span(base, hole, cfg.report_macro_expr)

    work_file.write_text(report_text, encoding="utf-8")

    rep_res = agda_check(
        cfg=cfg,
        file_path=work_file,
        timeout_s=timeout_s,
        allow_unsolved=True,
    )

    combined = rep_res.combined
    if not has_req_markers(combined):
        # Provide a helpful failure: show some output to debug macro/markers.
        msg = (
            "Agda output did not include AGDAJANG_REQ_BEGIN/END markers.\n"
            "This usually means the report macro is missing, not imported, or markers changed.\n"
            "---- Agda combined output (truncated) ----\n"
            + combined[:2000]
            + ("\n... (truncated) ..." if len(combined) > 2000 else "")
        )
        return (source_text, False, msg)

    goalctx = extract_goalctx_from_report(combined)

    # Call policy
    try:
        cands = call_policy(cfg, goalctx, timeout_s=timeout_s)
    except Exception as e:
        return (source_text, False, f"policy call failed: {e}")

    if not cands:
        return (source_text, False, f"policy returned no candidates for goal: {goalctx.goal}")

    # Try candidates in order, patching the original hole (not the macro version)
    for cand in cands:
        trial = replace_span(base, hole, cand.term)

        # Decide whether to allow unsolved metas (if remaining holes exist)
        remaining = count_holes(trial)
        allow_unsolved = cfg.allow_unsolved_metas and (remaining > 0)

        work_file.write_text(trial, encoding="utf-8")
        chk = agda_check(cfg, work_file, timeout_s=timeout_s, allow_unsolved=allow_unsolved)

        if chk.rc == 0:
            return (trial, True, None)

    # No candidate worked
    diag = (
        "No candidate term typechecked for this hole.\n"
        f"Goal: {goalctx.goal}\n"
        "Candidates tried:\n"
        + "\n".join(f"  - {c.term} (score={c.score})" for c in cands)
    )
    return (source_text, False, diag)


def solve_file(cfg: BridgeCfg, timeout_s: Optional[float]) -> Tuple[str, int]:
    """
    Solve up to cfg.max_holes holes in cfg.input_path.
    Returns (final_source, solved_count).
    """
    src0 = cfg.input_path.read_text(encoding="utf-8")
    src = src0
    solved = 0

    # Work in a private directory so interface artifacts don’t pollute repo.
    with tempfile.TemporaryDirectory(prefix="agda-jang-bridge-") as td:
        workdir = Path(td)
        if cfg.keep_workdir:
            # If user wants to keep the workdir, we simply don’t delete it:
            # emulate by copying to a stable path at the end.
            pass

        work_file = workdir / cfg.input_path.name
        work_file.write_text(src, encoding="utf-8")

        # Main loop: solve one hole at a time
        for _ in range(cfg.max_holes):
            if scan_next_hole(src) is None:
                break

            new_src, ok, msg = solve_one_hole(cfg, work_file, src, timeout_s=timeout_s)
            if not ok:
                raise RuntimeError(msg or "unknown failure in solve_one_hole")
            # If there was “nothing to do”, ok=True, new_src == src.
            if new_src == src:
                break

            src = new_src
            solved += 1

        # Optional: copy workdir to output-adjacent debug location if requested
        if cfg.keep_workdir:
            dbg_dir = cfg.output_path.parent / "_agent_bridge_workdir"
            dbg_dir.mkdir(parents=True, exist_ok=True)
            (dbg_dir / cfg.input_path.name).write_text(src, encoding="utf-8")

    return (src, solved)


# -------------------------
# CLI
# -------------------------

def parse_args(argv: Optional[Sequence[str]] = None) -> BridgeCfg:
    ap = argparse.ArgumentParser(description="AgdaJang agent bridge (report -> policy -> patch -> check).")
    ap.add_argument("--input", required=True, help="Input .agda file (will not be modified).")
    ap.add_argument("--output", required=True, help="Output .agda file to write (solved copy).")

    ap.add_argument("--agda-bin", default="agda", help="Agda binary.")
    ap.add_argument("--agda-flags", default="", help="Extra flags passed to Agda (quoted string).")

    ap.add_argument("--policy-script", default=None, help="Path to policy backend script (default: policy_fixture.py).")
    ap.add_argument("--k", type=int, default=5, help="Top-k candidates to request from the policy.")
    ap.add_argument("--max-holes", type=int, default=10, help="Maximum number of holes to attempt to solve.")
    ap.add_argument("--keep-workdir", action="store_true", help="Keep a copy of intermediate work for debugging.")

    ap.add_argument(
        "--no-allow-unsolved-metas",
        action="store_true",
        help="If set, do NOT pass --allow-unsolved-metas during intermediate checks (not recommended).",
    )

    ap.add_argument(
        "--report-macro",
        default="reportGoalCtx ?",
        help="Macro expression inserted in place of a hole to force goal/context reporting.",
    )

    args = ap.parse_args(list(argv) if argv is not None else None)

    inp = Path(args.input).resolve()
    out = Path(args.output).resolve()

    if not inp.exists():
        raise SystemExit(f"ERROR: input file not found: {inp}")
    if inp.suffix.lower() != ".agda":
        raise SystemExit(f"ERROR: expected a .agda file, got: {inp}")
    if inp == out:
        raise SystemExit("ERROR: input and output paths are identical (refusing to overwrite input).")

    policy_script = (
        Path(args.policy_script).resolve()
        if args.policy_script
        else (Path(__file__).resolve().parent / "policy_fixture.py")
    )
    if not policy_script.exists():
        raise SystemExit(f"ERROR: policy script not found: {policy_script}")

    # Required imports so `reportGoalCtx` is in scope
    # (can extend this later if we move macro names/modules.)
    required_open_imports = (
        "open import AgdaJang.Debug",
    )

    return BridgeCfg(
        agda_bin=str(args.agda_bin),
        agda_flags=_split_flags(args.agda_flags),
        input_path=inp,
        output_path=out,
        policy_script=policy_script,
        k=int(args.k),
        max_holes=int(args.max_holes),
        keep_workdir=bool(args.keep_workdir),
        allow_unsolved_metas=not bool(args.no_allow_unsolved_metas),
        report_macro_expr=str(args.report_macro).strip(),
        required_open_imports=tuple(required_open_imports),
    )


def main(argv: Optional[Sequence[str]] = None) -> int:
    cfg = parse_args(argv)

    # Ensure output directory exists
    cfg.output_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        final_src, solved = solve_file(cfg, timeout_s=None)
    except Exception as e:
        print(f"❌ agent_bridge failed: {e}", file=sys.stderr)
        return 2

    cfg.output_path.write_text(final_src, encoding="utf-8")

    # Final strict check:
    # - If holes remain, report that clearly.
    remaining = count_holes(final_src)
    if remaining > 0:
        print(
            f"ℹ️  Wrote {cfg.output_path} after solving {solved} hole(s); "
            f"{remaining} hole(s) remain.",
            file=sys.stderr,
        )
        # Still consider it success for v0, since we may cap max-holes intentionally.
        return 0

    # If no holes remain, typecheck without --allow-unsolved-metas (unless user put it in agda_flags)
    final_check = agda_check(cfg, cfg.output_path, timeout_s=None, allow_unsolved=False)
    if final_check.rc != 0:
        print("❌ Final Agda check failed (no holes remain, but file did not typecheck).", file=sys.stderr)
        print("---- Agda output ----", file=sys.stderr)
        print(final_check.combined.rstrip(), file=sys.stderr)
        print("---------------------", file=sys.stderr)
        return 3

    print(f"✅ Solved {solved} hole(s); wrote {cfg.output_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
