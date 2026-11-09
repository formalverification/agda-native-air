"""
Tests for `scripts/agda-for-flake.sh`, the launcher keyed by the lock.

File: scripts/python/tests/test_agda_for_flake.py

Description
-----------
The launcher's promise (issue #342) is that every checkout gets the Agda its
own flake names, built once per change of what decides it, and never another.
These tests hold it to that through the real script, in real git checkouts
under a temporary directory, with a stub `nix` first on PATH, so they need no
network and no Nix store and take a few seconds.

The stub `nix build REF -o ROOT` makes a fresh directory standing in for a
store path, with a `bin/agda` that prints which build it came from, its
arguments, and its environment, and then echoes its stdin; it links ROOT to
that directory and logs every call.  So a test reads, from the launcher's
stdout alone, which build answered, and from the log how many builds ran.  The
stub also reads its stdin to the end and prints a line on stdout, which is
how the tests see that the launcher hands nix /dev/null and keeps nix's
output off Agda's stdout.

Cases: a miss builds and a hit does not; Agda's arguments, stdin and exit
status pass through; the key moves with flake.lock, a Nix file, any other
tracked file (the backend's Haskell sources), and an uncommitted edit, and
stays put for Agda sources and for files Nix does not see; sibling worktrees
share a build on one lock and get their own on another; a subdirectory finds
the checkout's flake; two first calls at once build once; and every refusal
(no attribute, no flake, no lock, a failed build, an output without Agda) is
one line on stderr, exit 69, and no Agda run.  And `--print-key` (issue #347)
prints the key a call would use, which is the name of the root that call
runs, and builds, writes, and runs nothing; it follows the same files the
key does, takes `--flake-attr` before or after it, and refuses as a call
would.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_agda_for_flake.py`
+  Needs git and bash on PATH, nothing else.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Optional, Sequence

import pytest

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
LAUNCHER: Path = REPO_ROOT / "scripts" / "agda-for-flake.sh"
ATTR: str = "fls-agdaWithPackages"
UNAVAILABLE: int = 69  # the launcher's exit status when it runs no Agda

pytestmark = pytest.mark.skipif(shutil.which("git") is None, reason="git is not on PATH")

# The stub nix.  `build` takes the launcher's exact argument shape
# (build --no-write-lock-file REF -o ROOT); `eval` answers an output path for
# a flake outside git.  STUB_* variables steer it per test.
STUB_NIX: str = r"""#!/usr/bin/env bash
set -eu
echo "nix $* LD_LIBRARY_PATH=${LD_LIBRARY_PATH-unset}" >> "$STUB_NIX_LOG"
case "$1" in
  build)
    ref="$3"; root="$5"
    stdin="$(cat)"                      # /dev/null gives nothing
    echo "stub nix: stdout noise"       # must not reach Agda's stdout
    sleep "${STUB_NIX_SLEEP:-0}"
    eval "${STUB_NIX_DURING_BUILD:-}"   # a checkout that changes mid-build
    if [ -n "${STUB_NIX_FAIL:-}" ]; then echo "error: stub nix cannot fetch" >&2; exit 1; fi
    n="$(grep -c '^nix build' "$STUB_NIX_LOG")"
    out="${STUB_STORE}/build-${n}"
    mkdir -p "${out}/bin"
    if [ -z "${STUB_NIX_NO_AGDA:-}" ]; then
      cat > "${out}/bin/agda" <<EOF
#!/usr/bin/env bash
echo "agda build-${n} of ${ref} stdin-at-build=[${stdin}] args=[\$*] LD_LIBRARY_PATH=\${LD_LIBRARY_PATH-unset}"
cat
exit "\${STUB_AGDA_EXIT:-0}"
EOF
      chmod +x "${out}/bin/agda"
    fi
    ln -sfn "$out" "$root"
    ;;
  eval)
    echo -n "${STUB_EVAL_OUT}"
    ;;
  *) echo "stub nix: unexpected $*" >&2; exit 2 ;;
