"""
agda_probe.py

File: agda-dojang/python/utils/agda_probe.py

Description:
  The primitives for probing Agda about one hole in one source file: locate the
  next `{!!}`, rewrite it (with a reporting macro, or with a candidate term),
  run Agda over the rewritten file, and read a verdict out of what Agda printed.

  Three concerns live here, in that order:

  1.  Source surgery.  `find_next_hole` and the `build_*_variant` functions turn
      a fixture's text into the exact text we want Agda to see.
  2.  Invocation.  `ProbeConfig` names everything a run needs; `run_agda` and
      `collect_output` execute it and normalise Agda's chatter into `(rc, out)`.
      A run against a *shadow copy* of the module needs its include path pruned
      so Agda does not see the original and the copy at once; hence
      `ensure_overlay_dir` and the flag/include filtering below it.
  3.  Verdict reading.  `only_unsolved_metas` and `filled_hole_still_unsolved`
      distinguish "Agda accepted the term" from "Agda merely deferred", which is
      what stops a candidate like `_` or `?` from scoring as a solution.

Provenance:
  Relocated from `tools/agent_bridge.py` when the legacy Python bridge
  (`agent_bridge.py`, `report_parser.py`, `dojang_try.py`) was retired in favour
  of the `agda-mcp` server (issue #109).  Behaviour is unchanged; the bridge's
  own loop, its CLI, and its dead helpers did not come along, and the names the
  proof-completion evaluator imports are public here rather than underscored.
  `ProbeConfig` is the old `ProbeConfig` minus three fields (`output`,
  `keep_workdir`, `max_holes`) that only the retired CLI read.

  The evaluator `tools/eval_fixtures.py` is the one caller.  Agents reach the
  same capabilities through `agda-mcp` (`get_goal`, `fill_hole`), which is the
  Haskell port of this logic, not through anything here.

Design notes:
  + Errors are values.  Every fallible function returns `Result[..., PipelineError]`
    or a total answer; `raise` is not used for expected failures.
  + Effects at the edges.  Only `read_text`, `run_agda`, and `ensure_overlay_dir`
    touch the filesystem or spawn a process; everything else is pure over strings.
  + Stdlib and `utils.*` only, so this module stays free of any dependency on
    `tools/` and its tests run in the no-Agda unit-test lane.
"""
from __future__ import annotations

import os
import re
import shlex
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

from .command_runner import run_command
from .result import Ok, Result, Err
from .types import CommandResult, PipelineError


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
class ProbeConfig:
    file: Path
    policy_cmd: List[str]
    agda_bin: str
    agda_flags: str
    include_dirs: List[str]
    timeout_sec: Optional[float]
    top_k: int
    cwd: Optional[Path]

    # The Agda-side reporting macro call we inject in place of `{!!}`
    # (expects a trailing `?` to stand for "current goal hole term").
    report_expr: str


def ensure_overlay_dir(
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

    Mirrors the small safety in dojang_try.py:
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

def _flags_for_run(cfg: ProbeConfig, file_path: Path) -> List[str]:
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
    cfg: ProbeConfig,
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

def find_next_hole(src: str) -> Optional[HoleSpan]:
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

# =========================
# Reading Agda's verdict
# =========================

_UNSOLVED_HDR_RE = re.compile(
    r"Unsolved(?:\s+interaction)?\s+metas\s+at\s+the\s+following\s+locations:",
    re.IGNORECASE,
)
_ERR_LINE = ": error:"
_UNSOLVED_TAG = re.compile(r"\[Unsolved", re.IGNORECASE)
_POS = re.compile(r":(\d+)[\.,](\d+)")

def unsolved_meta_positions(out: str) -> List[Tuple[int, int]]:
    """
    Best-effort parse of the positions listed in Agda's “Unsolved metas …” block.
    We only care about (line, col) starts.
    """
    m = _UNSOLVED_HDR_RE.search(out)
    if not m:
        return []
    tail = out[m.end():]
    return [(int(m.group(1)), int(m.group(2))) for m in _POS.finditer(tail)]

def only_unsolved_metas(out: str) -> bool:
    """
    True iff the run appears to have failed *only* due to remaining unsolved metas.
    """
    if not _UNSOLVED_HDR_RE.search(out):
        return False

    # If Agda prints tagged error lines, ensure they’re only “unsolved meta” ones.
    err_lines = [ln for ln in out.splitlines() if _ERR_LINE in ln]
    if not err_lines:
        # Some runs only print the unsolved-metas header (rare); accept.
        return True

    def ok_line(ln: str) -> bool:
        return (("Unsolved" in ln and "metas" in ln) or bool(_UNSOLVED_TAG.search(ln)))

    return all(ok_line(ln) for ln in err_lines)

def filled_hole_still_unsolved(hole: HoleSpan, out: str) -> bool:
    """
    True iff Agda still reports an unsolved meta starting at the hole’s (line,col).
    This catches candidates like `_` or `?` that don’t actually solve the hole.
    """
    pos = set(unsolved_meta_positions(out))
    return (hole.line, hole.col) in pos

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
    cfg: ProbeConfig,
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

def strip_flag(flags: str, flag: str) -> str:
    """
    Remove a single flag token from a shell-ish flag string.
    Used so we can do a strict final typecheck without --allow-unsolved-metas,
    even if the caller included it for the reporting runs.
    """
    toks = shlex.split(flags) if flags else []
    toks = [t for t in toks if t != flag]
    return " ".join(shlex.quote(t) for t in toks)

# =========================
# Building the file Agda sees
# =========================

def build_report_variant(cfg: ProbeConfig, src: str, hole: HoleSpan) -> str:
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
