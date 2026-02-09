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
import os
import shlex
import shutil
import sys
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
from utils.rendering import render_module

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
    output: Optional[Path]
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

def _ensure_overlay_dir(
    workdir: Path,
    input_dir: Path,
    exclude_filename: str,
) -> Path:
    """
    Create an overlay directory inside workdir that mirrors input_dir *except*
    for exclude_filename.

    Why: in shadow mode we typecheck a temp copy of <exclude_filename> that has
    the same top-level module name. If we also include input_dir, Agda sees two
    possible files for that module and reports AmbiguousTopLevelModuleName.

    The overlay lets us still resolve imports of *other* sibling modules without
    exposing the original module file.
    """
    overlay = workdir / "_input_overlay"
    overlay.mkdir(parents=True, exist_ok=True)

    try:
        entries = list(input_dir.iterdir())
    except OSError:
        # If the input dir is unreadable, still return an empty overlay.
        return overlay

    for p in entries:
        if p.name == exclude_filename:
            continue
        dst = overlay / p.name
        if dst.exists() or dst.is_symlink():
            continue
        # Prefer symlinks (fast). Fall back to copy for environments where
        # symlinks are restricted.
        try:
            dst.symlink_to(p)
        except OSError:
            try:
                if p.is_dir():
                    shutil.copytree(p, dst, dirs_exist_ok=True)
                else:
                    shutil.copy2(p, dst)
            except OSError:
                # Best-effort; missing extras here will surface as missing imports.
                continue

    return overlay


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

def _drop_include_dir_tokens(tokens: List[str], drop_dir: Path) -> List[str]:
    """
    Remove occurrences of:  -i <drop_dir>
    from an argv-style token list.

    This is needed because in "shadow" mode we typecheck a temp copy of the
    module (same module name, same filename). If Agda also sees the original
    module file via -i <inputdir>, it reports AmbiguousTopLevelModuleName.
    """
    dd = drop_dir.resolve()
    out: List[str] = []
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "-i" and i + 1 < len(tokens):
            cand = tokens[i + 1]
            try:
                if Path(cand).resolve() == dd:
                    i += 2
                    continue
            except Exception:
                # Fall back to string compare if resolve fails
                if os.path.normpath(cand) == os.path.normpath(str(dd)):
                    i += 2
                    continue
        out.append(t)
        i += 1
    return out

def _flags_for_run(cfg: BridgeConfig, file_path: Path) -> List[str]:
    """
    Compute argv tokens for Agda flags.

    If we're checking a *shadow copy* (file_path != cfg.file), we remove
    `-i <inputdir>` so Agda doesn't see both:
      - the original module file, and
      - the temp shadow file
    at the same time.
    """
    toks = _split_flags(cfg.agda_flags)
    try:
        if file_path.resolve() != cfg.file.resolve():
            toks = _drop_include_dir_tokens(toks, cfg.file.parent)
    except Exception:
        # Conservative: if resolve fails, still try dropping by string path
        toks = _drop_include_dir_tokens(toks, cfg.file.parent)
    return toks

def _filter_includes_for_shadow(
    cfg: BridgeConfig,
    file_path: Path,
    include_dirs: Sequence[str],
) -> List[str]:
    """
    In shadow mode (file_path != cfg.file), remove include dirs that would expose
    the original module file directory.
    """
    out: List[str] = []
    try:
        input_dir = cfg.file.parent.resolve()
    except Exception:
        input_dir = cfg.file.parent

    for d in include_dirs:
        try:
            if Path(d).resolve() == input_dir:
                continue
        except Exception:
            if os.path.normpath(d) == os.path.normpath(str(input_dir)):
                continue
        out.append(d)
    return out

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

def _extract_import_lines(src: str) -> List[str]:
    """
    Best-effort import extraction for scratch modules.

    We keep it intentionally simple for v0:
      - include lines starting with `open import` or `import`
      - ignore comments and everything else
    """
    out: List[str] = []
    for raw in src.splitlines():
        line = raw.strip()
        if line.startswith("open import ") or line.startswith("import "):
            out.append(line)
    return out

