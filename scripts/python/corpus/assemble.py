#!/usr/bin/env python3
"""
File: scripts/python/corpus/assemble.py

Description: Assemble a publishable agda-strux corpus from an extraction tree.

  `AgdaJsonlDriver` writes one JSONL file per Agda module plus a
  `run-manifest.json` recording what it attempted.  This script turns that
  tree into the three artifacts a release needs:

    +  `corpus.jsonl`     — every row, concatenated in a deterministic order.
    +  `coverage.json`    — modules attempted, succeeded, failed, and why.
    +  `provenance.json`  — library commit, toolchain pins, run configuration,
                            row counts, and the corpus digest.

  Nothing here interprets a row: the corpus is exactly what the backend
  emitted (docs/representation.md §3), so the schema contract is the
  backend's, not this script's.

Design Principles:
  +  Determinism.  Modules are concatenated in sorted order and rows keep
     their within-module order, so the same extraction assembles to the same
     bytes and the digest in `provenance.json` means something.
  +  Honesty about coverage.  A module that failed appears in `coverage.json`
     with its reason and its log path.  A module the extractor never attempted
     (present in the modules file, absent from the manifest) is reported as
     `not_attempted` rather than silently dropped.
  +  Pure core.  Coverage classification, ordering, and the provenance record
     are pure functions over data already read; I/O and `sys.exit` live in
     `main` and the small `_read_*` / `_write_*` shells.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

# The script is run as `python -m scripts.python.corpus.assemble` (or by path
# with the repo root on PYTHONPATH), so utils resolves as a sibling package.
from scripts.python.utils.command_runner import run_command
from scripts.python.utils.file_ops import load_json, read_text, write_json
from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
)

# Schema of the artifacts this script writes.  Bump when a field changes
# meaning; consumers must tolerate unknown fields (representation.md §3.2).
COVERAGE_SCHEMA = "agda-strux.coverage.v0"
PROVENANCE_SCHEMA = "agda-strux.provenance.v0"

# Read/write size for the streaming concatenation.  The corpus runs to tens of
# megabytes and a single row can be hundreds of kilobytes, so we never hold
# more than one module in memory.
_CHUNK = 1 << 20


# ---------------------------------------------------------------------------
# Domain types
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ModuleOutcome:
    """One module's fate in an extraction run, as the manifest recorded it."""

    module: str
    status: str  # "succeeded" | "failed" | "not_attempted"
    rows: int
    seconds: float
    skipped: bool  # served from a previous run (resume)
    exit_code: Optional[int]
    reasons: Tuple[str, ...]
    output_file: str
    log_file: str


@dataclass(frozen=True)
class Coverage:
    """Coverage of a whole run: the counts plus every module's outcome."""

    attempted: int
    succeeded: int
    failed: int
    not_attempted: int
    resumed: int
    rows: int
    outcomes: Tuple[ModuleOutcome, ...]

    @property
    def failures(self) -> Tuple[ModuleOutcome, ...]:
        return tuple(o for o in self.outcomes if o.status != "succeeded")


# ---------------------------------------------------------------------------
# Pure core — coverage
# ---------------------------------------------------------------------------


def parse_modules_file(text: str) -> Tuple[str, ...]:
    """Module names from an `everything-modules.txt`, comments and blanks out.

    Mirrors `AgdaJsonlDriver.readModules`, so the two agree on what the run
    was asked to cover.
    """
    lines = (line.strip() for line in text.splitlines())
    return tuple(sorted({line for line in lines if line and not line.startswith("#")}))


def outcome_of_result(entry: Dict) -> ModuleOutcome:
    """Convert one `run-manifest.json` result record into a `ModuleOutcome`."""
    ok = bool(entry.get("ok", False))
    errors = tuple(str(e) for e in entry.get("validateErrors", []))
    return ModuleOutcome(
        module=str(entry.get("module", "")),
        status="succeeded" if ok else "failed",
        rows=int(entry.get("rows", 0)),
        seconds=float(entry.get("seconds", 0.0)),
        skipped=bool(entry.get("skipped", False)),
        exit_code=entry.get("exitCode"),
        # A failure with no recorded error is still a failure; say so rather
        # than emitting an empty reason list that reads like a success.
        reasons=errors if errors or ok else ("failed with no recorded reason",),
        output_file=str(entry.get("outputFile", "")),
        log_file=str(entry.get("logFile", "")),
    )


