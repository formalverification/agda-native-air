#!/usr/bin/env python3
"""
eval_fixtures.py

File: agda-dojang/python/tools/eval_fixtures.py

Description:
  Deterministic Agda-check evaluator + fixtures scoreboard.
  (Issue #85 deliverable.)

What this does (v0):
  + Enumerate fixture modules with `{!!}` holes.
  + For each hole
    1. run the report macro (e.g. reportGoalCtx) to extract {goal, context},
    2. call a policy backend to get top-k candidates,
    3. typecheck each candidate in a scratch module, recording a JSONL row
       per candidate attempt: ok/type_error/timeout/crash + elapsedMs.
    4. patch the fixture source with the first passing candidate.
  + If the fixture becomes hole-free, run a strict final Agda check.

XFAIL support (Issue #84 nicety):
  Some fixtures are intentionally UNSOLVABLE by current policy (negative examples);
  these are marked as "expected fail" (xfail) so demo/CI remains green while retaining
  negatives.  By default, FixtureFail01 is xfail.  Use --xfail / --xfail-file to add
  more; use --xfail-none to disable defaults.

Outputs (deterministic paths):
  _build/eval-proof-completion/<run-id>/
    results.jsonl          # per-candidate attempt rows
    fixtures.jsonl         # per-fixture summary rows
    logs/<Fixture>/<hole>/<rank>.txt
    solved/<Fixture>.agda  # only if fully solved

Notes:
  + Time-stamp at bottom of `report.md` is added iff `AGDADOJANG_REPORT_TIMESTAMP=1`.
  + Deterministic fixture enumeration and per-fixture workdirs for reproducibility.
  + Best-effort logging: never fail the evaluation because logging failed.
  + No external dependencies beyond Python stdlib for maximum portability and ease of use.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import shlex
import shutil
import sys
import time
from dataclasses import asdict, dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple, Set

from tools.report_parser import extract_policy_request_from_output
from tools.policy_contract import build_request as build_policy_request
from utils.file_ops import write_text_atomic
from utils.result import Err, Ok, Result
from utils.types import PipelineError, CommandResult
from utils.command_runner import run_command

# Reuse the bridge’s well-tested behavior for:
#  - hole finding/spans
#  - shadow-mode flag/include filtering (avoids ambiguous module errors)
#  - policy invocation contract
#  - scratch-module rendering with context postulates
from tools.agent_bridge import (  # type: ignore
    BridgeConfig,
    HoleSpan,
    PolicyRequest,
    build_candidate_variant,
    build_report_variant,
    call_policy,
    collect_output,
    read_text,
    run_agda,
    _coerce_context,
    _coerce_meta,
    _extract_import_lines,
    _extract_prelude_lines,
    _only_unsolved_metas,
    _filled_hole_still_unsolved,
    _find_next_hole,
    _render_candidate_scratch,
    _strip_flag,
    _ensure_overlay_dir,  # added earlier for ambiguity-avoidance
)


# =============================================================================
# Small immutable data types
# =============================================================================

@dataclass(frozen=True)
class EvalConfig:
    fixtures: List[Path]
    out_dir: Path
    run_id: str
    policy_cmd: List[str]
    agda_bin: str
    agda_flags: str
    include_dirs: List[str]
    timeout_sec: Optional[float]
    keep_workdir: bool
    max_holes: int
    top_k: int
    cwd: Optional[Path]
    report_expr: str
    xfail_ids: Set[str]
    fail_on_xpass: bool


@dataclass(frozen=True)
class CandidateAttempt:
    fixtureId: str
    module: str
    fixturePath: str
    holeIndex: int
    holeLine: int
    holeCol: int
    candidateRank: int
    candidate: str
    status: str  # ok | type_error | timeout | crash | policy_error | report_error
    elapsedMs: int
    rc: int
    logPath: str
    schemaVersion: str = "eval-proof-completion.v0"


@dataclass(frozen=True)
class FixtureSummary:
    fixtureId: str
    module: str
    fixturePath: str
    holesTotal: int
    holesSolved: int
    fullySolved: bool
    finalStatus: str  # ok | unsolved | type_error | timeout | crash
    elapsedMs: int
    solvedPath: Optional[str]
    expectedFail: bool = False
    evalOutcome: str = ""  # ok | fail | xfail | xpass
    schemaVersion: str = "eval-proof-completion.v0"


# =============================================================================
# Pure helpers
# =============================================================================

_HOLE_TOKEN = "{!!}"


def _count_holes(src: str) -> int:
    return src.count(_HOLE_TOKEN)

def _split_csv(items: Iterable[str]) -> List[str]:
    out: List[str] = []
    for it in items:
        for part in str(it).split(","):
            s = part.strip()
            if s:
                out.append(s)
    return out


def _read_xfail_file(path: Path) -> List[str]:
    """
    Read fixture ids from a file (one per line).
    Allows blank lines and '#' comments.
    """
    try:
        txt = path.read_text(encoding="utf-8")
    except OSError:
        return []
    out: List[str] = []
    for line in txt.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        out.append(s)
    return out


def _annotate_outcome(cfg: EvalConfig, s: FixtureSummary) -> FixtureSummary:
    """
    Add expectedFail + evalOutcome while keeping finalStatus stable for v0 consumers.
    Outcome:
      - ok:    fully solved and not expectedFail
      - fail:  not fully solved and not expectedFail
      - xfail: not fully solved and expectedFail
      - xpass: fully solved and expectedFail
    """
    expected = s.fixtureId in cfg.xfail_ids
    passed = bool(s.fullySolved)
    outcome = ("xpass" if (expected and passed) else
               "xfail" if (expected and not passed) else
               "ok" if (not expected and passed) else
               "fail")
    return replace(s, expectedFail=expected, evalOutcome=outcome)


def _mkdir_clean(path: Path) -> Result[None, PipelineError]:
    try:
        path.mkdir(parents=True, exist_ok=True)
        return Ok(None)
    except OSError as e:
        return Err(PipelineError(kind="OSError", cmd=[], rc=-1, stdout="", stderr="", message=str(e)))


def _rm_tree_best_effort(path: Path) -> None:
    try:
        if path.exists():
            shutil.rmtree(path)
    except OSError:
        return


def _write_jsonl_line(fp, obj: Dict[str, Any]) -> None:
    fp.write(json.dumps(obj, ensure_ascii=False) + "\n")


def _status_from_run(res: Result[CommandResult, PipelineError]) -> Tuple[str, int, str]:
    """
    Map a run_command-style Result into a (status, rc, merged_output).
    """
    rc, out = collect_output(res)
    if isinstance(res, Ok) and rc == 0:
        return "ok", rc, out

    # Err path: classify
    if isinstance(res, Err):
        k = (res.error.kind or "").lower()
        if "timeout" in k:
            return "timeout", rc, out
        if "oserror" in k:
            return "crash", rc, out
        # NonZeroExit etc.
        return "type_error", rc, out

    # Ok with non-zero (rare / defensive)
    return "type_error", rc, out


def _bridge_cfg_for_fixture(cfg: EvalConfig, fixture: Path) -> BridgeConfig:
    return BridgeConfig(
        file=fixture.resolve(),
        output=None,
        policy_cmd=cfg.policy_cmd,
        agda_bin=cfg.agda_bin,
        agda_flags=cfg.agda_flags,
        include_dirs=list(cfg.include_dirs),
        timeout_sec=cfg.timeout_sec,
        keep_workdir=cfg.keep_workdir,
        max_holes=cfg.max_holes,
        top_k=cfg.top_k,
        cwd=cfg.cwd,
        report_expr=cfg.report_expr,
    )


def _work_root(cfg: EvalConfig) -> Path:
    return cfg.out_dir / cfg.run_id


def _fixture_workdir(cfg: EvalConfig, fixture_id: str) -> Path:
    return _work_root(cfg) / "work" / fixture_id


def _fixture_logs_dir(cfg: EvalConfig, fixture_id: str, hole_index: int) -> Path:
    return _work_root(cfg) / "logs" / fixture_id / f"hole-{hole_index:02d}"


def _fixture_solved_dir(cfg: EvalConfig) -> Path:
    return _work_root(cfg) / "solved"


def _results_jsonl_path(cfg: EvalConfig) -> Path:
    return _work_root(cfg) / "results.jsonl"


def _fixtures_jsonl_path(cfg: EvalConfig) -> Path:
    return _work_root(cfg) / "fixtures.jsonl"


# =============================================================================
# IO helpers (Result-returning)
# =============================================================================

def _agda_version(cfg: EvalConfig) -> str:
    """
    Best-effort: capture `agda --version`. Not fatal if it fails.
    """
    res = run_command([cfg.agda_bin, "--version"], cwd=cfg.cwd, timeout=cfg.timeout_sec, merge_stderr=True)
    if isinstance(res, Ok):
        return res.value.stdout.strip()
    return ""


def _ensure_run_dirs(cfg: EvalConfig, clean: bool) -> Result[None, PipelineError]:
    root = _work_root(cfg)
    if clean:
        _rm_tree_best_effort(root)
    for p in [root, root / "logs", root / "work", root / "solved"]:
        r = _mkdir_clean(p)
        if isinstance(r, Err):
            return r
    return Ok(None)


def _discover_fixtures(specs: Sequence[str]) -> List[Path]:
    """
    Expand a list of file/glob specs into a sorted unique list of Paths.
    Deterministic ordering by path string.
    """
    seen: Dict[str, None] = {}
    out: List[Path] = []
    for s in specs:
        matches = glob.glob(s)
        if not matches and Path(s).exists():
            matches = [s]
        for m in matches:
            p = Path(m).resolve()
            k = str(p)
            if k in seen:
                continue
            seen[k] = None
            out.append(p)
    out.sort(key=lambda p: str(p))
    return out


# =============================================================================
# Core evaluation
# =============================================================================

def _run_report(
    bridge_cfg: BridgeConfig,
    fixture_src: str,
    hole: HoleSpan,
    shadow_dir: Path,
    overlay: Path,
) -> Tuple[Optional[Dict[str, Any]], str]:
    """
    Run the report variant and parse a policy request object from output.
    Returns (req_obj | None, merged_output).
    """
    report_src = build_report_variant(bridge_cfg, fixture_src, hole)
    shadow_file = shadow_dir / bridge_cfg.file.name
    write_text_atomic(shadow_file, report_src)

    res = run_agda(bridge_cfg, shadow_file, extra_include_dirs=[str(shadow_dir), str(overlay)])
    _rc, out = collect_output(res)
    req_obj = extract_policy_request_from_output(out)
    if isinstance(req_obj, dict):
        m = req_obj.get("module")
        if not isinstance(m, str) or not m:
            req_obj["module"] = bridge_cfg.file.stem
    return req_obj, out


def _try_candidates_for_hole(
    cfg: EvalConfig,
    bridge_cfg: BridgeConfig,
    fixture_id: str,
    fixture: Path,
    fixture_src: str,
    hole_index: int,
    hole: HoleSpan,
    req_obj: Dict[str, Any],
    shadow_dir: Path,
    overlay: Path,
    results_fp,
) -> Result[Tuple[bool, str], PipelineError]:
    """
    Try top-k policy candidates for a single hole, writing per-candidate rows to results_fp.
    Returns Ok((solved?, updated_src)).
    """
    meta0 = _coerce_meta(req_obj.get("meta")) or {}
    # Attach stable per-run identifiers so the deterministic fixture policy can
    # special-case exact (fixture, hole) pairs when needed.
    meta = {
        **meta0,
        "fixtureId": fixture_id,
        "holeIndex": hole_index,
    }

    req = PolicyRequest(
        goal=str(req_obj.get("goal", "")).strip(),
        context=_coerce_context(req_obj.get("context")),
        module=req_obj.get("module") if isinstance(req_obj.get("module"), str) else None,
        meta=meta,
    )

    logs_dir = _fixture_logs_dir(cfg, fixture_id, hole_index)
    _mkdir_clean(logs_dir)
    # Record the exact request we are about to send.
    req_log_obj = build_policy_request(
        goal=req.goal,
        context=req.context,
        module=req.module,
        meta=req.meta,
    )
    write_text_atomic(
        logs_dir / "policy_request.json",
        json.dumps(req_log_obj, ensure_ascii=False, indent=2) + "\n",
    )

    pol = call_policy(bridge_cfg, req=req, workdir=shadow_dir)
    if isinstance(pol, Err):
        log_path = logs_dir / "policy_error.txt"
        write_text_atomic(log_path, pol.error.message + "\n")

        attempt = CandidateAttempt(
            fixtureId=fixture_id,
            module=fixture.stem,
            fixturePath=str(fixture),
            holeIndex=hole_index,
            holeLine=hole.line,
            holeCol=hole.col,
            candidateRank=0,
            candidate="",
            status="policy_error",
            elapsedMs=0,
            rc=pol.error.rc,
            logPath=str(log_path),
        )
        _write_jsonl_line(results_fp, attempt.__dict__)
        return Err(pol.error)

    # Record the raw policy response (candidates + meta).
    write_text_atomic(
        logs_dir / "policy_response.json",
        json.dumps(asdict(pol.value), ensure_ascii=False, indent=2) + "\n",
    )

    candidates = pol.value.candidates[: cfg.top_k]
    if not candidates:
        log_path = logs_dir / "no_candidates.txt"
        write_text_atomic(log_path, json.dumps(req_log_obj, ensure_ascii=False, indent=2) + "\n")
        attempt = CandidateAttempt(
            fixtureId=fixture_id,
            module=fixture.stem,
            fixturePath=str(fixture),
            holeIndex=hole_index,
            holeLine=hole.line,
            holeCol=hole.col,
            candidateRank=0,
            candidate="",
            status="policy_error",
            elapsedMs=0,
            rc=43,
            logPath=str(log_path),
        )
        _write_jsonl_line(results_fp, attempt.__dict__)
        return Ok((False, fixture_src))

    for rank, cand in enumerate(candidates, start=1):
        log_path = logs_dir / f"cand-{rank:02d}.txt"

        # Validate in a patched shadow copy of the *fixture module*.
        shadow_file = shadow_dir / bridge_cfg.file.name
        trial_src = build_candidate_variant(fixture_src, hole, cand.term)
        write_text_atomic(shadow_file, trial_src)

        t0 = time.monotonic()
        run_res = run_agda(bridge_cfg, shadow_file, extra_include_dirs=[str(shadow_dir), str(overlay)])
        status, rc, out = _status_from_run(run_res)
        elapsed = int((time.monotonic() - t0) * 1000.0)

        # Accept “only unsolved metas” as long as the filled hole is no longer unsolved.
        accepted = (status == "ok") or (_only_unsolved_metas(out) and not _filled_hole_still_unsolved(hole, out))
        if accepted:
            status = "ok"

        write_text_atomic(log_path, out.rstrip() + "\n")

        attempt = CandidateAttempt(
            fixtureId=fixture_id,
            module=fixture.stem,
            fixturePath=str(fixture),
            holeIndex=hole_index,
            holeLine=hole.line,
            holeCol=hole.col,
            candidateRank=rank,
            candidate=cand.term,
            status=status,
            elapsedMs=elapsed,
            rc=rc,
            logPath=str(log_path),
        )
        _write_jsonl_line(results_fp, attempt.__dict__)

        if accepted:
            return Ok((True, trial_src))

    return Ok((False, fixture_src))


def _final_strict_check(
    bridge_cfg: BridgeConfig,
    src: str,
    shadow_dir: Path,
    overlay: Path,
) -> Tuple[str, int, str]:
    """
    Return (finalStatus, rc, output) for strict final typecheck.
    """
    final_file = shadow_dir / bridge_cfg.file.name
    write_text_atomic(final_file, src)

    strict_cfg = BridgeConfig(**{**bridge_cfg.__dict__, "agda_flags": _strip_flag(bridge_cfg.agda_flags, "--allow-unsolved-metas")})
    res = run_agda(strict_cfg, final_file, extra_include_dirs=[str(shadow_dir), str(overlay)])
    status, rc, out = _status_from_run(res)
    return status, rc, out


def eval_one_fixture(cfg: EvalConfig, fixture: Path, results_fp) -> Result[FixtureSummary, PipelineError]:
    fixture_id = fixture.stem
    bridge_cfg = _bridge_cfg_for_fixture(cfg, fixture)

    r0 = read_text(fixture)
    if isinstance(r0, Err):
        return r0
    src0 = r0.value
    holes_total = _count_holes(src0)

    # Deterministic per-fixture workdir.
    wdir = _fixture_workdir(cfg, fixture_id)
    shadow_dir = wdir / "shadow"
    if not cfg.keep_workdir:
        _rm_tree_best_effort(wdir)
    _mkdir_clean(shadow_dir)

    # Overlay (mirrors fixture parent minus this file) to avoid module ambiguity.
    overlay = _ensure_overlay_dir(wdir, fixture.parent, fixture.name)

    t_start = time.monotonic()

    src = src0
    holes_solved = 0
    hole_index = 0

    while holes_solved < cfg.max_holes:
        hole = _find_next_hole(src)
        if hole is None:
            break

        # Per-hole logs dir (we keep all artifacts for this hole here).
        logs_dir = _fixture_logs_dir(cfg, fixture_id, hole_index)
        _mkdir_clean(logs_dir)

        req_obj, out = _run_report(bridge_cfg, src, hole, shadow_dir, overlay)

        # Save raw Agda output from the report step (even on success).
        report_log = logs_dir / "report_output.txt"
        write_text_atomic(report_log, out.rstrip() + "\n")

        if req_obj is None:
            # Record a single report_error attempt and stop this fixture.
            logs_dir = _fixture_logs_dir(cfg, fixture_id, hole_index)
            _mkdir_clean(logs_dir)
            # Always keep the raw Agda output that we tried to parse.
            write_text_atomic(logs_dir / "report_output.txt", out.rstrip() + "\n")
            log_path = logs_dir / "report_error.txt"
            write_text_atomic(log_path, out.rstrip() + "\n")
            attempt = CandidateAttempt(
                fixtureId=fixture_id,
                module=fixture.stem,
                fixturePath=str(fixture),
                holeIndex=hole_index,
                holeLine=hole.line,
                holeCol=hole.col,
                candidateRank=0,
                candidate="",
                status="report_error",
                elapsedMs=0,
                rc=42,
                logPath=str(log_path),
            )
            _write_jsonl_line(results_fp, attempt.__dict__)
            break

        # Stash report output; _try_candidates_for_hole cleans logs_dir, so write after.
        report_out = out
        r1 = _try_candidates_for_hole(
            cfg=cfg,
            bridge_cfg=bridge_cfg,
            fixture_id=fixture_id,
            fixture=fixture,
            fixture_src=src,
            hole_index=hole_index,
            hole=hole,
            req_obj=req_obj,
            shadow_dir=shadow_dir,
            overlay=overlay,
            results_fp=results_fp,
        )

        # Persist the raw report output for this hole (survives logs_dir cleaning).
        logs_dir = _fixture_logs_dir(cfg, fixture_id, hole_index)
        try:
            if logs_dir.exists():
                ro_path = logs_dir / "report_output.txt"
                if not ro_path.exists():
                    write_text_atomic(ro_path, report_out.rstrip() + "\n")
        except Exception:
            # Best-effort: never fail the evaluation because logging failed.
            pass

        if isinstance(r1, Err):
            # policy_error already logged in results.jsonl
            break

        solved, src2 = r1.value
        if not solved:
            # No candidate among top-k worked; stop this fixture.
            src = src2
            break

        src = src2
        holes_solved += 1
        hole_index += 1

    no_holes_left = (_find_next_hole(src) is None)
    final_status: str = "unsolved"
    solved_path: Optional[str] = None

    # Always do a strict check when there are no holes left.
    # Special-case: fixtures with 0 holes should be treated as "ok" if they strictly typecheck.
    if no_holes_left:
        final_status, _rc, out = _final_strict_check(bridge_cfg, src, shadow_dir, overlay)

        # Save strict output (even for hole-free fixtures) for debugging/CI artifacts.
        strict_log = _work_root(cfg) / "logs" / fixture_id / "final_strict.txt"
        _mkdir_clean(strict_log.parent)
        write_text_atomic(strict_log, out.rstrip() + "\n")

        if final_status == "ok" and holes_total > 0:
            # Write a canonical, typecheckable artifact for fixtures that started with
            # holes and were fully solved + passed the strict final check.
            solved_dir = _fixture_solved_dir(cfg)
            _mkdir_clean(solved_dir)
            solved_file = solved_dir / f"{fixture_id}.agda"
            write_text_atomic(solved_file, src)
            solved_path = str(solved_file)

    elapsed_ms = int((time.monotonic() - t_start) * 1000.0)
    summary = FixtureSummary(
        fixtureId=fixture_id,
        module=fixture_id,
        fixturePath=str(fixture),
        holesTotal=holes_total,
        holesSolved=holes_solved,
        fullySolved=bool(final_status == "ok"),
        finalStatus=("ok" if final_status == "ok" else final_status),
        elapsedMs=elapsed_ms,
        solvedPath=solved_path,
    )

    # Cleanup if requested
    if not cfg.keep_workdir:
        _rm_tree_best_effort(wdir)

    return Ok(summary)


def _format_scoreboard(summaries: List[FixtureSummary]) -> str:
    # Simple deterministic text output; no external deps.
    def final_cell(s: FixtureSummary) -> str:
        o = (s.evalOutcome or s.finalStatus or "").strip()

        # Make outcomes explicit while still showing underlying finalStatus when non-ok.
        if o in ("ok",):
            return "ok"
        if o in ("xfail", "xpass", "fail"):
            return f"{o}:{s.finalStatus}"
        return o

    rows = [
        ("fixture", "holes", "solved", "final", "ms"),
        *[
            (
                s.fixtureId,
                str(s.holesTotal),
                str(s.holesSolved),
                final_cell(s),
                str(s.elapsedMs),
            )
            for s in summaries
        ],
    ]
    colw = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    lines: List[str] = []
    for j, r in enumerate(rows):
        line = "  ".join(r[i].ljust(colw[i]) for i in range(len(r)))
        lines.append(line)
        if j == 0:
            lines.append("  ".join("-" * colw[i] for i in range(len(r))))
    return "\n".join(lines)

def _print_scoreboard(summaries: List[FixtureSummary]) -> None:
    print(_format_scoreboard(summaries))

def _compute_report_stats(cfg: EvalConfig, summaries: List[FixtureSummary]) -> Dict[str, Any]:
    num_goals = sum(int(s.holesTotal) for s in summaries)
    num_typechecked = sum(int(s.holesSolved) for s in summaries)
    success_rate = (num_typechecked / num_goals) if num_goals else 0.0
    return {
        "numGoals": num_goals,
        "k": int(cfg.top_k),
        "numTypechecked": num_typechecked,
        "successRate": success_rate,
    }


def _render_command_block() -> str:
    """
    Best-effort: render the *actual* invocation of this script (argv),
    prefixed with PYTHONPATH if set.
    """
    py_path = os.environ.get("PYTHONPATH")
    prefix = f"PYTHONPATH={shlex.quote(py_path)} " if py_path else ""

    # sys.argv[0] is the script path as invoked (often python/tools/eval_fixtures.py)
    parts = [shlex.quote(sys.executable), shlex.quote(sys.argv[0])] + [shlex.quote(a) for a in sys.argv[1:]]
    if not parts:
        return ""

    # Render one-arg-per-line for readability.
    if len(parts) == 1:
        return prefix + parts[0]

    lines = [prefix + f"{parts[0]} {parts[1]} \\"]
    rest = parts[2:]
    for i, a in enumerate(rest):
        is_last = (i == len(rest) - 1)
        suffix = "" if is_last else " \\"
        lines.append(f"  {a}{suffix}")
    return "\n".join(lines)


def _write_reports(cfg: EvalConfig, summaries: List[FixtureSummary]) -> None:
    """
    Write report.json + report.md under out-dir/run-id.
    Best-effort: should never fail the evaluation if writing reports fails.
    """
    try:
        root = _work_root(cfg)
        stats = _compute_report_stats(cfg, summaries)
        scoreboard = _format_scoreboard(summaries)
        cmd_block = _render_command_block()

        # JSON report (machine-readable)
        report_json = json.dumps(stats, ensure_ascii=False, indent=2) + "\n"
        write_text_atomic(root / "report.json", report_json)

        # Markdown report (human-readable)
        pct = round(float(stats["successRate"]) * 100.0)
        md = []
        md.append("# Proof Completion Report\n")
        md.append("## Statistics\n")
        md.append(f"+ `numGoals`: {stats['numGoals']}\n")
        md.append(f"+ `k`: {stats['k']}\n")
        md.append(f"+ `numTypechecked`: {stats['numTypechecked']}\n")
        md.append(f"+ `successRate`: {pct}%\n")
        md.append("\n## Commands\n\n```bash\n")
        md.append(cmd_block.rstrip() + "\n")
        md.append("```\n")
        md.append("\n## Report Card\n\n```\n")
        md.append(scoreboard.rstrip() + "\n")
        md.append("```\n")

        # Footer: keep deterministic by default; optionally include a timestamp.
        md.append("\n---\n")
        md.append("Report generated by `eval_fixtures.py`.")
        ts_flag = os.environ.get("AGDADOJANG_REPORT_TIMESTAMP", "").strip().lower()
        if ts_flag and ts_flag not in ("0", "false", "no"):
            when = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            md.append(f" Generated at {when} (UTC).")
        md.append("\n")

        write_text_atomic(root / "report.md", "".join(md))
    except Exception:
        return


# =============================================================================
# CLI
# =============================================================================

def parse_args(argv: Optional[List[str]] = None) -> Tuple[EvalConfig, bool]:
    ap = argparse.ArgumentParser(description="Evaluate proof-completion fixtures with Agda as oracle.")
    ap.add_argument(
        "--fixtures",
        action="append",
        default=None,
        help="Repeatable file/glob spec. If omitted, defaults to data/fixtures/Fixture*.agda",
    )
    ap.add_argument("--out-dir", default="_build/eval-proof-completion", help="Output root directory.")
    ap.add_argument("--run-id", default="latest", help="Subdirectory under out-dir (deterministic).")
    ap.add_argument("--clean", action="store_true", help="Delete out-dir/run-id before running.")

    ap.add_argument("--policy", default=f"{sys.executable} python/tools/policy_fixture.py",
                    help="Policy command (quoted). Default: python/tools/policy_fixture.py.")
    ap.add_argument("--k", type=int, default=5, help="Top-k candidates to try per hole.")
    ap.add_argument("--max-holes", type=int, default=4, help="Max holes to attempt per fixture.")

    ap.add_argument("--agda-bin", default="agda", help="Agda binary.")
    ap.add_argument("--agda-flags", default="", help="Extra flags passed to Agda (quoted string).")
    ap.add_argument("--include", action="append", default=[], help="Extra -i include dirs (repeatable).")
    ap.add_argument("--timeout", type=float, default=None, help="Timeout (seconds) per process invocation.")
    ap.add_argument("--cwd", default=None, help="Working directory (recommended: repo root).")
    ap.add_argument("--keep-workdir", action="store_true", help="Keep per-fixture work dirs under out-dir.")
    ap.add_argument("--report-expr", default="reportGoalCtx", help="Expression injected for reporting.")


    # XFAIL support (negative fixtures that are expected to remain unsolved).
    ap.add_argument("--xfail", action="append", default=[],
                    help="Fixture id(s) expected to fail (repeatable; comma-separated ok).")
    ap.add_argument("--xfail-file", default=None,
                    help="File listing xfail fixture ids (one per line; '#' comments allowed).")
    ap.add_argument("--xfail-none", action="store_true",
                    help="Disable default xfail set (FixtureFail01).")
    ap.add_argument("--fail-on-xpass", action="store_true",
                    help="Non-zero exit if an xfail fixture is unexpectedly solved (XPASS).")

    args = ap.parse_args(argv)
    policy_cmd = args.policy.strip()
    if not policy_cmd:
        raise SystemExit("ERROR: --policy parsed to empty command.")

    import shlex
    cmd = shlex.split(policy_cmd)
    if not cmd:
        raise SystemExit("ERROR: --policy parsed to empty argv.")

    cwd = Path(args.cwd).resolve() if args.cwd else None
    fixture_specs = args.fixtures if (args.fixtures is not None) else ["data/fixtures/Fixture*.agda"]
    fixtures = _discover_fixtures(fixture_specs)

    # XFAIL ids:
    # - default includes FixtureFail01 unless disabled
    xfail_ids: Set[str] = set()
    if not bool(args.xfail_none):
        xfail_ids.add("FixtureFail01")
    xfail_ids.update(_split_csv(args.xfail or []))
    if args.xfail_file:
        xfail_ids.update(_read_xfail_file(Path(args.xfail_file).resolve()))

    cfg = EvalConfig(
        fixtures=fixtures,
        out_dir=Path(args.out_dir).resolve(),
        run_id=str(args.run_id),
        policy_cmd=cmd,
        agda_bin=str(args.agda_bin),
        agda_flags=str(args.agda_flags),
        include_dirs=[str(x) for x in (args.include or [])],
        timeout_sec=args.timeout,
        keep_workdir=bool(args.keep_workdir),
        max_holes=int(args.max_holes),
        top_k=int(args.k),
        cwd=cwd,
        report_expr=str(args.report_expr),
        xfail_ids=xfail_ids,
        fail_on_xpass=bool(args.fail_on_xpass),
    )
    return cfg, bool(args.clean)


def main(argv: Optional[List[str]] = None) -> int:
    cfg, clean = parse_args(argv)

    if not cfg.fixtures:
        print("ERROR: no fixtures matched", file=sys.stderr)
        return 2

    r = _ensure_run_dirs(cfg, clean=clean)
    if isinstance(r, Err):
        print(f"ERROR: cannot prepare output dirs: {r.error.message}", file=sys.stderr)
        return 2

    # Record tool versions (best-effort).
    agda_ver = _agda_version(cfg)
    if agda_ver:
        write_text_atomic(_work_root(cfg) / "agda_version.txt", agda_ver + "\n")

    results_path = _results_jsonl_path(cfg)
    fixtures_path = _fixtures_jsonl_path(cfg)

    summaries: List[FixtureSummary] = []

    with results_path.open("w", encoding="utf-8") as results_fp, fixtures_path.open("w", encoding="utf-8") as fixtures_fp:
        for fx in cfg.fixtures:
            s = eval_one_fixture(cfg, fx, results_fp)
            if isinstance(s, Ok):
                s2 = _annotate_outcome(cfg, s.value)
                summaries.append(s2)
                _write_jsonl_line(fixtures_fp, s2.__dict__)
            else:
                # Hard failure: record a minimal summary-like row and continue.
                err = s.error
                pseudo = FixtureSummary(
                    fixtureId=fx.stem,
                    module=fx.stem,
                    fixturePath=str(fx),
                    holesTotal=0,
                    holesSolved=0,
                    fullySolved=False,
                    finalStatus="crash",
                    elapsedMs=0,
                    solvedPath=None,
                )
                pseudo2 = _annotate_outcome(cfg, pseudo)
                summaries.append(pseudo2)
                _write_jsonl_line(fixtures_fp, pseudo2.__dict__)
                print(f"[eval] FAIL fixture {fx.stem}: {err.message}", file=sys.stderr)

    _print_scoreboard(summaries)
    print(f"\nWrote: {results_path}")
    print(f"Wrote: {fixtures_path}")

    # Write aggregated reports (best-effort)
    _write_reports(cfg, summaries)

    unexpected = [s for s in summaries if s.evalOutcome == "fail"]
    xpasses = [s for s in summaries if s.evalOutcome == "xpass"]

    if unexpected:
        ids = ", ".join(s.fixtureId for s in unexpected)
        print(f"[eval] ERROR: unexpected failures: {ids}", file=sys.stderr)
        return 1

    if xpasses:
        ids = ", ".join(s.fixtureId for s in xpasses)
        print(f"[eval] NOTE: unexpected passes (xpass): {ids}", file=sys.stderr)
        if cfg.fail_on_xpass:
            return 3

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
