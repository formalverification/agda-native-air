"""
Tests for `scripts/python/demo/paths.py`.

File: scripts/python/tests/test_demo_paths.py

Description
-----------
Path normalization is the demo build's one safety property: a transcript in
the archive is full of the sweep machine's absolute paths, and none of them
may reach a published page.  The cases below are the ones that would get it
wrong in a way a spot check would miss: the work directory is a child of the
repository root, so its rule has to fire first; the client's own per-session
directory carries the same path with every separator turned into a dash; and
dictionary keys carry paths as readily as values do.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_demo_paths.py`
"""

from __future__ import annotations

from typing import Any, Dict

from scripts.python.demo.paths import (
    FORBIDDEN,
    PathMap,
    check_clean,
    normalize_text,
    normalize_value,
)

ROOT = "/home/someone/git/org/repo/worktrees/branch"
WORK = ROOT + "/data/benchmarks/reports/agent-bench/run-1/work/subject-1"

PMAP = PathMap(repo_root=ROOT, work_dir=WORK)


def _mcp(cwd: str) -> Dict[str, Any]:
    return {"mcpServers": {"agda": {
        "command": cwd + "/scripts/run-server.sh",
        "args": ["--cwd", cwd, "--timeout", "600"],
    }}}


def test_of_reads_both_anchors_from_the_archive() -> None:
    result = PathMap.of(_mcp(ROOT), {"cwd": WORK})
    assert result.is_ok
    assert result.unwrap() == PMAP


def test_of_names_the_missing_piece() -> None:
    no_cwd = {"mcpServers": {"agda": {"args": ["--timeout", "600"]}}}
    assert "--cwd" in str(PathMap.of(no_cwd, {"cwd": WORK}).unwrap_err())
    assert "cwd" in str(PathMap.of(_mcp(ROOT), {}).unwrap_err())
    assert "mcpServers" in str(PathMap.of({}, {"cwd": WORK}).unwrap_err())


def test_the_work_directory_wins_over_the_repository_root() -> None:
    # The whole point of the rule order: the work directory lies inside the
    # repository root, so rewriting the root first would leave the file
    # looking like any other file of the checkout.
    assert normalize_text(WORK + "/M.agda", PMAP) == "<work>/M.agda"
    assert normalize_text(ROOT + "/agda-dojang/agda", PMAP) == \
        "<repo>/agda-dojang/agda"


def test_a_bare_directory_keeps_its_anchor() -> None:
    assert normalize_text(WORK, PMAP) == "<work>"
    assert normalize_text(ROOT, PMAP) == "<repo>"


def test_the_client_session_slug_is_rewritten_too() -> None:
    # The client names its per-session directory after the working directory
    # with every separator turned into a dash, and a tool result that spilled
    # to disk is reported by that path.
    slug = WORK.replace("/", "-")
    spill = f"/home/someone/.claude/projects/{slug}/abc/tool-results/x"
    out = normalize_text(spill, PMAP)
    assert "<work>-slug" in out
    assert check_clean(out).is_ok


def test_the_nix_store_keeps_the_package_and_drops_the_hash() -> None:
    path = "/nix/store/0mkdwhwzshgsa7xknd81r8hvdp6gbmr6-agda-algebras-1.2/src/X"
    assert normalize_text(path, PMAP) == "<nix>/agda-algebras-1.2/src/X"


def test_the_runtime_directory_loses_its_uid() -> None:
    assert normalize_text("/run/user/1000/cc-socks/1.sock", PMAP) == \
        "<runtime>/cc-socks/1.sock"


def test_a_home_path_no_anchor_covers_still_goes() -> None:
    out = normalize_text("/home/nobody/.cache/thing", PMAP)
    assert out == "~/.cache/thing"
    assert check_clean(out).is_ok


def test_normalize_value_walks_keys_as_well_as_values() -> None:
    value = {WORK + "/M.agda": [1, {"at": ROOT + "/x"}, ROOT], "n": 3}
    out = normalize_value(value, PMAP)
    assert out == {"<work>/M.agda": [1, {"at": "<repo>/x"}, "<repo>"], "n": 3}


def test_check_clean_names_every_forbidden_prefix() -> None:
    for prefix in FORBIDDEN:
        problem = check_clean(f"see {prefix}something/else here")
        assert problem.is_err
        assert prefix in str(problem.unwrap_err())
    assert check_clean("<work>/M.agda and <nix>/x").is_ok


def test_normalization_is_idempotent() -> None:
    # The build normalizes a transcript as it reads it and then normalizes the
    # whole assembled replay again as a backstop; the second pass must be a
    # no-op or the anchors would compound.
    once = normalize_text(WORK + "/M.agda " + ROOT, PMAP)
    assert normalize_text(once, PMAP) == once