def missing_outcome(module: str) -> ModuleOutcome:
    """A module the modules file asked for and the manifest never mentions."""
    return ModuleOutcome(
        module=module,
        status="not_attempted",
        rows=0,
        seconds=0.0,
        skipped=False,
        exit_code=None,
        reasons=("module is in the modules file but absent from the run manifest",),
        output_file="",
        log_file="",
    )


def compute_coverage(manifest: Dict, requested: Sequence[str]) -> Coverage:
    """Coverage from a run manifest, cross-checked against the modules file."""
    attempted = tuple(outcome_of_result(e) for e in manifest.get("results", []))
    seen = {o.module for o in attempted}
    missing = tuple(missing_outcome(m) for m in requested if m not in seen)
    outcomes = tuple(sorted(attempted + missing, key=lambda o: o.module))

    return Coverage(
        attempted=len(attempted),
        succeeded=sum(1 for o in outcomes if o.status == "succeeded"),
        failed=sum(1 for o in outcomes if o.status == "failed"),
        not_attempted=len(missing),
        resumed=sum(1 for o in outcomes if o.skipped),
        rows=sum(o.rows for o in outcomes),
        outcomes=outcomes,
    )


def coverage_to_json(coverage: Coverage, library: str, requested: int) -> Dict:
    """The `coverage.json` document.  Failures come first: they are the point."""
    return {
        "schema": COVERAGE_SCHEMA,
        "library": library,
        "modulesRequested": requested,
        "summary": {
            "attempted": coverage.attempted,
            "succeeded": coverage.succeeded,
            "failed": coverage.failed,
            "notAttempted": coverage.not_attempted,
            "resumed": coverage.resumed,
            "rows": coverage.rows,
        },
        "failures": [_outcome_to_json(o) for o in coverage.failures],
        "modules": [_outcome_to_json(o) for o in coverage.outcomes],
    }


def _outcome_to_json(o: ModuleOutcome) -> Dict:
    return {
        "module": o.module,
        "status": o.status,
        "rows": o.rows,
        "seconds": round(o.seconds, 3),
        "resumed": o.skipped,
        "exitCode": o.exit_code,
        "reasons": list(o.reasons),
        "outputFile": o.output_file,
        "logFile": o.log_file,
    }


# ---------------------------------------------------------------------------
# Pure core — ordering and provenance
# ---------------------------------------------------------------------------


def module_jsonl_path(jsonl_dir: Path, module: str) -> Path:
    """Where `AgdaJsonlDriver` put a module's rows: dots become directories."""
    return jsonl_dir.joinpath(*module.split(".")).with_suffix(".jsonl")


def concatenation_order(jsonl_dir: Path, coverage: Coverage) -> Tuple[Path, ...]:
    """Per-module JSONL files to concatenate, in deterministic order.

    Only modules the manifest calls succeeded are included: a failed module's
    file is either absent or partial, and a corpus is not the place to guess.
    """
    return tuple(
        module_jsonl_path(jsonl_dir, o.module)
        for o in coverage.outcomes
        if o.status == "succeeded"
    )


def flake_lock_pins(lock: Dict) -> Dict[str, Dict[str, str]]:
    """The pinned revision of every flake input, keyed by node name.

    This is the toolchain: Agda, the standard library, the JDK, Spark and
    Python all come from the locked nixpkgs, so its revision pins them all.
    """

    def pin(node: Dict) -> Optional[Dict[str, str]]:
        locked = node.get("locked")
        if not isinstance(locked, dict):
            return None
        keys = ("type", "owner", "repo", "rev", "ref", "narHash", "url")
        return {k: str(locked[k]) for k in keys if k in locked}

    nodes = lock.get("nodes", {})
    pinned = ((name, pin(node)) for name, node in nodes.items() if name != "root")
    return {name: p for name, p in pinned if p is not None}


def library_paths_in(libraries_file_text: str) -> Tuple[str, ...]:
    """The `.agda-lib` paths a project-local Agda libraries file registers.

    For a Nix-provided library the path *is* the version pin, which is why it
    belongs in the provenance record verbatim.
    """
    lines = (line.strip() for line in libraries_file_text.splitlines())
    return tuple(line for line in lines if line and not line.startswith("--"))


