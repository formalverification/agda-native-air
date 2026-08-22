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


def relative_to(root: str, path: str) -> str:
    """`path` relative to `root` when it is under it, else `path` unchanged.

    The manifest records absolute paths, which name one machine's directory
    layout.  A published coverage report is more useful — and comparable
    between two machines — with the run's own out-dir factored out.
    """
    if not root or not path:
        return path
    root = root.rstrip("/")
    return path[len(root) + 1 :] if path.startswith(root + "/") else path


def coverage_to_json(
    coverage: Coverage,
    library: str,
    requested: int,
    out_root: str = "",
    requested_source: str = "run-manifest",
) -> Dict:
    """The `coverage.json` document.  Failures come first: they are the point."""
    return {
        "schema": COVERAGE_SCHEMA,
        "library": library,
        "modulesRequested": requested,
        # "run-manifest" when the run recorded its own module list, which is
        # the only source that cannot have changed since; "modules-file" when
        # falling back to re-reading the file the run merely pointed at.
        "modulesRequestedFrom": requested_source,
        # Artifact paths below are relative to this, the extraction out-dir.
        "outRoot": out_root,
        "summary": {
            "attempted": coverage.attempted,
            "succeeded": coverage.succeeded,
            "failed": coverage.failed,
            "notAttempted": coverage.not_attempted,
            "resumed": coverage.resumed,
            "rows": coverage.rows,
        },
        "failures": [_outcome_to_json(o, out_root) for o in coverage.failures],
        "modules": [_outcome_to_json(o, out_root) for o in coverage.outcomes],
    }