def _render_postulates_from_context(ctx: List[Dict[str, Any]]) -> str:
    """
    Render a `postulate` block for the policy request context.

    Important: we emit declarations in reverse order. In Agda, the context often
    comes "innermost first"; reversing helps ensure earlier types are in scope
    (e.g. `A : Set` before `x : A`).
    """
    decls: List[str] = []
    # reverse to get outer binders first (usually what we want)
    for i, entry in enumerate(reversed(ctx)):
        nm0 = entry.get("name", "")
        ty0 = entry.get("type", "")
        nm = str(nm0).strip() if nm0 is not None else ""
        ty = str(ty0).strip() if ty0 is not None else ""
        if not ty:
            continue
        if not nm or nm == "_":
            nm = f"ctx{i}"
        decls.append(f"  {nm} : {ty}")
    if not decls:
        return ""
    return "postulate\n" + "\n".join(decls) + "\n"

def _render_candidate_scratch(req_obj: Dict[str, Any], user_imports: List[str], candidate: str) -> str:
    """
    Build a scratch module that checks exactly one candidate against exactly one goal.

    We reuse `utils.rendering.render_module` for the basic skeleton, and inject
    a `postulate` block for the reported context so that terms like `x` typecheck.
    """
    goal = str(req_obj.get("goal", "")).strip()
    ctx  = req_obj.get("context", []) if isinstance(req_obj.get("context"), list) else []
    base = render_module(goal=goal, user_imports=user_imports, body_term=candidate)
    post = _render_postulates_from_context(ctx)
    if not post:
        return base
    # Insert postulates just before the goal line `_ : ...`
    marker = "\n_ :"
    if marker not in base:
        # Fall back: just append postulates before the goal block
        return base.replace("\n\n_ :", "\n\n" + post + "\n_ :", 1) if "\n\n_ :" in base else (base + "\n" + post)
    return base.replace(marker, "\n\n" + post + marker, 1)

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
    # In shadow mode, filter includes that would expose the original module dir.
    extras = list(extra_include_dirs)
    includes = list(cfg.include_dirs)
    if file_path.resolve() != cfg.file.resolve():
        extras = _filter_includes_for_shadow(cfg, file_path, extras)
        includes = _filter_includes_for_shadow(cfg, file_path, includes)

    for d in extras:
        inc += ["-i", d]
    for d in includes:
        inc += ["-i", d]

    flags = _flags_for_run(cfg, file_path)
    cmd = [cfg.agda_bin, *flags, *inc, str(file_path)]
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


def _coerce_meta(raw: Any) -> Dict[str, Any]:
    """
    Coerce arbitrary JSON-ish values into a JSON-object-like dict.

    Pyright-friendly: never returns None; keys are normalized to str.
    """
    if not isinstance(raw, dict):
        return {}
    return {str(k): v for k, v in raw.items()}