def build_provenance(
    *,
    library: str,
    library_commit: str,
    library_remote: str,
    library_dirty: bool,
    repo_commit: str,
    repo_dirty: bool,
    manifest: Dict,
    coverage: Coverage,
    flake_pins: Dict[str, Dict[str, str]],
    agda_libraries: Sequence[str],
    agda_version: str,
    type_ast_versions: Sequence[str],
    corpus_rows: int,
    corpus_bytes: int,
    corpus_sha256: str,
) -> Dict:
    """The `provenance.json` document: what was extracted, from what, by what."""
    return {
        "schema": PROVENANCE_SCHEMA,
        "corpus": {
            "library": library,
            "rowSchema": "agda-strux full JSONL, docs/representation.md §3",
            "typeAstVersions": list(type_ast_versions),
            "rows": corpus_rows,
            "bytes": corpus_bytes,
            "sha256": corpus_sha256,
        },
        "source": {
            "library": library,
            "remote": library_remote,
            "commit": library_commit,
            "workingTreeDirty": library_dirty,
            "srcDir": manifest.get("srcDir", ""),
        },
        "producer": {
            "repository": "formalverification/agda-native-air",
            "commit": repo_commit,
            "workingTreeDirty": repo_dirty,
            "extractor": "struxdriver.extract.AgdaJsonlDriver",
            "backend": manifest.get("agdaJsonBin", ""),
        },
        "toolchain": {
            "agda": agda_version,
            "agdaLibraries": list(agda_libraries),
            "flakeInputs": flake_pins,
        },
        "run": {
            "startedAt": manifest.get("startedAt", ""),
            "finishedAt": manifest.get("finishedAt", ""),
            "runner": manifest.get("runner", ""),
            "sparkMaster": manifest.get("sparkMaster", ""),
            "parallelism": manifest.get("parallelism", 0),
            "resume": manifest.get("resume", None),
            "modulesFile": manifest.get("modulesFile", ""),
        },
        "coverage": {
            "attempted": coverage.attempted,
            "succeeded": coverage.succeeded,
            "failed": coverage.failed,
            "notAttempted": coverage.not_attempted,
        },
    }


# ---------------------------------------------------------------------------
# Effectful shell
# ---------------------------------------------------------------------------


def _git(args: Sequence[str], repo: Path) -> Result[str, PipelineError]:
    """Run a read-only git command in `repo` and return its trimmed stdout."""
    return run_command(
        ["git", "-C", str(repo), *args], capture_output=True, text=True
    ).and_then(
        lambda cp: Result.ok(cp.stdout.strip())
        if cp.returncode == 0
        else Result.err(
            PipelineError(
                ErrorType.COMMAND_FAILED,
                f"git {' '.join(args)} failed in {repo}",
                context={"stderr": (cp.stderr or "").strip()},
            )
        )
    )


def _git_or(args: Sequence[str], repo: Path, default: str) -> str:
    """`_git`, but a missing remote or detached state is not fatal here."""
    return _git(args, repo).unwrap_or(default)


def _worktree_dirty(repo: Path) -> bool:
    """True when tracked files differ from HEAD.  Untracked files do not count:
    they cannot change what Agda read."""
    return _git_or(["status", "--porcelain", "--untracked-files=no"], repo, "") != ""


def concatenate(sources: Iterable[Path], target: Path) -> Result[Tuple[int, int, str], PipelineError]:
    """Concatenate JSONL files into `target`; return (rows, bytes, sha256).

    Streams: a corpus of tens of megabytes never lands in memory whole.  A
    source whose last line lacks a newline gets one, so rows never merge.
    """
    digest = hashlib.sha256()
    rows = 0
    written = 0

    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("wb") as out:
            for src in sources:
                if not src.is_file():
                    return Result.err(
                        PipelineError(
                            ErrorType.FILE_NOT_FOUND,
                            f"module JSONL missing: {src}",
                        )
                    )
                tail = b""
                with src.open("rb") as handle:
                    while True:
                        chunk = handle.read(_CHUNK)
                        if not chunk:
                            break
                        rows += chunk.count(b"\n")
                        digest.update(chunk)
                        out.write(chunk)
                        written += len(chunk)
                        tail = chunk[-1:]
                if tail and tail != b"\n":
                    digest.update(b"\n")
                    out.write(b"\n")
                    written += 1
                    rows += 1
        return Result.ok((rows, written, digest.hexdigest()))
    except OSError as exc:
        return Result.err(
            PipelineError(
                ErrorType.COMMAND_FAILED, f"failed writing {target}", cause=exc
            )
        )