esac
"""


@dataclass(frozen=True)
class Sandbox:
    """One test's world: a stub nix, its log and store, and a cache."""

    bin_dir: Path
    log: Path
    store: Path
    cache: Path

    def env(self, extra: Mapping[str, str]) -> dict[str, str]:
        """The launcher's environment: the stub first on PATH, the cache under XDG."""
        base = {k: v for k, v in os.environ.items() if k not in ("AGDA_FLAKE_ATTR", "XDG_CACHE_HOME")}
        return {**base, "PATH": f"{self.bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}",
                "STUB_NIX_LOG": str(self.log), "STUB_STORE": str(self.store),
                "XDG_CACHE_HOME": str(self.cache), "AGDA_FLAKE_ATTR": ATTR, **extra}

    def builds(self) -> int:
        """How many `nix build` calls the stub has seen."""
        text = self.log.read_text(encoding="utf-8") if self.log.exists() else ""
        return sum(1 for line in text.splitlines() if line.startswith("nix build"))


@pytest.fixture
def sandbox(tmp_path: Path) -> Sandbox:
    bin_dir = tmp_path / "stub-bin"
    bin_dir.mkdir()
    (bin_dir / "nix").write_text(STUB_NIX, encoding="utf-8")
    (bin_dir / "nix").chmod(0o755)
    (tmp_path / "store").mkdir()
    return Sandbox(bin_dir=bin_dir, log=tmp_path / "nix.log", store=tmp_path / "store",
                   cache=tmp_path / "cache")


def git(cwd: Path, *args: str) -> str:
    """Run git in CWD with a fixed identity; return its stdout."""
    done = subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", str(cwd), *args],
                          capture_output=True, text=True, check=True)
    return done.stdout


# The files of a small flake checkout, shaped like formal-ledger-specifications:
# a lock, Nix files, the Haskell sources of a custom Agda, Agda sources, prose.
CHECKOUT_FILES: Mapping[str, str] = {
    "flake.nix": "{ outputs = _: { }; }\n",
    "flake.lock": '{"nodes": {"root": {}}, "version": 7}\n',
    "build-tools/nix/fls-agda.nix": "{ src = ../agda; }\n",
    "build-tools/agda/Main.hs": "main = pure ()\n",
    "formal-ledger.agda-lib": "name: formal-ledger\ninclude: src\n",
    "src/Ledger.agda": "module Ledger where\n",
    "src/Ledger/Prelude.lagda.md": "# Prelude\n",
    "README.md": "readme\n",
}


def make_checkout(root: Path) -> Path:
    """A committed git checkout holding CHECKOUT_FILES at ROOT."""
    for name, text in CHECKOUT_FILES.items():
        (root / name).parent.mkdir(parents=True, exist_ok=True)
        (root / name).write_text(text, encoding="utf-8")
    git(root, "init", "-q", "-b", "main")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "init")
    return root


@pytest.fixture
def checkout(tmp_path: Path) -> Path:
    return make_checkout(tmp_path / "fls")


def launch(sandbox: Sandbox, cwd: Path, args: Sequence[str] = ("--version",),
           extra: Optional[Mapping[str, str]] = None, stdin: str = "") -> subprocess.CompletedProcess[str]:
    """Run the launcher from CWD with ARGS, as agda-mcp would run Agda."""
    return subprocess.run([str(LAUNCHER), *args], cwd=cwd, env=sandbox.env(extra or {}),
                          input=stdin, capture_output=True, text=True, timeout=60)


def build_of(done: subprocess.CompletedProcess[str]) -> str:
    """The `build-N` that answered, read from the stub Agda's first line."""
    assert done.returncode == 0, done.stderr
    first = done.stdout.splitlines()[0]
    assert first.startswith("agda build-"), done.stdout
    return first.split()[1]


