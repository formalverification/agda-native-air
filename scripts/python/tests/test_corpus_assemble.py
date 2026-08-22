"""
Tests for `scripts/python/corpus/assemble.py`.

File: scripts/python/tests/test_corpus_assemble.py

Description
-----------
Exercises the pure core (coverage classification, concatenation order,
provenance shape, flake-lock and libraries-file parsing) directly, and the
streaming concatenation against real temporary files.

The coverage tests are the point of the suite: the deliverable for issue #84
is a corpus *with an honest failure list*, so "a module in the modules file
that the manifest never mentions is reported, not dropped" is a contract, not
an implementation detail.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_corpus_assemble.py`
"""

from __future__ import annotations

import gzip
import json
from pathlib import Path

from scripts.python.corpus.assemble import (
    Coverage,
    _parser,
    _summary,
    assemble,
    build_provenance,
    compute_coverage,
    concatenate,
    concatenation_order,
    coverage_to_json,
    flake_lock_pins,
    gzip_file,
    library_paths_in,
    module_jsonl_path,
    observed_type_ast_versions,
    outcome_of_result,
    parse_modules_file,
    relative_to,
    untracked_sources_under,
)


# ---------------------------------------------------------------------------
# Modules file
# ---------------------------------------------------------------------------


def test_parse_modules_file_drops_blanks_and_comments() -> None:
    text = "Overture.Basic\n\n# a comment\nAlgebras.Basic\n  Terms.Basic  \n"
    assert parse_modules_file(text) == ("Algebras.Basic", "Overture.Basic", "Terms.Basic")


def test_parse_modules_file_dedupes_and_sorts() -> None:
    assert parse_modules_file("B\nA\nB\n") == ("A", "B")


# ---------------------------------------------------------------------------
# Coverage
# ---------------------------------------------------------------------------


def _result(module: str, ok: bool, **kw: object) -> dict:
    base = {
        "module": module,
        "inputFile": f"/src/{module}.lagda.md",
        "outputFile": f"/out/jsonl/{module}.jsonl",
        "logFile": f"/out/logs/{module}.log",
        "skipped": False,
        "ok": ok,
        "seconds": 1.5,
        "rows": 10 if ok else 0,
        "validateOk": ok,
        "validateErrors": [] if ok else ["exit_code=1"],
    }
    base.update(kw)
    return base


def test_outcome_of_result_reads_a_success() -> None:
    o = outcome_of_result(_result("Overture.Basic", True, exitCode=0))
    assert o.status == "succeeded"
    assert o.rows == 10
    assert o.reasons == ()


def test_outcome_of_result_keeps_the_failure_reason() -> None:
    o = outcome_of_result(_result("Broken.Module", False, exitCode=1))
    assert o.status == "failed"
    assert o.reasons == ("exit_code=1",)
    assert o.log_file == "/out/logs/Broken.Module.log"


def test_a_failure_with_no_recorded_error_still_states_one() -> None:
    o = outcome_of_result(_result("Silent", False, validateErrors=[]))
    assert o.status == "failed"
    assert o.reasons == ("failed with no recorded reason",)


def test_compute_coverage_counts_every_outcome() -> None:
    manifest = {
        "results": [
            _result("A", True),
            _result("B", True, skipped=True),
            _result("C", False),
        ]
    }
    coverage = compute_coverage(manifest, ("A", "B", "C"))

    assert coverage.attempted == 3
    assert coverage.succeeded == 2
    assert coverage.failed == 1
    assert coverage.not_attempted == 0
    assert coverage.resumed == 1
    assert coverage.rows == 20


def test_compute_coverage_reports_a_module_the_run_never_touched() -> None:
    manifest = {"results": [_result("A", True)]}
    coverage = compute_coverage(manifest, ("A", "Skipped.Entirely"))

    assert coverage.not_attempted == 1
    statuses = {o.module: o.status for o in coverage.outcomes}
    assert statuses["Skipped.Entirely"] == "not_attempted"
    # It is a failure for reporting purposes, so the card cannot miss it.
    assert "Skipped.Entirely" in {o.module for o in coverage.failures}