def _coerce_context(raw: Any) -> List[Dict[str, str]]:
    """
    Coerce a decoded request 'context' into exactly:
      List[{"name": str, "type": str}]

    This matches policy_fixture.py's expectations and keeps typing tight.
    Extra keys (index/visibility/etc.) are ignored.
    """
    if not isinstance(raw, list):
        return []
    out: List[Dict[str, str]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        typ  = item.get("type")
        if isinstance(name, str) and isinstance(typ, str):
            out.append({"name": name, "type": typ})
    return out


def _strip_flag(flags: str, flag: str) -> str:
    """
    Remove a single flag token from a shell-ish flag string.
    Used so we can do a strict final typecheck without --allow-unsolved-metas,
    even if the caller included it for the reporting runs.
    """
    toks = shlex.split(flags) if flags else []
    toks = [t for t in toks if t != flag]
    return " ".join(shlex.quote(t) for t in toks)


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
        meta = _coerce_meta(raw.get("meta"))
        cands.append(PolicyCandidate(term=term, score=score, meta=meta))

    return Ok(PolicyResponse(
        schemaVersion=str(obj.get("schemaVersion", "")),
        candidates=cands,
        meta=_coerce_meta(obj.get("meta")),
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


def solve_one_hole(cfg: BridgeConfig, src: str, hole: HoleSpan, workdir: Path, overlay: Path) -> Result[str, PipelineError]:
    """
    Attempt to solve exactly one hole.
    Returns updated source text if solved; Err if unsolved or failure.
    """
    # 1) Report mode: write a reporting variant into workdir, run Agda, parse request.
    report_src = build_report_variant(cfg, src, hole)
    report_file = workdir / cfg.file.name
    write_text_atomic(report_file, report_src)

    # Include only the workdir for the shadow module; inputdir is intentionally
    # dropped from flags to avoid AmbiguousTopLevelModuleName.
    # Include overlay (siblings) but *not* the real input dir, to avoid ambiguity.
    report_run = run_agda(cfg, report_file, extra_include_dirs=[str(workdir), str(overlay)])
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
        context=_coerce_context(req_obj.get("context")),
        module=req_obj.get("module") if isinstance(req_obj.get("module"), str) else None,
        meta=_coerce_meta(req_obj.get("meta")) or None,
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

    # 3) Try top-k candidates in a scratch module. This avoids false negatives
    #    when the original file still contains other `{!!}` holes.
    user_imports = _extract_import_lines(src)
    scratch_file = workdir / "TrySandbox.agda"
    for cand in candidates[: cfg.top_k]:
        scratch_src = _render_candidate_scratch(req_obj, user_imports, cand.term)
        write_text_atomic(scratch_file, scratch_src)

        cand_run = run_agda(cfg, scratch_file, extra_include_dirs=[str(workdir), str(overlay)])
        rc, _out = collect_output(cand_run)
        if rc == 0:
            return Ok(build_candidate_variant(src, hole, cand.term))

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
        overlay = _ensure_overlay_dir(d, cfg.file.parent, cfg.file.name)
        if cfg.keep_workdir:
            print(f"[agent-bridge] workdir: {d}", file=sys.stderr)
        # Work on a local copy, but write back only at the end (atomic).
        src = src0
        solved = 0

        for _i in range(cfg.max_holes):
            hole = _find_next_hole(src)
            if hole is None:
                break

            r1 = solve_one_hole(cfg, src, hole, d, overlay)
            if isinstance(r1, Err):
                return r1

            src = r1.value
            solved += 1

        # Verify only if there are *no holes left*.
        if solved > 0 and _find_next_hole(src) is None:
            final_file = d / cfg.file.name
            write_text_atomic(final_file, src)
            # Strict final check: drop --allow-unsolved-metas if present
            strict_cfg = BridgeConfig(
                **{**cfg.__dict__, "agda_flags": _strip_flag(cfg.agda_flags, "--allow-unsolved-metas")}
            )
            # The `BridgeConfig(**{**cfg.__dict__, ...})` trick is a quick immutable
            # "copy with one field changed" without bringing in extra helpers.
            # (could replace later with an explicit constructor call; more verbose, but clearer)

            # IMPORTANT: do NOT include cfg.file.parent here (it contains the original
            # module file, which would make the module name ambiguous). Use overlay.
            final_run = run_agda(strict_cfg, final_file, extra_include_dirs=[str(d), str(overlay)])
            rc, out = collect_output(final_run)
            if rc != 0:
                return Err(PipelineError(
                    kind="NonZeroExit",
                    cmd=[],
                    rc=rc,
                    stdout=out,
                    stderr="",
                    message="file did not typecheck after solving (unexpected) — see workdir if kept",
                ))

        return Ok(src)


# =========================
# CLI
# =========================

def parse_args(argv: Optional[List[str]] = None) -> BridgeConfig:
    ap = argparse.ArgumentParser(description="AgdaJang agent bridge (report → policy → patch → check).")
    ap.add_argument("--input", "--file", dest="file", required=True,
                    help="Path to an .agda file with `{!!}` holes.")
    ap.add_argument("--output", default=None,
                    help="Where to write the patched file. If omitted, overwrites --input.")
    ap.add_argument("--policy", default=f"{sys.executable} python/tools/policy_fixture.py",
                    help="Policy command (quoted). Default: python/tools/policy_fixture.py")
    ap.add_argument("--agda-bin", default="agda", help="Agda binary")
    ap.add_argument("--agda-flags", default="", help="Extra flags passed to Agda (quoted string)")
    ap.add_argument("--include", action="append", default=[], help="Extra -i include dirs (repeatable)")
    ap.add_argument("--timeout", type=float, default=None, help="Timeout (seconds) for each process invocation")
    ap.add_argument("--keep-workdir", action="store_true", help="Keep the working directory for inspection")
    ap.add_argument("--max-holes", type=int, default=4, help="Max number of holes to solve")
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
        output=Path(args.output).resolve() if args.output else None,
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

    # Write atomically (prefer --output if provided)
    out_path = cfg.output if cfg.output is not None else cfg.file
    if out_path.suffix.lower() == ".agda" and out_path.stem != cfg.file.stem:
        print(
            f"[agent-bridge] NOTE: output filename stem '{out_path.stem}' "
            f"does not match module/file stem '{cfg.file.stem}'. "
            f"Agda will reject this if you typecheck '{out_path.name}'.",
            file=sys.stderr,
        )
    write_text_atomic(out_path, res.value)
    print(f"[agent-bridge] OK: wrote patched file: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