def refused(done: subprocess.CompletedProcess[str], wording: str) -> None:
    """A refusal: exit 69, no Agda output, and the reason last on stderr."""
    assert done.returncode == UNAVAILABLE, (done.returncode, done.stderr)
    assert done.stdout == ""
    last = done.stderr.strip().splitlines()[-1]
    assert last.startswith("agda-for-flake: ") and wording in last, done.stderr


# ---- A miss builds, a hit does not, and Agda's interface passes through ----

def test_a_miss_builds_once_and_a_hit_runs_the_same_agda(sandbox: Sandbox, checkout: Path) -> None:
    first = launch(sandbox, checkout)
    assert build_of(first) == "build-1" and sandbox.builds() == 1
    assert f"of {checkout}#{ATTR} " in first.stdout
    assert "building fls-agdaWithPackages" in first.stderr
    second = launch(sandbox, checkout)
    assert build_of(second) == "build-1" and sandbox.builds() == 1
    assert second.stderr == ""


def test_arguments_stdin_and_exit_status_reach_agda_and_nix_reads_none(sandbox: Sandbox, checkout: Path) -> None:
    done = launch(sandbox, checkout, ["--interaction-json", "-i", "a b"],
                  extra={"STUB_AGDA_EXIT": "42"}, stdin='IOTCM "x" None Indirect (Cmd_load "x" [])\n')
    assert done.returncode == 42
    lines = done.stdout.splitlines()
    # nix's own stdout went to stderr, and nix read /dev/null, not the request.
    assert lines[0].startswith("agda build-1 ") and "stdin-at-build=[]" in lines[0]
    assert "args=[--interaction-json -i a b]" in lines[0]
    assert lines[1:] == ['IOTCM "x" None Indirect (Cmd_load "x" [])']
    assert "stub nix: stdout noise" in done.stderr


def test_the_flake_attr_argument_is_consumed(sandbox: Sandbox, checkout: Path) -> None:
    for args in (["--flake-attr", "other", "M.agda"], ["--flake-attr=other", "M.agda"]):
        done = launch(sandbox, checkout, args, extra={"AGDA_FLAKE_ATTR": ""})
        assert f"of {checkout}#other " in done.stdout and "args=[M.agda]" in done.stdout
    assert sandbox.builds() == 1  # one attribute, one key
    assert (sandbox.cache / "agda-mcp" / "other").is_dir()


def test_nix_runs_without_the_dynamic_linker_path_and_agda_keeps_it(sandbox: Sandbox, checkout: Path) -> None:
    done = launch(sandbox, checkout, extra={"LD_LIBRARY_PATH": "/devshell/lib"})
    assert "LD_LIBRARY_PATH=/devshell/lib" in done.stdout.splitlines()[0]
    assert "LD_LIBRARY_PATH=unset" in sandbox.log.read_text(encoding="utf-8")


def test_the_root_is_a_cache_entry_with_a_note(sandbox: Sandbox, checkout: Path) -> None:
    launch(sandbox, checkout)
    entries = sorted(p.name for p in (sandbox.cache / "agda-mcp" / ATTR).iterdir())
    assert len(entries) == 4
    key = entries[0]
    assert entries == [key, f"{key}.lock", f"{key}.out", f"{key}.txt"]
    # <key>.out is Nix's gc root; <key>, a link to it, is what a call runs.
    assert os.readlink(sandbox.cache / "agda-mcp" / ATTR / key) == f"{key}.out"
    assert (sandbox.cache / "agda-mcp" / ATTR / f"{key}.out").is_symlink()
    note = (sandbox.cache / "agda-mcp" / ATTR / f"{key}.txt").read_text(encoding="utf-8")
    assert f"checkout {checkout}\n" in note and f"attribute {ATTR}\n" in note


# ---- What moves the key, and what does not ---------------------------------

@pytest.mark.parametrize("name", ["flake.lock", "build-tools/nix/fls-agda.nix",
                                  "build-tools/agda/Main.hs", "README.md"])
