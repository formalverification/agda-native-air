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
    _summary,
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


def test_build_provenance_records_source_toolchain_and_coverage() -> None:
    coverage = Coverage(
        attempted=3, succeeded=2, failed=1, not_attempted=0, resumed=0, rows=20, outcomes=()
    )
    doc = build_provenance(
        library="agda-algebras",
        library_commit="cafe123",
        library_remote="git@github.com:ualib/agda-algebras.git",
        library_dirty=False,
        repo_commit="beef456",
        repo_dirty=True,
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
    assert doc["producer"]["workingTreeDirty"] is True
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
