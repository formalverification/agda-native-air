#!/usr/bin/env python3
"""
agent_bridge.py
===============

File: agda-ai-prover/agda-jang/python/tools/agent_bridge.py

Goal (Issue #23 v0)
------------------
Provide a tiny, deterministic "report → policy → patch → check" loop:

  1) Create a *reporting* variant of a target Agda file by replacing the next hole
     with a marker-emitting macro call (e.g. `reportGoalCtx ?`).
  2) Run Agda on the reporting variant and parse a `{goal, context}` request from
     stable BEGIN/END markers in the compiler output.
  3) Call a policy backend (local process) to get ranked candidate terms.
  4) Try candidates by patching the original hole; accept the first candidate that
     typechecks; repeat for up to N holes.

Design constraints / style
--------------------------
- Reuses project utilities:
    utils.command_runner.run_command
    utils.file_ops.temp_dir, utils.file_ops.write_text_atomic
    utils.result.Result (Ok/Err)
    utils.types.PipelineError, CommandResult
- Avoids exceptions for control flow (errors become PipelineError values).
- Keeps data immutable (dataclasses, frozen where appropriate).
- Type annotations everywhere.

Important note
--------------
This bridge expects the Agda-side reporting macro to emit a request block:

  AGDAJANG_REQ_BEGIN
  { "goal": "...", "context": [ { "name": "...", "type": "..." }, ... ] }
  AGDAJANG_REQ_END

The parsing support for these markers is added in tools/report_parser.py (diff below).

CLI examples
------------
From repo root (recommended, so --library-file paths resolve):

  PYTHONPATH=agda-jang/python \
  python3 agda-jang/python/tools/agent_bridge.py \
    --file data/agda/FixtureHoles.agda \
    --policy "python3 agda-jang/python/tools/policy_fixture.py" \
    --agda-bin agda \
    --agda-flags "-i agda --library-file=agda/libraries -l agda-jang" \
    --include "data/agda" \
    --max-holes 4 \
    --k 5

If you want to inspect generated workdir files:
  ... --keep-workdir
"""

from __future__ import annotations

import argparse
import json
import re
import shlex
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from tools.report_parser import (
    extract_policy_request_from_output,
)

from utils.command_runner import run_command
from utils.file_ops import temp_dir, write_text_atomic
from utils.result import Err, Ok, Result
from utils.types import CommandResult, PipelineError


# =========================
# Small immutable data types
# =========================

@dataclass(frozen=True)
class HoleSpan:
    """
    A byte/character span for a single hole occurrence in a source file,
    plus a 1-based (line, col) for nicer logging.
    """
    start: int
    end: int
    line: int
    col: int


@dataclass(frozen=True)
class PolicyCandidate:
    term: str
    score: float
    meta: Dict[str, Any]


@dataclass(frozen=True)
class PolicyResponse:
    schemaVersion: str
    candidates: List[PolicyCandidate]
    meta: Dict[str, Any]


@dataclass(frozen=True)
class PolicyRequest:
    goal: str
    context: List[Dict[str, str]]  # [{"name":..., "type":...}, ...]
    module: Optional[str] = None
    meta: Optional[Dict[str, Any]] = None


@dataclass(frozen=True)
class BridgeConfig:
    file: Path
    policy_cmd: List[str]
    agda_bin: str
    agda_flags: str
    include_dirs: List[str]
    timeout_sec: Optional[float]
    keep_workdir: bool
    max_holes: int
    top_k: int
    cwd: Optional[Path]

    # The Agda-side reporting macro call we inject in place of `{!!}`
    # (expects a trailing `?` to stand for "current goal hole term").
    report_expr: str


# =========================
# Pure-ish helpers (strings)
# =========================

_HOLE_TOKEN = "{!!}"


def _split_flags(flag_str: str) -> List[str]:
    """
    Parse an Agda flag string into argv tokens.

    Mirrors the small safety in jang_try.py:
      - drop a dangling "-l" if present (avoids Agda parse error).
    """
    toks = shlex.split(flag_str) if flag_str else []
    if toks and toks[-1] == "-l":
        toks = toks[:-1]
    return toks