def test_a_committed_change_to_a_file_nix_reads_rebuilds(sandbox: Sandbox, checkout: Path, name: str) -> None:
    assert build_of(launch(sandbox, checkout)) == "build-1"
    with (checkout / name).open("a", encoding="utf-8") as handle:
        handle.write("changed\n")
    git(checkout, "commit", "-q", "-am", f"change {name}")
    assert build_of(launch(sandbox, checkout)) == "build-2"


@pytest.mark.parametrize("name", ["src/Ledger.agda", "src/Ledger/Prelude.lagda.md"])
def test_an_agda_source_never_moves_the_key(sandbox: Sandbox, checkout: Path, name: str) -> None:
    assert build_of(launch(sandbox, checkout)) == "build-1"
    (checkout / name).write_text("edited\n", encoding="utf-8")
    assert build_of(launch(sandbox, checkout)) == "build-1"  # dirty
    git(checkout, "commit", "-q", "-am", "edit a proof")
    assert build_of(launch(sandbox, checkout)) == "build-1"  # committed
    (checkout / "src" / "New.agda").write_text("module New where\n", encoding="utf-8")
    git(checkout, "add", "src/New.agda")
    assert build_of(launch(sandbox, checkout)) == "build-1"  # a new one, staged
    assert sandbox.builds() == 1


def test_an_uncommitted_edit_counts_and_its_revert_finds_the_old_root(sandbox: Sandbox, checkout: Path) -> None:
    assert build_of(launch(sandbox, checkout)) == "build-1"
    lock = checkout / "flake.lock"
    original = lock.read_text(encoding="utf-8")
    lock.write_text('{"nodes": {}, "version": 7}\n', encoding="utf-8")  # unstaged
    assert build_of(launch(sandbox, checkout)) == "build-2"
    git(checkout, "add", "flake.lock")  # staged: the same contents, the same key
    assert build_of(launch(sandbox, checkout)) == "build-2"
    git(checkout, "commit", "-q", "-m", "the new lock")  # committed: the same again
    assert build_of(launch(sandbox, checkout)) == "build-2"
    lock.write_text(original, encoding="utf-8")  # back, uncommitted
    assert build_of(launch(sandbox, checkout)) == "build-1"
    assert sandbox.builds() == 2


def test_a_symlinks_target_and_a_files_executable_bit_count(sandbox: Sandbox, checkout: Path) -> None:
    # Nix copies a symlink as a symlink and keeps a file's executable bit,
    # so either can change a build; neither may share another tree's key.
    (checkout / "build-tools" / "old").mkdir()
    (checkout / "build-tools" / "new").mkdir()
    (checkout / "build-tools" / "old" / "a.hs").write_text("old\n", encoding="utf-8")
    (checkout / "build-tools" / "new" / "a.hs").write_text("new\n", encoding="utf-8")
    (checkout / "build-tools" / "src").symlink_to("old")
    (checkout / "build.sh").write_text("echo build\n", encoding="utf-8")
    git(checkout, "add", "-A")
    git(checkout, "commit", "-q", "-m", "a symlink and a script")
    link = checkout / "build-tools" / "src"
    assert build_of(launch(sandbox, checkout)) == "build-1"
    link.unlink(); link.symlink_to("new")  # another directory
    assert build_of(launch(sandbox, checkout)) == "build-2"
    link.unlink(); link.symlink_to("gone")  # dangling
    assert build_of(launch(sandbox, checkout)) == "build-3"
    link.unlink(); link.symlink_to("old")  # back
    assert build_of(launch(sandbox, checkout)) == "build-1"
    (checkout / "build.sh").chmod(0o755)  # unstaged mode change
    assert build_of(launch(sandbox, checkout)) == "build-4"
    git(checkout, "add", "build.sh")  # staged, then committed: the same tree
    assert build_of(launch(sandbox, checkout)) == "build-4"
    git(checkout, "commit", "-q", "-m", "executable")
    assert build_of(launch(sandbox, checkout)) == "build-4"
    assert sandbox.builds() == 4