def test_compute_coverage_sorts_outcomes_by_module() -> None:
    manifest = {"results": [_result("Z", True), _result("A", True)]}
    coverage = compute_coverage(manifest, ())
    assert [o.module for o in coverage.outcomes] == ["A", "Z"]


def test_relative_to_factors_out_the_out_dir() -> None:
    assert relative_to("/out", "/out/jsonl/A.jsonl") == "jsonl/A.jsonl"


def test_relative_to_tolerates_a_trailing_slash() -> None:
    assert relative_to("/out/", "/out/logs/A.log") == "logs/A.log"


def test_relative_to_leaves_an_unrelated_path_alone() -> None:
    # Not under the root: better an absolute path than a wrong relative one.
    assert relative_to("/out", "/elsewhere/A.jsonl") == "/elsewhere/A.jsonl"
    # A sibling whose name merely starts the same way is not "under" it.
    assert relative_to("/out", "/outside/A.jsonl") == "/outside/A.jsonl"


def test_relative_to_passes_empties_through() -> None:
    assert relative_to("", "/out/A.jsonl") == "/out/A.jsonl"
    assert relative_to("/out", "") == ""


def test_coverage_to_json_reports_paths_relative_to_the_out_dir() -> None:
    manifest = {"results": [_result("A", True)]}
    doc = coverage_to_json(
        compute_coverage(manifest, ("A",)), "agda-algebras", 1, out_root="/out"
    )

    assert doc["outRoot"] == "/out"
    assert doc["modules"][0]["outputFile"] == "jsonl/A.jsonl"
    assert doc["modules"][0]["logFile"] == "logs/A.log"


def test_coverage_to_json_leads_with_failures() -> None:
    manifest = {"results": [_result("A", True), _result("B", False)]}
    doc = coverage_to_json(compute_coverage(manifest, ("A", "B")), "agda-algebras", 2)

    assert doc["summary"] == {
        "attempted": 2,
        "succeeded": 1,
        "failed": 1,
        "notAttempted": 0,
        "resumed": 0,
        "rows": 10,
    }
    assert [f["module"] for f in doc["failures"]] == ["B"]
    assert len(doc["modules"]) == 2
    assert doc["modulesRequested"] == 2


# ---------------------------------------------------------------------------
# Ordering
# ---------------------------------------------------------------------------


def test_module_jsonl_path_nests_on_dots() -> None:
    assert module_jsonl_path(Path("/out/jsonl"), "Overture.Signatures") == Path(
        "/out/jsonl/Overture/Signatures.jsonl"
    )


def test_module_jsonl_path_handles_a_top_level_module() -> None:
    assert module_jsonl_path(Path("/out/jsonl"), "Everything") == Path(
        "/out/jsonl/Everything.jsonl"
    )


def test_concatenation_order_is_sorted_and_omits_failures() -> None:
    manifest = {"results": [_result("Z", True), _result("A", True), _result("M", False)]}
    coverage = compute_coverage(manifest, ())
    order = concatenation_order(Path("/out/jsonl"), coverage)

    assert order == (Path("/out/jsonl/A.jsonl"), Path("/out/jsonl/Z.jsonl"))


# ---------------------------------------------------------------------------
# Concatenation
# ---------------------------------------------------------------------------


def _write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def test_concatenate_counts_rows_and_is_deterministic(tmp_path: Path) -> None:
    a = _write(tmp_path / "a.jsonl", '{"n":1}\n{"n":2}\n')
    b = _write(tmp_path / "b.jsonl", '{"n":3}\n')
    target = tmp_path / "out" / "corpus.jsonl"

    rows, size, digest = concatenate((a, b), target).unwrap()

    assert rows == 3
    assert size == target.stat().st_size
    assert target.read_text(encoding="utf-8") == '{"n":1}\n{"n":2}\n{"n":3}\n'

    again = concatenate((a, b), target).unwrap()
    assert again == (rows, size, digest)


