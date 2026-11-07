"""
Tests for the pin check in `scripts/run-server.sh` (issue #342).

File: scripts/python/tests/test_run_server_pin_check.py

Description
-----------
When a registration's --agda-bin is a fixed pin into the Nix store, the
launcher lists the packages the project's flake builds now and, when the pin
is none of them but one has the pin's package name, says so in one line on
stderr, beside the server and never before it.  These tests drive the real
launcher on its fast path (AGDA_MCP_BIN naming a stand-in server, so no
`nix develop`), with a stub `nix` first on PATH answering the two
evaluations, and NIX_STORE_DIR pointing at a temporary directory, so a "store
path" is a directory the test made.  No network, no store, no Agda.

The detached check holds the launcher's stderr until it finishes, so
`subprocess.run` returns only after its line, if any, has been written; the
tests need no sleeps.

The Nix expression itself (packages, tryEval, the listing format) is not
exercised here, since the stub answers in its place; it was checked against
formal-ledger-specifications' flake, and the PR that added it records that
run.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_run_server_pin_check.py`
"""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

import pytest

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
RUN_SERVER: Path = REPO_ROOT / "scripts" / "run-server.sh"

# The stub nix: `eval --impure ... builtins.currentSystem` answers a system,
# `eval ... #packages.<system> --apply ...` answers STUB_PACKAGES (or fails
# when STUB_EVAL_FAIL is set).  Every call is logged.
STUB_NIX: str = r"""#!/usr/bin/env bash
echo "nix $*" >> "$STUB_NIX_LOG"
case "$*" in
  "eval --impure --raw --expr builtins.currentSystem") printf 'x86_64-linux' ;;
  eval\ --raw\ --no-write-lock-file\ *'#packages.x86_64-linux --apply'*)
    sleep "${STUB_EVAL_SLEEP:-0}"
    if [ -n "${STUB_EVAL_FAIL:-}" ]; then echo "error: cannot evaluate" >&2; exit 1; fi
    printf '%s' "$STUB_PACKAGES" ;;
  *) echo "stub nix: unexpected $*" >&2; exit 2 ;;
esac
"""

# A stand-in server: reads the client's requests to the end and leaves.
STUB_SERVER: str = "#!/bin/sh\ncat >/dev/null\necho 'stand-in server ran' >&2\n"


@dataclass(frozen=True)
class World:
    """A store, a flake checkout, a stub nix and a stand-in server."""

    store: Path
    checkout: Path
    bin_dir: Path
    server: Path
    log: Path

    def store_path(self, name: str) -> Path:
        """A directory standing in for a store path NAME, with a bin/agda."""
        path = self.store / name
        (path / "bin").mkdir(parents=True, exist_ok=True)
        (path / "bin" / "agda").write_text("#!/bin/sh\n", encoding="utf-8")
        (path / "bin" / "agda").chmod(0o755)
        return path

    def pin(self, link: Path, name: str) -> Path:
        """A gc-root-style symlink LINK to store path NAME; returns LINK/bin/agda."""
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(self.store_path(name))
        return link / "bin" / "agda"

    def nix_calls(self) -> int:
        """How many times the stub ran (the --apply expression spans lines)."""
        text = self.log.read_text(encoding="utf-8") if self.log.exists() else ""
        return sum(1 for line in text.splitlines() if line.startswith("nix eval "))


@pytest.fixture
def world(tmp_path: Path) -> World:
    store = tmp_path / "store"
    store.mkdir()
    checkout = tmp_path / "fls"
    (checkout / ".git").mkdir(parents=True)
    (checkout / "flake.nix").write_text("{ }\n", encoding="utf-8")
    bin_dir = tmp_path / "stub-bin"
    bin_dir.mkdir()
    (bin_dir / "nix").write_text(STUB_NIX, encoding="utf-8")
    (bin_dir / "nix").chmod(0o755)
    server = tmp_path / "agda-mcp"
    server.write_text(STUB_SERVER, encoding="utf-8")
    server.chmod(0o755)
    return World(store=store, checkout=checkout, bin_dir=bin_dir, server=server,
                 log=tmp_path / "nix.log")