def gzip_file(source: Path, target: Path) -> Result[int, PipelineError]:
    """Write a deterministic gzip of `source` (mtime 0) and return its size."""
    try:
        with source.open("rb") as raw, target.open("wb") as out:
            # mtime=0 and an empty stored filename keep the archive
            # byte-identical across runs, so the release asset can be verified
            # by digest like the corpus itself.  Without `filename=""`,
            # GzipFile records `out.name` in the header and two gzips of the
            # same bytes differ.
            with gzip.GzipFile(
                filename="", fileobj=out, mode="wb", compresslevel=9, mtime=0
            ) as gz:
                while True:
                    chunk = raw.read(_CHUNK)
                    if not chunk:
                        break
                    gz.write(chunk)
        return Result.ok(target.stat().st_size)
    except OSError as exc:
        return Result.err(
            PipelineError(ErrorType.COMMAND_FAILED, f"failed gzipping {source}", cause=exc)
        )


def observed_type_ast_versions(corpus: Path, limit: int = 5000) -> Result[Tuple[str, ...], PipelineError]:
    """Distinct `typeAstVersion` values in the first `limit` rows.

    The card must state the encoding version it ships; reading it back off the
    rows is the only claim that cannot drift from the data.
    """
    versions: List[str] = []
    try:
        with corpus.open("r", encoding="utf-8") as handle:
            for i, line in enumerate(handle):
                if i >= limit:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    version = str(json.loads(line).get("typeAstVersion", ""))
                except json.JSONDecodeError as exc:
                    return Result.err(
                        PipelineError(
                            ErrorType.PARSING_ERROR,
                            f"{corpus}:{i + 1} is not valid JSON",
                            cause=exc,
                        )
                    )
                if version and version not in versions:
                    versions.append(version)
        return Result.ok(tuple(sorted(versions)))
    except OSError as exc:
        return Result.err(
            PipelineError(ErrorType.COMMAND_FAILED, f"failed reading {corpus}", cause=exc)
        )


def agda_version_string(explicit: Optional[str]) -> str:
    """The pinned Agda's version: as given, else asked of `agda` on PATH."""
    if explicit:
        return explicit
    return (
        run_command(["agda", "--version"], capture_output=True, text=True)
        .and_then(
            lambda cp: Result.ok(cp.stdout.strip().splitlines()[0])
            if cp.returncode == 0 and cp.stdout.strip()
            else Result.err(PipelineError(ErrorType.COMMAND_FAILED, "agda --version failed"))
        )
        .unwrap_or("unknown")
    )


@dataclass(frozen=True)
class Assembly:
    """What an assembly produced, for `main` to report."""

    corpus: Path
    corpus_gz: Optional[Path]
    coverage: Path
    provenance: Path
    rows: int
    coverage_summary: Coverage