def test_concatenate_repairs_a_missing_final_newline(tmp_path: Path) -> None:
    a = _write(tmp_path / "a.jsonl", '{"n":1}')
    b = _write(tmp_path / "b.jsonl", '{"n":2}\n')
    target = tmp_path / "corpus.jsonl"

    rows, _, _ = concatenate((a, b), target).unwrap()

    assert rows == 2
    assert target.read_text(encoding="utf-8") == '{"n":1}\n{"n":2}\n'


def test_concatenate_errs_on_a_missing_module_file(tmp_path: Path) -> None:
    result = concatenate((tmp_path / "absent.jsonl",), tmp_path / "corpus.jsonl")
    assert result.is_err
    assert "absent.jsonl" in result.unwrap_err().message


def test_gzip_file_round_trips_and_is_reproducible(tmp_path: Path) -> None:
    source = _write(tmp_path / "corpus.jsonl", '{"n":1}\n')
    first = tmp_path / "one.gz"
    second = tmp_path / "two.gz"

    assert gzip_file(source, first).unwrap() == first.stat().st_size
    gzip_file(source, second).unwrap()

    assert gzip.decompress(first.read_bytes()) == source.read_bytes()
    # mtime=0 means two gzips of the same bytes are the same bytes.
    assert first.read_bytes() == second.read_bytes()


def test_observed_type_ast_versions_reads_them_off_the_rows(tmp_path: Path) -> None:
    corpus = _write(
        tmp_path / "corpus.jsonl",
        json.dumps({"typeAstVersion": "0.3-v0"})
        + "\n"
        + json.dumps({"typeAstVersion": "0.3-v0"})
        + "\n",
    )
    assert observed_type_ast_versions(corpus).unwrap() == ("0.3-v0",)


def test_observed_type_ast_versions_scans_past_any_sample_size(tmp_path: Path) -> None:
    # A version that appears only late in the file must still be reported: a
    # sampled scan would let provenance claim a single encoding for a corpus
    # that has two.
    rows = [json.dumps({"typeAstVersion": "0.3-v0"})] * 6000
    rows.append(json.dumps({"typeAstVersion": "0.4-v0"}))
    corpus = _write(tmp_path / "corpus.jsonl", "\n".join(rows) + "\n")

    assert observed_type_ast_versions(corpus).unwrap() == ("0.3-v0", "0.4-v0")


def test_observed_type_ast_versions_reports_a_bad_line(tmp_path: Path) -> None:
    corpus = _write(tmp_path / "corpus.jsonl", "not json\n")
    result = observed_type_ast_versions(corpus)
    assert result.is_err
    assert "not valid JSON" in result.unwrap_err().message


# ---------------------------------------------------------------------------
# Provenance
# ---------------------------------------------------------------------------


def _provenance_args(**overrides: object) -> dict:
    """Default arguments for `build_provenance`, overridable per test."""
    args = {
        "library": "agda-algebras",
        "library_commit": "cafe123",
        "library_commit_source": "run-manifest",
        "library_commit_live": "cafe123",
        "library_remote": "git@github.com:ualib/agda-algebras.git",
        "library_dirty": False,
        "library_untracked": 0,
        "library_untracked_sources": (),
        "repo_commit": "beef456",
        "repo_dirty": False,
        "repo_untracked": 0,
        "manifest": _manifest(),
        "coverage": Coverage(1, 1, 0, 0, 0, 10, ()),
        "flake_pins": {},
        "agda_libraries": (),
        "agda_version": "Agda version 2.8.0",
        "type_ast_versions": ("0.3-v0",),
        "corpus_rows": 10,
        "corpus_bytes": 100,
        "corpus_sha256": "abc",
    }
    args.update(overrides)
    return args


def test_flake_lock_pins_keeps_the_revision_of_each_input() -> None:
    lock = {
        "nodes": {
            "root": {"inputs": {"nixpkgs": "nixpkgs"}},
            "nixpkgs": {
                "locked": {
                    "type": "github",
                    "owner": "NixOS",
                    "repo": "nixpkgs",
                    "rev": "deadbeef",
                    "narHash": "sha256-xyz",
                }
            },
            "flake-utils": {"original": {"type": "github"}},
        }
    }
    pins = flake_lock_pins(lock)

    assert pins["nixpkgs"]["rev"] == "deadbeef"
    assert "root" not in pins
    # An input with no `locked` entry pins nothing, so it is omitted.
    assert "flake-utils" not in pins