def _outcome_to_json(o: ModuleOutcome, out_root: str = "") -> Dict:
    return {
        "module": o.module,
        "status": o.status,
        "rows": o.rows,
        "seconds": round(o.seconds, 3),
        "resumed": o.skipped,
        "exitCode": o.exit_code,
        "reasons": list(o.reasons),
        "outputFile": relative_to(out_root, o.output_file),
        "logFile": relative_to(out_root, o.log_file),
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
    library_commit_source: str,
    library_commit_live: str,
    library_remote: str,
    library_dirty: bool,
    library_untracked: int,
    library_untracked_sources: Sequence[str],
    repo_commit: str,
    repo_dirty: bool,
    repo_untracked: int,
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
            # Where the commit above came from, and what the checkout says now.
            # They differ when the library moved between extraction and
            # packaging, in which case the corpus describes `commit` and the
            # checkout no longer does.
            "commitRecordedBy": library_commit_source,
            "commitAtPackagingTime": library_commit_live,
            "commitMatchesCheckout": library_commit == library_commit_live,
            "workingTreeDirty": library_dirty,
            "untrackedFiles": library_untracked,
            # The untracked files that can actually change the corpus: the
            # metadata scanner globs the include dirs, so an untracked module
            # under srcDir is extracted like any other.  A non-empty list here
            # means the commit above does not fully describe what was read.
            "untrackedSourcesUnderSrc": list(library_untracked_sources),
            "srcDir": manifest.get("srcDir", ""),
        },
        "producer": {
            "repository": "formalverification/agda-native-air",
            "commit": repo_commit,
            "workingTreeDirty": repo_dirty,
            "untrackedFiles": repo_untracked,
            "extractor": "struxdriver.extract.AgdaJsonlDriver",
            "backend": manifest.get("agdaJsonBin", ""),
        },
        "toolchain": {
            # Unlike the commits above, these are read WHEN PACKAGING RUNS, not
            # when the extraction did — the driver has no reliable way to
            # record them (the pinned Agda is linked into `agda-json`, so an
            # `agda --version` from PATH would describe a different binary).
            # Said plainly here rather than left to be assumed.
            "sampledAt": "packaging-time",
            "agda": agda_version,
            "agdaLibraries": list(agda_libraries),
            "flakeInputs": flake_pins,
        },
        "run": {
            "startedAt": manifest.get("startedAt", ""),
            "finishedAt": manifest.get("finishedAt", ""),
            # `runner` is what was asked for; `runnerEffective` is what ran.
            # They differ when Spark failed and the driver fell back to local.
            "runner": manifest.get("runner", ""),
            "runnerEffective": manifest.get(
                "runnerEffective", manifest.get("runner", "")
            ),
            "sparkFallback": bool(manifest.get("sparkFallback", False)),
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
    """True when tracked files differ from HEAD."""
    return _git_or(["status", "--porcelain", "--untracked-files=no"], repo, "") != ""


def _untracked_files(repo: Path) -> Tuple[str, ...]:
    """Every untracked file in `repo`, as repo-relative paths.

    `--untracked-files=all` rather than the default: git collapses an untracked
    directory to a single `dir/` entry, which would hide the files inside it.
    """
    out = _git_or(["status", "--porcelain", "--untracked-files=all"], repo, "")
    return tuple(
        line[3:].strip('"')
        for line in out.splitlines()
        if line.startswith("?? ")
    )


def untracked_sources_under(
    src_dir: str, repo: Path, untracked: Sequence[str]
) -> Tuple[str, ...]:
    """Untracked Agda sources inside the extracted include dir.

    These are the untracked files that matter: the metadata scanner globs the
    library's include dirs for `*.agda` / `*.lagda*`, so an untracked module
    there IS extracted and DOES change the corpus.  Reporting only tracked
    dirtiness would call such a tree clean — the original comment here claimed
    untracked files "cannot change what Agda read", which was wrong (issue #84
    review).

    Other untracked files (notes, patches, images) are counted separately but
    not listed: they cannot reach the corpus.
    """
    if not src_dir:
        return ()
    try:
        rel_src = str(Path(src_dir).resolve().relative_to(repo.resolve()))
    except ValueError:
        # The src dir is not inside this checkout; nothing to attribute.
        return ()
    prefix = "" if rel_src == "." else rel_src.rstrip("/") + "/"
    return tuple(
        sorted(
            path
            for path in untracked
            if path.startswith(prefix) and _is_agda_source(path)
        )
    )


def _is_agda_source(path: str) -> bool:
    """Whether a path is a file Agda would treat as a module source."""
    return path.endswith(".agda") or ".lagda" in Path(path).name


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


def observed_type_ast_versions(corpus: Path) -> Result[Tuple[str, ...], PipelineError]:
    """Distinct `typeAstVersion` values across EVERY row.

    The card must state the encoding version it ships, and reading it back off
    the rows is the only claim that cannot drift from the data — so the scan
    covers the whole file.  A sample would make the provenance record say
    "these versions" while meaning "these versions in the part I looked at",
    which is exactly the kind of claim a dataset card must not contain.
    """
    versions: List[str] = []
    try:
        with corpus.open("r", encoding="utf-8") as handle:
            for i, line in enumerate(handle):
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

    # What the run was asked to cover.  The manifest's own snapshot is
    # authoritative: `modulesFile` is only a path, and regenerating metadata
    # between extraction and packaging would otherwise change what "requested"
    # meant — marking new modules `not_attempted` and keeping removed ones.
    # The file is the fallback for a manifest written before the snapshot
    # existed.
    manifest_modules = manifest.get("modules")
    if isinstance(manifest_modules, list) and manifest_modules:
        requested: Tuple[str, ...] = tuple(sorted(str(m) for m in manifest_modules))
        requested_source = "run-manifest"
    else:
        requested_result = read_text(Path(args.modules_file)).map(parse_modules_file)
        if requested_result.is_err:
            return Result.err(requested_result.unwrap_err())
        requested = requested_result.unwrap()
        requested_source = "modules-file"

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

    # The manifest counted the rows when it validated each module; this counted
    # them again from the files on disk just now.  If a per-module JSONL was
    # truncated or replaced in between, the two disagree — and publishing would
    # ship a `coverage.json` whose row total contradicts `provenance.json`.
    # Refuse rather than reconcile: the fix is to re-extract, not to pick one.
    expected_rows = sum(o.rows for o in coverage.outcomes if o.status == "succeeded")
    if rows != expected_rows:
        return Result.err(
            PipelineError(
                ErrorType.VALIDATION_ERROR,
                "assembled row count does not match the extraction manifest; "
                "a per-module JSONL changed after it was validated",
                context={
                    "assembled": rows,
                    "manifestExpected": expected_rows,
                    "jsonlDir": args.jsonl_dir,
                },
            )
        )

    versions_result = observed_type_ast_versions(corpus_path)
    if versions_result.is_err:
        return Result.err(versions_result.unwrap_err())

    library_root = Path(args.library_root)
    repo_root = Path(args.repo_root)
    library_untracked = _untracked_files(library_root)
    src_dir = str(manifest.get("srcDir", ""))
    flake_lock = load_json(Path(args.flake_lock)).map(flake_lock_pins).unwrap_or({})
    agda_libraries = (
        read_text(Path(args.agda_libraries_file)).map(library_paths_in).unwrap_or(())
        if args.agda_libraries_file
        else ()
    )

    # The library commit belongs to the extraction, not to this packaging run:
    # `make corpus` consumes an existing raw tree, so checking out another
    # commit in between would otherwise label old JSONL with the new one.  Use
    # what the manifest recorded, and report the live checkout separately so a
    # mismatch is visible rather than silently resolved.
    recorded_commit = str(manifest.get("srcCommit", "") or "")
    live_commit = _git_or(["rev-parse", "HEAD"], library_root, "unknown")
    provenance = build_provenance(
        library=args.library,
        library_commit=recorded_commit or live_commit,
        library_commit_source="run-manifest" if recorded_commit else "packaging-time",
        library_commit_live=live_commit,
        library_remote=_git_or(["remote", "get-url", "origin"], library_root, "unknown"),
        library_dirty=(
            bool(manifest.get("srcDirty"))
            if recorded_commit
            else _worktree_dirty(library_root)
        ),
        library_untracked=len(library_untracked),
        library_untracked_sources=untracked_sources_under(
            src_dir, library_root, library_untracked
        ),
        # Same time-of-check reasoning as the library: the extraction was run
        # by some commit of this repository, and packaging can happen from
        # another without the rows changing.
        repo_commit=str(manifest.get("producerCommit", "") or "")
        or _git_or(["rev-parse", "HEAD"], repo_root, "unknown"),
        repo_dirty=(
            bool(manifest.get("producerDirty"))
            if manifest.get("producerCommit")
            else _worktree_dirty(repo_root)
        ),
        repo_untracked=len(_untracked_files(repo_root)),
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
        (
            coverage_path,
            coverage_to_json(
                coverage,
                args.library,
                len(requested),
                str(manifest.get("outDir", "")),
                requested_source,
            ),
        ),
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


def _summary() -> str:
    """The `Description:` line of this module's docstring, for `--help`.

    Read by name rather than by line number: indexing into `__doc__` silently
    produced an empty description the first time.
    """
    for line in (__doc__ or "").splitlines():
        if line.startswith("Description:"):
            return line.split(":", 1)[1].strip()
    return ""


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=_summary())
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