def _find_next_hole(src: str) -> Optional[HoleSpan]:
    """
    Find the next `{!!}` hole token.

    v0 deliberately keeps this simple: it does not attempt to parse comments/strings.
    For FixtureHoles.agda, this is sufficient and deterministic.

    Returns None if no hole exists.
    """
    idx = src.find(_HOLE_TOKEN)
    if idx < 0:
        return None
    start = idx
    end = idx + len(_HOLE_TOKEN)

    # 1-based line/col
    line = src.count("\n", 0, start) + 1
    last_nl = src.rfind("\n", 0, start)
    col = (start - last_nl) if last_nl >= 0 else (start + 1)
    return HoleSpan(start=start, end=end, line=line, col=col)


def _replace_span(src: str, span: HoleSpan, replacement: str) -> str:
    return src[: span.start] + replacement + src[span.end :]


def _json_dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, indent=2)


# =========================
# IO helpers (Result-returning)
# =========================

def read_text(path: Path) -> Result[str, PipelineError]:
    """
    Read UTF-8 text from a file, returning PipelineError on failure.
    """
    try:
        return Ok(path.read_text(encoding="utf-8"))
    except OSError as e:
        return Err(PipelineError(
            kind="OSError",
            cmd=[],
            rc=-1,
            stdout="",
            stderr="",
            message=f"failed to read {path}: {e}",
        ))


def run_agda(
    cfg: BridgeConfig,
    file_path: Path,
    extra_include_dirs: Sequence[str],
) -> Result[CommandResult, PipelineError]:
    """
    Run Agda on `file_path`, adding include dirs.

    Note: run_command returns Err on non-zero exit; for *report mode* we still want
    stdout, so callers should usually normalize Err into a "collected output" shape.
    """
    inc: List[str] = []
    for d in extra_include_dirs:
        inc += ["-i", d]
    for d in cfg.include_dirs:
        inc += ["-i", d]

    cmd = [cfg.agda_bin, *_split_flags(cfg.agda_flags), *inc, str(file_path)]
    return run_command(cmd, cwd=cfg.cwd, timeout=cfg.timeout_sec, merge_stderr=True)


def collect_output(res: Result[CommandResult, PipelineError]) -> Tuple[int, str]:
    """
    Normalize Ok/Err from run_command into (rc, merged_output).

    - Ok: rc==0, output in stdout
    - Err: rc is error.rc, output in error.stdout (+error.stderr if present)
    """
    if isinstance(res, Ok):
        return res.value.rc, res.value.stdout
    err = res.error
    merged = (err.stdout or "") + (("\n" + err.stderr) if err.stderr else "")
    return err.rc, merged


def call_policy(
    cfg: BridgeConfig,
    req: PolicyRequest,
    workdir: Path,
) -> Result[PolicyResponse, PipelineError]:
    """
    Call the policy backend as a local process.

    We avoid stdin piping so we can reuse run_command:
      - write req.json
      - run: <policy_cmd> --in req.json --out -
      - parse stdout as JSON
    """
    req_path = workdir / "policy_req.json"
    write_text_atomic(req_path, _json_dumps({
        "goal": req.goal,
        "context": req.context,
        "module": req.module,
        "meta": req.meta,
    }) + "\n")

    cmd = [*cfg.policy_cmd, "--in", str(req_path), "--out", "-", "--k", str(cfg.top_k)]
    res = run_command(cmd, cwd=cfg.cwd, timeout=cfg.timeout_sec, merge_stderr=True)

    if isinstance(res, Err):
        e = res.error
        return Err(PipelineError(
            kind=e.kind,
            cmd=e.cmd,
            rc=e.rc,
            stdout=e.stdout,
            stderr=e.stderr,
            message=f"policy backend failed: {e.message}",
        ))

    out = res.value.stdout.strip()
    try:
        obj = json.loads(out)
    except Exception as ex:
        return Err(PipelineError(
            kind="OSError",
            cmd=cmd,
            rc=-1,
            stdout=out,
            stderr="",
            message=f"policy backend returned non-JSON: {ex}",
        ))

    cands: List[PolicyCandidate] = []
    for raw in (obj.get("candidates") or []):
        if not isinstance(raw, dict):
            continue
        term = str(raw.get("term", "")).strip()
        if not term:
            continue
        score = float(raw.get("score", 0.0))
        meta = raw.get("meta") if isinstance(raw.get("meta"), dict) else {}
        cands.append(PolicyCandidate(term=term, score=score, meta=meta))

    return Ok(PolicyResponse(
        schemaVersion=str(obj.get("schemaVersion", "")),
        candidates=cands,
        meta=obj.get("meta") if isinstance(obj.get("meta"), dict) else {},
    ))