def assemble(args: argparse.Namespace) -> Result[Assembly, PipelineError]:
    """Read the extraction tree, write corpus + coverage + provenance."""
    out_dir = Path(args.out_dir)
    corpus_path = out_dir / "corpus.jsonl"

    manifest_result = load_json(Path(args.run_manifest))
    if manifest_result.is_err:
        return Result.err(manifest_result.unwrap_err())
    manifest = manifest_result.unwrap()

    requested_result = read_text(Path(args.modules_file)).map(parse_modules_file)
    if requested_result.is_err:
        return Result.err(requested_result.unwrap_err())
    requested = requested_result.unwrap()

    coverage = compute_coverage(manifest, requested)
    if coverage.succeeded == 0:
        return Result.err(
            PipelineError(
                ErrorType.VALIDATION_ERROR,
                "no module succeeded; refusing to assemble an empty corpus",
                context={"manifest": args.run_manifest},
            )
        )

    concat = concatenate(concatenation_order(Path(args.jsonl_dir), coverage), corpus_path)
    if concat.is_err:
        return Result.err(concat.unwrap_err())
    rows, corpus_bytes, corpus_sha = concat.unwrap()

    versions_result = observed_type_ast_versions(corpus_path)
    if versions_result.is_err:
        return Result.err(versions_result.unwrap_err())

    library_root = Path(args.library_root)
    flake_lock = load_json(Path(args.flake_lock)).map(flake_lock_pins).unwrap_or({})
    agda_libraries = (
        read_text(Path(args.agda_libraries_file)).map(library_paths_in).unwrap_or(())
        if args.agda_libraries_file
        else ()
    )

    provenance = build_provenance(
        library=args.library,
        library_commit=_git_or(["rev-parse", "HEAD"], library_root, "unknown"),
        library_remote=_git_or(["remote", "get-url", "origin"], library_root, "unknown"),
        library_dirty=_worktree_dirty(library_root),
        repo_commit=_git_or(["rev-parse", "HEAD"], Path(args.repo_root), "unknown"),
        repo_dirty=_worktree_dirty(Path(args.repo_root)),
        manifest=manifest,
        coverage=coverage,
        flake_pins=flake_lock,
        agda_libraries=agda_libraries,
        agda_version=agda_version_string(args.agda_version),
        type_ast_versions=versions_result.unwrap(),
        corpus_rows=rows,
        corpus_bytes=corpus_bytes,
        corpus_sha256=corpus_sha,
    )

    corpus_gz: Optional[Path] = None
    if args.gzip:
        gz_path = out_dir / "corpus.jsonl.gz"
        gz_result = gzip_file(corpus_path, gz_path)
        if gz_result.is_err:
            return Result.err(gz_result.unwrap_err())
        provenance["corpus"]["gzipBytes"] = gz_result.unwrap()
        provenance["corpus"]["gzipSha256"] = _sha256_of(gz_path)
        corpus_gz = gz_path

    coverage_path = out_dir / "coverage.json"
    provenance_path = out_dir / "provenance.json"
    for path, document in (
        (coverage_path, coverage_to_json(coverage, args.library, len(requested))),
        (provenance_path, provenance),
    ):
        written = write_json(path, document)
        if written.is_err:
            return Result.err(written.unwrap_err())

    return Result.ok(
        Assembly(
            corpus=corpus_path,
            corpus_gz=corpus_gz,
            coverage=coverage_path,
            provenance=provenance_path,
            rows=rows,
            coverage_summary=coverage,
        )
    )


def _sha256_of(path: Path) -> str:
    """Digest of a file, read in chunks."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(_CHUNK)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[2].strip())
    p.add_argument("--jsonl-dir", required=True, help="per-module JSONL tree (<outDir>/jsonl)")
    p.add_argument("--run-manifest", required=True, help="<outDir>/run-manifest.json")
    p.add_argument("--modules-file", required=True, help="everything-modules.txt used for the run")
    p.add_argument("--out-dir", required=True, help="where to write corpus/coverage/provenance")
    p.add_argument("--library", default="agda-algebras", help="library name for the records")
    p.add_argument("--library-root", required=True, help="checkout the library was read from")
    p.add_argument("--repo-root", default=".", help="agda-native-air checkout that produced the run")
    p.add_argument("--flake-lock", default="flake.lock", help="flake.lock pinning the toolchain")
    p.add_argument("--agda-libraries-file", default=None, help="project-local Agda libraries file")
    p.add_argument("--agda-version", default=None, help="Agda version string (else ask `agda`)")
    p.add_argument("--gzip", action="store_true", help="also write corpus.jsonl.gz")
    return p


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = _parser().parse_args(argv)
    result = assemble(args)

    if result.is_err:
        print(f"[assemble] {result.unwrap_err()}", file=sys.stderr)
        return 1

    a = result.unwrap()
    c = a.coverage_summary
    print(f"[assemble] corpus     : {a.corpus} ({a.rows} rows)")
    if a.corpus_gz is not None:
        print(f"[assemble] compressed : {a.corpus_gz}")
    print(f"[assemble] coverage   : {a.coverage}")
    print(f"[assemble] provenance : {a.provenance}")
    print(
        f"[assemble] modules    : attempted={c.attempted} succeeded={c.succeeded} "
        f"failed={c.failed} notAttempted={c.not_attempted}"
    )
    for outcome in c.failures:
        print(f"[assemble]   {outcome.status}: {outcome.module} — {'; '.join(outcome.reasons)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