def test_library_paths_in_reads_the_registered_agda_libs() -> None:
    text = "-- comment\n/nix/store/abc/standard-library.agda-lib\n\n/repo/agda-dojang.agda-lib\n"
    assert library_paths_in(text) == (
        "/nix/store/abc/standard-library.agda-lib",
        "/repo/agda-dojang.agda-lib",
    )


def test_untracked_sources_under_finds_a_module_that_would_be_extracted() -> None:
    repo = Path("/lib")
    untracked = (
        "src/Scratch/Probe.lagda.md",   # extracted: the scanner globs src/
        "src/Other.agda",               # extracted
        "notes.md",                     # cannot reach the corpus
        "docs/assets/portrait.jpg",     # cannot reach the corpus
        "other/Elsewhere.agda",         # Agda source, but outside src/
    )
    assert untracked_sources_under("/lib/src", repo, untracked) == (
        "src/Other.agda",
        "src/Scratch/Probe.lagda.md",
    )


def test_untracked_sources_under_covers_every_literate_flavour() -> None:
    repo = Path("/lib")
    untracked = tuple(
        f"src/M{i}{ext}"
        for i, ext in enumerate(
            (".agda", ".lagda", ".lagda.md", ".lagda.rst", ".lagda.tex", ".lagda.org")
        )
    )
    assert len(untracked_sources_under("/lib/src", repo, untracked)) == len(untracked)


def test_untracked_sources_under_ignores_a_src_dir_outside_the_checkout() -> None:
    # A srcDir from another machine's layout attributes nothing.
    assert untracked_sources_under("/elsewhere/src", Path("/lib"), ("src/A.agda",)) == ()


def test_untracked_sources_under_handles_an_empty_src_dir() -> None:
    assert untracked_sources_under("", Path("/lib"), ("src/A.agda",)) == ()


# ---------------------------------------------------------------------------
# Time-of-check: what the manifest recorded vs what packaging can see
# ---------------------------------------------------------------------------


def _manifest(**kw: object) -> dict:
    base = {
        "srcDir": "/src",
        "agdaJsonBin": "/bin/agda-json",
        "startedAt": "t0",
        "finishedAt": "t1",
        "runner": "spark",
        "sparkMaster": "local[4]",
        "parallelism": 8,
        "resume": False,
        "results": [_result("A", True)],
    }
    base.update(kw)
    return base


def test_provenance_carries_the_runner_that_actually_ran() -> None:
    # Spark failed and the driver fell back; publishing this as a Spark run
    # would misdescribe how the rows were produced.
    doc = build_provenance(**_provenance_args(
        manifest=_manifest(runnerEffective="local", sparkFallback=True)
    ))
    assert doc["run"]["runner"] == "spark"
    assert doc["run"]["runnerEffective"] == "local"
    assert doc["run"]["sparkFallback"] is True


def test_provenance_runner_defaults_to_the_requested_one() -> None:
    # A manifest written before the driver recorded an effective runner.
    doc = build_provenance(**_provenance_args(manifest=_manifest()))
    assert doc["run"]["runnerEffective"] == "spark"
    assert doc["run"]["sparkFallback"] is False


def test_provenance_flags_a_library_that_moved_after_extraction() -> None:
    doc = build_provenance(**_provenance_args(
        library_commit="extracted111",
        library_commit_source="run-manifest",
        library_commit_live="moved222",
    ))
    # The corpus describes the commit it was extracted from, and says plainly
    # that the checkout no longer does.
    assert doc["source"]["commit"] == "extracted111"
    assert doc["source"]["commitAtPackagingTime"] == "moved222"
    assert doc["source"]["commitMatchesCheckout"] is False
    assert doc["source"]["commitRecordedBy"] == "run-manifest"