# =========================
# Core algorithm
# =========================

def build_report_variant(cfg: BridgeConfig, src: str, hole: HoleSpan) -> str:
    """
    Replace the hole token with the reporting expression.
    Example replacement: "reportGoalCtx ?"
    """
    return _replace_span(src, hole, cfg.report_expr)


def build_candidate_variant(src: str, hole: HoleSpan, term: str) -> str:
    """
    Replace the hole token with a candidate term (surface syntax).
    """
    return _replace_span(src, hole, term)


def solve_one_hole(cfg: BridgeConfig, src: str, hole: HoleSpan, workdir: Path) -> Result[str, PipelineError]:
    """
    Attempt to solve exactly one hole.
    Returns updated source text if solved; Err if unsolved or failure.
    """
    # 1) Report mode: write a reporting variant into workdir, run Agda, parse request.
    report_src = build_report_variant(cfg, src, hole)
    report_file = workdir / cfg.file.name
    write_text_atomic(report_file, report_src)

    # Ensure Agda can resolve the module by including the *workdir* and original file dir.
    # (Also include user-provided include_dirs from cfg.)
    report_run = run_agda(cfg, report_file, extra_include_dirs=[str(workdir), str(cfg.file.parent)])
    _rc, out = collect_output(report_run)

    req_obj = extract_policy_request_from_output(out)
    if req_obj is None:
        return Err(PipelineError(
            kind="NonZeroExit",
            cmd=[],
            rc=42,
            stdout=out,
            stderr="",
            message=(
                "could not extract policy request markers from Agda output. "
                "Is the reporting macro implemented and emitting AGDAJANG_REQ_BEGIN/END?"
            ),
        ))

    req = PolicyRequest(
        goal=str(req_obj.get("goal", "")).strip(),
        context=req_obj.get("context") if isinstance(req_obj.get("context"), list) else [],
        module=req_obj.get("module") if isinstance(req_obj.get("module"), str) else None,
        meta=req_obj.get("meta") if isinstance(req_obj.get("meta"), dict) else None,
    )

    # 2) Call policy backend.
    pol = call_policy(cfg, req, workdir)
    if isinstance(pol, Err):
        return pol

    candidates = pol.value.candidates
    if not candidates:
        return Err(PipelineError(
            kind="NonZeroExit",
            cmd=[],
            rc=43,
            stdout=_json_dumps(req_obj),
            stderr="",
            message="policy returned zero candidates",
        ))

    # 3) Try top-k candidates by patching the *original* file in workdir and running Agda.
    for cand in candidates[: cfg.top_k]:
        cand_src = build_candidate_variant(src, hole, cand.term)
        cand_file = workdir / cfg.file.name
        write_text_atomic(cand_file, cand_src)

        cand_run = run_agda(cfg, cand_file, extra_include_dirs=[str(workdir), str(cfg.file.parent)])
        rc, _out = collect_output(cand_run)
        if rc == 0:
            return Ok(cand_src)

    return Err(PipelineError(
        kind="NonZeroExit",
        cmd=[],
        rc=44,
        stdout="",
        stderr="",
        message=f"no candidate among top-{cfg.top_k} typechecked for hole at {hole.line}:{hole.col}",
    ))