def test_an_untracked_file_is_invisible_to_nix_and_to_the_key(sandbox: Sandbox, checkout: Path) -> None:
    assert build_of(launch(sandbox, checkout)) == "build-1"
    (checkout / "scratch.nix").write_text("{ }\n", encoding="utf-8")
    (checkout / "_build").mkdir()
    (checkout / "_build" / "x.agdai").write_text("binary\n", encoding="utf-8")
    assert build_of(launch(sandbox, checkout)) == "build-1"


# ---- Worktrees and subdirectories ------------------------------------------

def test_sibling_worktrees_share_a_lock_and_split_on_another(sandbox: Sandbox, checkout: Path, tmp_path: Path) -> None:
    same = tmp_path / "wt-same"
    other = tmp_path / "wt-other"
    git(checkout, "worktree", "add", "-q", "-b", "same", str(same))
    git(checkout, "worktree", "add", "-q", "-b", "other", str(other))
    (other / "flake.lock").write_text('{"nodes": {"older": {}}, "version": 7}\n', encoding="utf-8")
    git(other, "commit", "-q", "-am", "an older lock")
    assert build_of(launch(sandbox, checkout)) == "build-1"
    assert build_of(launch(sandbox, same)) == "build-1"
    built_other = launch(sandbox, other)
    assert build_of(built_other) == "build-2" and f"of {other}#{ATTR} " in built_other.stdout
    assert build_of(launch(sandbox, checkout)) == "build-1"
    assert sandbox.builds() == 2


def test_a_subdirectory_finds_the_checkouts_flake(sandbox: Sandbox, checkout: Path) -> None:
    done = launch(sandbox, checkout / "src" / "Ledger")
    assert f"of {checkout}#{ATTR} " in done.stdout


def test_a_flake_in_a_subdirectory_of_the_repository(sandbox: Sandbox, tmp_path: Path) -> None:
    repo = tmp_path / "mono"
    make_checkout(repo / "spec")
    shutil.rmtree(repo / "spec" / ".git")
    git(repo, "init", "-q", "-b", "main")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "init")
    done = launch(sandbox, repo / "spec" / "src")
    assert f"of {repo / 'spec'}#{ATTR} " in done.stdout


# ---- Concurrency -----------------------------------------------------------