def test_provenance_says_when_the_commit_was_only_sampled_at_packaging_time() -> None:
    doc = build_provenance(**_provenance_args(
        library_commit="cafe123",
        library_commit_source="packaging-time",
        library_commit_live="cafe123",
    ))
    assert doc["source"]["commitRecordedBy"] == "packaging-time"
    assert doc["source"]["commitMatchesCheckout"] is True


def test_coverage_names_where_the_requested_list_came_from() -> None:
    doc = coverage_to_json(
        compute_coverage(_manifest(), ("A",)), "agda-algebras", 1, "/out", "modules-file"
    )
    assert doc["modulesRequestedFrom"] == "modules-file"


def test_build_provenance_records_source_toolchain_and_coverage() -> None:
    coverage = Coverage(
        attempted=3, succeeded=2, failed=1, not_attempted=0, resumed=0, rows=20, outcomes=()
    )
    doc = build_provenance(
        library="agda-algebras",
        library_commit="cafe123",
        library_commit_source="run-manifest",
        library_commit_live="cafe123",
        library_remote="git@github.com:ualib/agda-algebras.git",
        library_dirty=False,
        library_untracked=7,
        library_untracked_sources=("src/Scratch/Probe.lagda.md",),
        repo_commit="beef456",
        repo_dirty=True,
        repo_untracked=2,
        manifest={
            "srcDir": "/src",
            "agdaJsonBin": "/bin/agda-json",
            "startedAt": "t0",
            "finishedAt": "t1",
            "runner": "spark",
            "parallelism": 8,
            "resume": True,
        },
        coverage=coverage,
        flake_pins={"nixpkgs": {"rev": "deadbeef"}},
        agda_libraries=("/nix/store/abc/standard-library.agda-lib",),
        agda_version="Agda version 2.8.0",
        type_ast_versions=("0.3-v0",),
        corpus_rows=20,
        corpus_bytes=4096,
        corpus_sha256="abc",
    )

    assert doc["source"]["commit"] == "cafe123"
    assert doc["source"]["workingTreeDirty"] is False
    # A clean tracked tree is not the whole story: an untracked module under
    # src/ is extracted like any other, so it is named rather than counted.
    assert doc["source"]["untrackedFiles"] == 7
    assert doc["source"]["untrackedSourcesUnderSrc"] == ["src/Scratch/Probe.lagda.md"]
    assert doc["producer"]["workingTreeDirty"] is True
    assert doc["producer"]["untrackedFiles"] == 2
    assert doc["toolchain"]["agda"] == "Agda version 2.8.0"
    assert doc["toolchain"]["flakeInputs"]["nixpkgs"]["rev"] == "deadbeef"
    assert doc["corpus"]["sha256"] == "abc"
    assert doc["corpus"]["typeAstVersions"] == ["0.3-v0"]
    assert doc["coverage"] == {
        "attempted": 3,
        "succeeded": 2,
        "failed": 1,
        "notAttempted": 0,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def test_summary_finds_the_description_line() -> None:
    # Read by name, not by line number: indexing into __doc__ gave an empty
    # --help description.
    assert _summary().startswith("Assemble a publishable")


# ---------------------------------------------------------------------------
# assemble() end to end, against a real extraction tree
# ---------------------------------------------------------------------------


ROW = '{"file":"X","module":"M","name":"f","qname":"M.f","prettyQname":"M.f",\
"type":"A","kind":"definition","astSize":1,"typeAstVersion":"0.3-v0"}'


def _extraction_tree(tmp_path: Path, rows_per_module: int = 2) -> Path:
    """A minimal <outDir>: two modules' JSONL plus a matching run-manifest."""
    out = tmp_path / "raw"
    (out / "jsonl").mkdir(parents=True)
    for mod in ("A", "B"):
        (out / "jsonl" / f"{mod}.jsonl").write_text(
            (ROW + "\n") * rows_per_module, encoding="utf-8"
        )
    manifest = {
        "srcDir": str(tmp_path / "src"),
        "outDir": str(out),
        "agdaJsonBin": "/bin/agda-json",
        "startedAt": "t0",
        "finishedAt": "t1",
        "runner": "spark",
        "runnerEffective": "local",
        "sparkFallback": True,
        "sparkMaster": "local[4]",
        "parallelism": 8,
        "resume": False,
        "srcCommit": "extracted111",
        "srcDirty": False,
        "producerCommit": "producer999",
        "producerDirty": False,
        "modules": ["A", "B"],
        "results": [
            _result("A", True, rows=rows_per_module),
            _result("B", True, rows=rows_per_module),
        ],
    }
    (out / "run-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    (tmp_path / "modules.txt").write_text("A\nB\n", encoding="utf-8")
    return out


def _args(tmp_path: Path, out: Path):
    return _parser().parse_args([
        "--jsonl-dir", str(out / "jsonl"),
        "--run-manifest", str(out / "run-manifest.json"),
        "--modules-file", str(tmp_path / "modules.txt"),
        "--out-dir", str(tmp_path / "corpus"),
        "--library-root", str(tmp_path),
        "--repo-root", str(tmp_path),
        "--flake-lock", str(tmp_path / "flake.lock"),
        "--agda-version", "Agda version 2.8.0",
    ])


def test_assemble_writes_a_corpus_from_a_consistent_tree(tmp_path: Path) -> None:
    out = _extraction_tree(tmp_path)
    result = assemble(_args(tmp_path, out))

    assert result.is_ok, result.unwrap_err() if result.is_err else ""
    a = result.unwrap()
    assert a.rows == 4
    provenance = json.loads(a.provenance.read_text(encoding="utf-8"))
    # Facts recorded by the run beat facts re-derived at packaging time.
    assert provenance["source"]["commit"] == "extracted111"
    assert provenance["source"]["commitRecordedBy"] == "run-manifest"
    assert provenance["run"]["runnerEffective"] == "local"
    assert provenance["run"]["sparkFallback"] is True
    assert provenance["producer"]["commit"] == "producer999"
    # Toolchain facts cannot be recorded by the run, and say so.
    assert provenance["toolchain"]["sampledAt"] == "packaging-time"
    coverage = json.loads(a.coverage.read_text(encoding="utf-8"))
    assert coverage["modulesRequestedFrom"] == "run-manifest"


def test_assemble_refuses_a_module_file_that_changed_after_validation(tmp_path: Path) -> None:
    out = _extraction_tree(tmp_path)
    # The manifest says B has 2 rows; the file on disk now has 1.  Assembly
    # used to succeed and publish a coverage total contradicting provenance.
    (out / "jsonl" / "B.jsonl").write_text(ROW + "\n", encoding="utf-8")

    result = assemble(_args(tmp_path, out))

    assert result.is_err
    err = result.unwrap_err()
    assert "does not match the extraction manifest" in err.message
    assert err.context["assembled"] == 3
    assert err.context["manifestExpected"] == 4


def test_assemble_uses_the_manifest_module_list_over_a_changed_file(tmp_path: Path) -> None:
    out = _extraction_tree(tmp_path)
    # Metadata regenerated between extraction and packaging: the file now names
    # a module the run never saw.  Reading the file would report it
    # `not_attempted` and inflate `modulesRequested`.
    (tmp_path / "modules.txt").write_text("A\nB\nC\n", encoding="utf-8")

    a = assemble(_args(tmp_path, out)).unwrap()
    coverage = json.loads(a.coverage.read_text(encoding="utf-8"))

    assert coverage["modulesRequested"] == 2
    assert coverage["summary"]["notAttempted"] == 0
    assert coverage["modulesRequestedFrom"] == "run-manifest"


def test_assemble_falls_back_to_the_modules_file_without_a_snapshot(tmp_path: Path) -> None:
    out = _extraction_tree(tmp_path)
    manifest = json.loads((out / "run-manifest.json").read_text(encoding="utf-8"))
    del manifest["modules"]
    del manifest["srcCommit"]
    (out / "run-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    a = assemble(_args(tmp_path, out)).unwrap()
    coverage = json.loads(a.coverage.read_text(encoding="utf-8"))
    provenance = json.loads(a.provenance.read_text(encoding="utf-8"))

    assert coverage["modulesRequestedFrom"] == "modules-file"
    assert provenance["source"]["commitRecordedBy"] == "packaging-time"