def solve_file(cfg: BridgeConfig) -> Result[str, PipelineError]:
    """
    Solve up to cfg.max_holes holes in cfg.file.

    Returns the final (possibly partially solved) source as Ok,
    or Err on a hard failure.
    """
    r0 = read_text(cfg.file)
    if isinstance(r0, Err):
        return r0
    src0 = r0.value

    with temp_dir(cfg.keep_workdir, prefix="agent-bridge_") as d:
        # Work on a local copy, but write back only at the end (atomic).
        src = src0
        solved = 0

        for _i in range(cfg.max_holes):
            hole = _find_next_hole(src)
            if hole is None:
                break

            r1 = solve_one_hole(cfg, src, hole, d)
            if isinstance(r1, Err):
                return r1

            src = r1.value
            solved += 1

        # If we solved at least one hole, verify final file checks.
        if solved > 0:
            final_file = d / cfg.file.name
            write_text_atomic(final_file, src)
            final_run = run_agda(cfg, final_file, extra_include_dirs=[str(d), str(cfg.file.parent)])
            rc, out = collect_output(final_run)
            if rc != 0:
                return Err(PipelineError(
                    kind="NonZeroExit",
                    cmd=[],
                    rc=rc,
                    stdout=out,
                    stderr="",
                    message="file did not typecheck after solving (unexpected)",
                ))

        return Ok(src)


# =========================
# CLI
# =========================

def parse_args(argv: Optional[List[str]] = None) -> BridgeConfig:
    ap = argparse.ArgumentParser(description="AgdaJang agent bridge (report → policy → patch → check).")
    ap.add_argument("--file", required=True, help="Path to an .agda file with `{!!}` holes.")
    ap.add_argument("--policy", required=True, help="Policy command (quoted), e.g. 'python3 .../policy_fixture.py'")
    ap.add_argument("--agda-bin", default="agda", help="Agda binary")
    ap.add_argument("--agda-flags", default="", help="Extra flags passed to Agda (quoted string)")
    ap.add_argument("--include", action="append", default=[], help="Extra -i include dirs (repeatable)")
    ap.add_argument("--timeout", type=float, default=None, help="Timeout (seconds) for each process invocation")
    ap.add_argument("--keep-workdir", action="store_true", help="Keep the working directory for inspection")
    ap.add_argument("--max-holes", type=int, default=1, help="Max number of holes to solve")
    ap.add_argument("--k", type=int, default=5, help="Top-k candidates to try per hole")
    ap.add_argument("--cwd", default=None, help="Working directory for running tools (recommended: repo root)")
    ap.add_argument(
        "--report-expr",
        default="reportGoalCtx ?",
        help="Expression to inject into a hole to make Agda emit a {goal,context} request block",
    )

    args = ap.parse_args(argv)

    policy_cmd = shlex.split(args.policy)
    if not policy_cmd:
        raise SystemExit("ERROR: --policy parsed to empty command")

    cwd = Path(args.cwd).resolve() if args.cwd else None

    return BridgeConfig(
        file=Path(args.file).resolve(),
        policy_cmd=policy_cmd,
        agda_bin=str(args.agda_bin),
        agda_flags=str(args.agda_flags),
        include_dirs=[str(x) for x in (args.include or [])],
        timeout_sec=args.timeout,
        keep_workdir=bool(args.keep_workdir),
        max_holes=int(args.max_holes),
        top_k=int(args.k),
        cwd=cwd,
        report_expr=str(args.report_expr),
    )


def main(argv: Optional[List[str]] = None) -> int:
    cfg = parse_args(argv)

    if not cfg.file.exists():
        print(f"ERROR: file not found: {cfg.file}")
        return 2
    if cfg.file.suffix.lower() != ".agda":
        print(f"ERROR: expected .agda file, got: {cfg.file}")
        return 2

    res = solve_file(cfg)
    if isinstance(res, Err):
        e = res.error
        print(f"[agent-bridge] FAIL: {e.message}")
        if e.stdout.strip():
            print("---- output ----")
            print(e.stdout.rstrip())
            print("---------------")
        return 1

    # Write back atomically
    write_text_atomic(cfg.file, res.value)
    print(f"[agent-bridge] OK: wrote patched file: {cfg.file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