def packages(world: World, *entries: tuple[str, str]) -> str:
    """The listing the flake's packages evaluate to: "ATTR OUTPATH" lines."""
    return "\n".join(f"{attr} {world.store / name}" for attr, name in entries)


def launch(world: World, agda_bin: str, listing: str, cwd: Path | None = None,
           extra: Mapping[str, str] | None = None,
           args: Sequence[str] = (), server_cwd: str = "${PWD}") -> subprocess.CompletedProcess[str]:
    """Start the launcher on its fast path from the checkout (or CWD), the
    server in SERVER_CWD."""
    env = {**os.environ, "PATH": f"{world.bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}",
           "AGDA_MCP_BIN": str(world.server), "NIX_STORE_DIR": str(world.store),
           "STUB_NIX_LOG": str(world.log), "STUB_PACKAGES": listing, **(extra or {})}
    return subprocess.run([str(RUN_SERVER), "--cwd", server_cwd, "--agda-bin", agda_bin, *args],
                          cwd=cwd or world.checkout, env=env, input="", capture_output=True,
                          text=True, timeout=60)


def pin_lines(done: subprocess.CompletedProcess[str]) -> list[str]:
    """The pin check's lines on stderr, after checking the server ran cleanly."""
    assert done.returncode == 0, done.stderr
    assert done.stdout == ""  # nothing of the check reaches the JSON-RPC stream
    assert "stand-in server ran" in done.stderr
    return [line for line in done.stderr.splitlines() if line.startswith("agda-mcp: --agda-bin ")]


OLD: str = "0vx59n9g1597p7gzmflmmya161hr695h-agdaWithPackages-2.8.0"
NEW: str = "ws6a1ika52v3b26mxqvlx43h2l08i8ah-agdaWithPackages-2.8.0"


def test_a_pin_the_flake_no_longer_builds_gets_one_line(world: World, tmp_path: Path) -> None:
    pin = world.pin(tmp_path / "cache" / "agda-root", OLD)
    world.store_path(NEW)
    # A slow evaluation, so the order of the two lines shows that the server
    # started first: the check runs beside it, not before it.
    done = launch(world, str(pin), packages(world, ("default", "x-formal-ledger-0.1"),
                                            ("fls-agdaWithPackages", NEW)),
                  extra={"STUB_EVAL_SLEEP": "1"})
    lines = pin_lines(done)
    assert len(lines) == 1, done.stderr
    assert done.stderr.index("stand-in server ran") < done.stderr.index(lines[0])
    assert lines[0] == (
        f"agda-mcp: --agda-bin {pin} is {world.store / OLD}, but the flake at {world.checkout} "
        f"now builds fls-agdaWithPackages as {world.store / NEW}: the pin predates a change to that "
        f"flake (its lock, most often), so loads may fail inside a dependency; rebuild the pin, or "
        f"register {REPO_ROOT}/scripts/agda-for-flake.sh (docs/agda-mcp/registering-a-project.md).")


def test_a_new_version_of_the_same_package_still_counts(world: World, tmp_path: Path) -> None:
    pin = world.pin(tmp_path / "agda-root", OLD)
    newer = "zzzz1ika52v3b26mxqvlx43h2l08i8ah-agdaWithPackages-2.9.0"
    assert len(pin_lines(launch(world, str(pin), packages(world, ("agda", newer))))) == 1


def test_a_current_pin_is_silent(world: World, tmp_path: Path) -> None:
    pin = world.pin(tmp_path / "agda-root", OLD)
    assert pin_lines(launch(world, str(pin), packages(world, ("fls-agdaWithPackages", OLD)))) == []
    assert world.nix_calls() == 2