@pytest.mark.skipif(shutil.which("flock") is None, reason="flock(1) is not on PATH")
def test_two_first_calls_at_once_build_once(sandbox: Sandbox, checkout: Path) -> None:
    env = sandbox.env({"STUB_NIX_SLEEP": "1"})
    procs = [subprocess.Popen([str(LAUNCHER), "--version"], cwd=checkout, env=env, text=True,
                              stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
             for _ in range(3)]
    results = [proc.communicate(timeout=60) for proc in procs]
    assert all(proc.returncode == 0 for proc in procs), results
    assert all(out.startswith("agda build-1 ") for out, _ in results), results
    assert sandbox.builds() == 1
    assert any("waiting for another build" in err for _, err in results)


# ---- A checkout that changes while Nix builds it ---------------------------

def test_a_build_of_a_tree_that_changed_meanwhile_is_not_kept_under_the_old_key(
        sandbox: Sandbox, checkout: Path) -> None:
    lock = checkout / "flake.lock"
    original = lock.read_text(encoding="utf-8")
    marker = checkout.parent / "changed-once"
    # The first build sees the lock change under it; later builds see none.
    during = f'[ -e "{marker}" ] || {{ touch "{marker}"; echo moved >> "{lock}"; }}'
    done = launch(sandbox, checkout, extra={"STUB_NIX_DURING_BUILD": during})
    assert build_of(done) == "build-2" and sandbox.builds() == 2
    assert "changed during the build; discarded it, building again" in done.stderr
    # The original lock never got build-1, the build of the moved lock.
    lock.write_text(original, encoding="utf-8")
    assert build_of(launch(sandbox, checkout)) == "build-3"
    with lock.open("a", encoding="utf-8") as handle:
        handle.write("moved\n")
    assert build_of(launch(sandbox, checkout)) == "build-2"
    assert sandbox.builds() == 3


def test_a_tree_that_changes_during_every_build_is_refused(sandbox: Sandbox, checkout: Path) -> None:
    during = f'echo moved >> "{checkout / "flake.lock"}"'
    done = launch(sandbox, checkout, extra={"STUB_NIX_DURING_BUILD": during})
    refused(done, "changed during each of 3 builds; no Agda was run")
    assert sandbox.builds() == 3
    assert not [p for p in (sandbox.cache / "agda-mcp" / ATTR).iterdir()
                if p.suffix not in (".lock",)]


# ---- Refusals: one line, exit 69, and no Agda ------------------------------

def test_no_attribute_is_refused(sandbox: Sandbox, checkout: Path) -> None:
    refused(launch(sandbox, checkout, extra={"AGDA_FLAKE_ATTR": ""}), "no flake attribute")
    refused(launch(sandbox, checkout, ["--flake-attr"], extra={"AGDA_FLAKE_ATTR": ""}),
            "--flake-attr needs a value")
    assert sandbox.builds() == 0


def test_no_flake_above_the_working_directory_is_refused(sandbox: Sandbox, tmp_path: Path) -> None:
    bare = tmp_path / "bare"
    (bare / "sub").mkdir(parents=True)
    git(bare, "init", "-q")
    refused(launch(sandbox, bare / "sub"), f"no flake.nix at or above {bare / 'sub'} (searched up to {bare})")


def test_no_lock_is_refused_and_nothing_is_written(sandbox: Sandbox, checkout: Path) -> None:
    git(checkout, "rm", "-q", "flake.lock")
    refused(launch(sandbox, checkout), f"no flake.lock in {checkout}")
    assert not (checkout / "flake.lock").exists() and sandbox.builds() == 0


def test_a_failed_build_is_refused_and_the_next_call_retries(sandbox: Sandbox, checkout: Path) -> None:
    done = launch(sandbox, checkout, extra={"STUB_NIX_FAIL": "1"})
    refused(done, "failed (exit 1; offline, or a broken flake?); no Agda was run")
    assert "error: stub nix cannot fetch" in done.stderr  # nix's own reason is kept
    assert not any((sandbox.cache / "agda-mcp" / ATTR).glob("*.txt"))
    assert build_of(launch(sandbox, checkout)) == "build-2"


def test_an_output_without_agda_is_refused(sandbox: Sandbox, checkout: Path) -> None:
    refused(launch(sandbox, checkout, extra={"STUB_NIX_NO_AGDA": "1"}), "which has no executable bin/agda")


def test_no_nix_is_refused(sandbox: Sandbox, checkout: Path) -> None:
    # PATH holds bash, env and git (through symlinks), and no nix.
    tools = sandbox.bin_dir.parent / "no-nix"
    tools.mkdir()
    for tool in ("bash", "env", "git", "dirname"):
        found = shutil.which(tool)
        assert found is not None
        (tools / tool).symlink_to(found)
    done = subprocess.run([str(LAUNCHER), "--version"], cwd=checkout, capture_output=True, text=True,
                          env={**sandbox.env({}), "PATH": str(tools)}, timeout=60)
    refused(done, "nix is not on PATH")


# ---- A flake outside git: keyed by its output path -------------------------

def test_a_flake_outside_git_is_keyed_by_its_output_path(sandbox: Sandbox, tmp_path: Path) -> None:
    plain = tmp_path / "plain"
    plain.mkdir()
    (plain / "flake.nix").write_text("{ }\n", encoding="utf-8")
    (plain / "flake.lock").write_text("{ }\n", encoding="utf-8")
    first_out = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-agdaWithPackages-2.8.0"
    second_out = "/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-agdaWithPackages-2.8.0"
    assert build_of(launch(sandbox, plain, extra={"STUB_EVAL_OUT": first_out})) == "build-1"
    assert build_of(launch(sandbox, plain, extra={"STUB_EVAL_OUT": first_out})) == "build-1"
    assert build_of(launch(sandbox, plain, extra={"STUB_EVAL_OUT": second_out})) == "build-2"
    assert (sandbox.cache / "agda-mcp" / ATTR / ("out-" + "a" * 32)).is_symlink()


# ---- --print-key: the key alone, for agda-mcp's identity command (#347) ----

def printed_key(done: subprocess.CompletedProcess[str]) -> str:
    """The key `--print-key` printed: exit 0, one line, nothing on stderr."""
    assert done.returncode == 0, done.stderr
    assert done.stderr == ""
    lines = done.stdout.splitlines()
    assert len(lines) == 1, done.stdout
    return lines[0]


def test_print_key_names_the_root_a_call_runs_and_builds_nothing(sandbox: Sandbox, checkout: Path) -> None:
    key = printed_key(launch(sandbox, checkout, ["--print-key"]))
    assert len(key) == 32 and sandbox.builds() == 0
    assert not (sandbox.cache / "agda-mcp").exists()  # nothing written
    assert build_of(launch(sandbox, checkout)) == "build-1"
    entries = sorted(p.name for p in (sandbox.cache / "agda-mcp" / ATTR).iterdir())
    assert entries[0] == key  # the root the call built and ran is named by it
    assert printed_key(launch(sandbox, checkout, ["--print-key"])) == key
    assert sandbox.builds() == 1


def test_print_key_follows_the_files_the_key_does(sandbox: Sandbox, checkout: Path) -> None:
    before = printed_key(launch(sandbox, checkout, ["--print-key"]))
    (checkout / "src" / "Ledger.agda").write_text("edited\n", encoding="utf-8")
    assert printed_key(launch(sandbox, checkout, ["--print-key"])) == before  # an Agda source
    with (checkout / "flake.lock").open("a", encoding="utf-8") as handle:
        handle.write("moved\n")
    moved = printed_key(launch(sandbox, checkout, ["--print-key"]))
    assert moved != before  # the lock, uncommitted
    git(checkout, "checkout", "--", "flake.lock")
    assert printed_key(launch(sandbox, checkout, ["--print-key"])) == before
    assert sandbox.builds() == 0


def test_print_key_takes_the_flake_attr_before_or_after_it(sandbox: Sandbox, checkout: Path) -> None:
    default = printed_key(launch(sandbox, checkout, ["--print-key"]))
    orders = (["--print-key", "--flake-attr", "other"], ["--flake-attr", "other", "--print-key"],
              ["--flake-attr=other", "--print-key"])
    keys = {printed_key(launch(sandbox, checkout, args, extra={"AGDA_FLAKE_ATTR": ""})) for args in orders}
    assert len(keys) == 1 and default not in keys  # the attribute is part of the key
    assert sandbox.builds() == 0


def test_print_key_refuses_as_a_call_would(sandbox: Sandbox, checkout: Path) -> None:
    refused(launch(sandbox, checkout, ["--print-key"], extra={"AGDA_FLAKE_ATTR": ""}), "no flake attribute")
    git(checkout, "rm", "-q", "flake.lock")
    refused(launch(sandbox, checkout, ["--print-key"]), f"no flake.lock in {checkout}")
    assert sandbox.builds() == 0


def test_print_key_outside_git_is_the_output_path_key(sandbox: Sandbox, tmp_path: Path) -> None:
    plain = tmp_path / "plain"
    plain.mkdir()
    (plain / "flake.nix").write_text("{ }\n", encoding="utf-8")
    (plain / "flake.lock").write_text("{ }\n", encoding="utf-8")
    out = "/nix/store/cccccccccccccccccccccccccccccccc-agdaWithPackages-2.8.0"
    key = printed_key(launch(sandbox, plain, ["--print-key"], extra={"STUB_EVAL_OUT": out}))
    assert key == "out-" + "c" * 32 and sandbox.builds() == 0