@pytest.mark.parametrize("other", [
    "x-agda-2.8.0",                    # another package name
    "x-agdaWithPackagesExtra-2.8.0",   # a longer name is not the same name
    "x-fls-agdaWithPackages-2.8.0",
])
def test_a_pin_of_a_name_the_flake_does_not_build_is_silent(world: World, tmp_path: Path, other: str) -> None:
    pin = world.pin(tmp_path / "agda-root", OLD)
    assert pin_lines(launch(world, str(pin), packages(world, ("p", other)))) == []


def test_a_failed_evaluation_is_silent(world: World, tmp_path: Path) -> None:
    pin = world.pin(tmp_path / "agda-root", OLD)
    assert pin_lines(launch(world, str(pin), "", extra={"STUB_EVAL_FAIL": "1"})) == []
    assert world.nix_calls() == 2


def test_a_per_checkout_binary_is_never_checked(world: World) -> None:
    # A dev shell's .agda/bin/agda links into the store too, but follows the checkout.
    agda = world.pin(world.checkout / ".agda-root", OLD)
    assert pin_lines(launch(world, str(agda), packages(world, ("p", NEW)))) == []
    assert world.nix_calls() == 0


def test_a_binary_outside_the_store_is_never_checked(world: World) -> None:
    assert pin_lines(launch(world, str(REPO_ROOT / "scripts" / "agda-for-flake.sh"), "")) == []
    assert pin_lines(launch(world, "agda", "")) == []
    assert world.nix_calls() == 0


def test_a_relative_pin_is_resolved_where_the_server_runs_it(world: World, tmp_path: Path) -> None:
    # The server enters --cwd and then runs --agda-bin, so a relative pin is
    # the one beside the checkout, not beside the directory the client
    # started in.  Here the checkout's is stale and the launch directory's
    # (the same relative path) is current: one line, naming the stale one.
    world.pin(tmp_path / "cache" / "agda-root", OLD)
    elsewhere = tmp_path / "elsewhere"
    world.pin(tmp_path / "cache-elsewhere" / "agda-root", NEW)
    (elsewhere / "sub").mkdir(parents=True)
    (tmp_path / "cache-elsewhere").rename(elsewhere / "cache")
    relative = "../cache/agda-root/bin/agda"
    listing = packages(world, ("fls-agdaWithPackages", NEW))
    lines = pin_lines(launch(world, relative, listing, cwd=elsewhere / "sub", server_cwd=str(world.checkout)))
    assert len(lines) == 1 and f"is {world.store / OLD}, but" in lines[0]
    assert lines[0].startswith(f"agda-mcp: --agda-bin {tmp_path / 'cache' / 'agda-root' / 'bin' / 'agda'} ")
    # The converse: the checkout's is current, the launch directory's stale.
    (tmp_path / "cache" / "agda-root").unlink()
    world.pin(tmp_path / "cache" / "agda-root", NEW)
    (elsewhere / "cache" / "agda-root").unlink()
    world.pin(elsewhere / "cache" / "agda-root", OLD)
    assert pin_lines(launch(world, relative, listing, cwd=elsewhere / "sub", server_cwd=str(world.checkout))) == []


def test_a_relative_path_into_the_checkout_is_never_checked(world: World) -> None:
    world.pin(world.checkout / ".agda-root", OLD)
    assert pin_lines(launch(world, ".agda-root/bin/agda", packages(world, ("p", NEW)))) == []
    assert world.nix_calls() == 0


def test_no_flake_within_the_repository_is_silent(world: World, tmp_path: Path) -> None:
    pin = world.pin(tmp_path / "agda-root", OLD)
    other = tmp_path / "plain"
    (other / ".git").mkdir(parents=True)
    assert pin_lines(launch(world, str(pin), packages(world, ("p", NEW)), cwd=other)) == []
    assert world.nix_calls() == 0


def test_a_subdirectory_of_the_checkout_finds_its_flake(world: World, tmp_path: Path) -> None:
    pin = world.pin(tmp_path / "agda-root", OLD)
    (world.checkout / "src").mkdir()
    done = launch(world, str(pin), packages(world, ("fls-agdaWithPackages", NEW)), cwd=world.checkout / "src")
    assert len(pin_lines(done)) == 1
