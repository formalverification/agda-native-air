#!/usr/bin/env bash
# agda-for-flake.sh
#
# File: scripts/agda-for-flake.sh
#
# Description:
#   Run the Agda that the project's own flake exports, built once per change
#   of what decides it, for the checkout this process runs in (issue #342).
#
#   A registration names this script as agda-mcp's --agda-bin (and as the
#   program of its --check-command), and names the flake attribute in its
#   environment as AGDA_FLAKE_ATTR (or, on a command line, as a leading
#   `--flake-attr NAME`).  Every argument after that goes to Agda unchanged.
#   The script finds the nearest flake.nix at or above its working directory,
#   computes a key from the files that decide the attribute's output, and
#   execs <cache>/agda-mcp/<attr>/<key>/bin/agda, building that root first
#   with `nix build <checkout>#<attr> -o <root>` when it does not exist.  So
#   each checkout gets the Agda its own lock names, a sibling worktree on
#   another lock gets its own, and a lock that moves costs one build, with
#   nothing to refresh by hand.
#
#   It replaces the hand-built pin (`nix build <checkout>#<attr> -o <link>`,
#   named directly as --agda-bin), which matches one lock and goes stale in
#   silence when the lock moves: in the field, every load then failed with
#   NotInScope inside a dependency for two weeks, which read as broken code.
#
# Where it runs:
#   agda-mcp runs Agda, in both of its lanes, in the server's working
#   directory (the --cwd of the registration, which is the checkout the
#   session started in), and the --check-command gate in the project root.
#   The flake is found by walking up from there to the nearest flake.nix,
#   stopping at a repository boundary (a directory holding .git), so a
#   session started in a subdirectory of the checkout finds the same flake.
#
# The key (what decides the attribute's output):
#   For a flake in a git checkout, Nix sees exactly the tracked files, with
#   the working tree's contents (a dirty tree included).  The key is a hash
#   of every tracked file except Agda sources (*.agda, *.lagda, *.lagda.*),
#   taken from the index (`git ls-files --stage`) and, for files the working
#   tree changes, from their contents (`git hash-object`), plus the
#   attribute's name and the flake's directory within the repository.  It
#   costs about 15 ms per call on formal-ledger-specifications.
#   +  Why not flake.lock alone: flake.nix and the files it imports decide the
#      output as much as the lock does.
#   +  Why not flake.lock and the *.nix files: a derivation reads other files.
#      formal-ledger-specifications builds its Agda from Haskell sources in
#      build-tools/agda (`src = ../agda`), so a branch that edits them gets a
#      different Agda under the same lock and the same Nix files.
#   +  Why Agda sources are left out: an environment for checking a project
#      cannot contain the project's own library (Agda would then find it
#      twice, in the store and in the checkout), so its output does not
#      depend on them, and leaving them out is what keeps the key steady
#      while a session edits proofs.  The attribute must be such an
#      environment (an `agda.withPackages` of the dependencies); a package
#      built from the project's own sources is the wrong attribute.
#   +  An edit to any other tracked file (a README, a script) changes the
#      key.  The next call then runs `nix build` again, which evaluates the
#      flake (about a second), finds the output already in the store, and
#      links a new root to it: correct, and cheap.
#   A flake outside any git checkout is keyed by its output path instead,
#   from `nix eval` on every call (about a second each), since Nix then
#   reads every file in the directory and no cheaper key is exact.
#
# The cache:
#   ${XDG_CACHE_HOME:-$HOME/.cache}/agda-mcp/<attr>/<key> is the gc root (a
#   symlink into the store that keeps the build alive), <key>.lock the lock
#   file, and <key>.txt a note of the checkout and output that made it.  The
#   key holds no checkout path, so sibling worktrees on the same lock share
#   one root.  Nothing is ever removed: delete the roots you no longer want
#   (`ls -lt` shows the newest first), then let `nix store gc` reclaim them.
#
# Failure, and what it never does:
#   A miss with no network, a failed build, a checkout with no flake.nix or
#   no flake.lock, or an attribute with no bin/agda: one line on stderr
#   saying which, after any output of nix's own, and exit status 69 (what
#   sysexits.h calls EX_UNAVAILABLE; Agda itself uses 1, 42, 71 and 154).
#   It never runs another Agda in place of the one asked for.  It never
#   writes into the checkout: `nix build --no-write-lock-file` leaves a
#   flake.lock that lags flake.nix as it is, and refuses nothing for it.
#
# Concurrency:
#   Two first calls at once (two sessions, or the server's two lanes) take
#   an exclusive flock(1) on <key>.lock; the second waits, says so, and then
#   finds the root the first one built.  Without flock (stock macOS) they
#   both run `nix build`, which is still correct: Nix locks each store path
#   while building it, and `-o` replaces the root symlink atomically.  A
#   build interrupted by the server's timeout (it kills the whole process
#   group) leaves no root, and the next call starts it again; every store
#   path finished before the interruption stays built.
#
# Streams:
#   agda-mcp reads Agda's standard output (JSON on the interaction lane), so
#   this script writes nothing there: nix's output goes to stderr, and nix
#   reads /dev/null, never the requests waiting on the lane's stdin.
#   LD_LIBRARY_PATH and DYLD_LIBRARY_PATH are cleared for nix only (a
#   devShell's libssl breaks the profile nix, issue #153); Agda gets the
#   environment it was called with.
#
# Usage:
#   AGDA_FLAKE_ATTR=fls-agdaWithPackages scripts/agda-for-flake.sh --version
#   scripts/agda-for-flake.sh --flake-attr fls-agdaWithPackages src/Ledger.lagda.md
#
#   Run the first line once in a checkout after setting up a registration:
#   it builds the root, if needed, outside any tool call's timeout, and
#   prints the Agda version that sessions there will get.

set -euo pipefail

say() { echo "agda-for-flake: $*" >&2; }
# Exit 69 (EX_UNAVAILABLE): the Agda asked for cannot be run.
fail() { say "$*"; exit 69; }

# ---- The attribute: a leading --flake-attr, else AGDA_FLAKE_ATTR ----------
attr="${AGDA_FLAKE_ATTR:-}"
case "${1:-}" in
  --flake-attr)   [ "$#" -ge 2 ] || fail "--flake-attr needs a value"
                  attr="$2"; shift 2 ;;
  --flake-attr=*) attr="${1#--flake-attr=}"; shift ;;
esac
[ -n "$attr" ] ||
  fail "no flake attribute: set AGDA_FLAKE_ATTR in the registration's env, or pass --flake-attr NAME first"

# ---- The flake: nearest flake.nix at or above the working directory --------
start="$(pwd -P)"
flake_dir="$start"
while [ ! -f "${flake_dir}/flake.nix" ]; do
  if [ -e "${flake_dir}/.git" ] || [ "$flake_dir" = / ]; then
    fail "no flake.nix at or above ${start} (searched up to ${flake_dir})"
  fi
  flake_dir="$(dirname "$flake_dir")"
done
[ -f "${flake_dir}/flake.lock" ] ||
  fail "no flake.lock in ${flake_dir}: this launcher builds only a locked flake; run 'nix flake lock' there"

command -v nix >/dev/null 2>&1 || fail "nix is not on PATH"
flake_ref="${flake_dir}#${attr}"

# nix without the caller's dynamic-linker path (issue #153, see the header).
run_nix() { env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH nix "$@"; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}

# ---- The key ---------------------------------------------------------------
# Pathspecs for every file but Agda sources; `*` crosses `/` in a git
# pathspec, so these match at any depth.
NOT_AGDA=(':(exclude)*.agda' ':(exclude)*.lagda' ':(exclude)*.lagda.*')

# git_inputs TOP: the lines the key hashes for a git checkout rooted at TOP,
# one per tracked file that is not an Agda source, "MODE HASH PATH", where
# HASH is the blob Nix will read: the working tree's for a file it changes
# ("deleted" for one it removed), the index's otherwise.  So a key describes
# the tree, not how git holds it: the same contents staged or not, or
# committed, give the same key.
git_inputs() {
  local top="$1" f
  {
    git -C "$top" -c core.quotePath=false diff --name-only -- "${NOT_AGDA[@]}" |
      while IFS= read -r f; do
        if [ -f "${top}/${f}" ]; then
          printf 'W\t%s\t%s\n' "$(git -C "$top" hash-object -- "$f")" "$f"
        else
          printf 'W\tdeleted\t%s\n' "$f"
        fi
      done
    printf 'END\n'
    # "MODE OBJECT STAGE<TAB>PATH" for every file in the index.
    git -C "$top" -c core.quotePath=false ls-files --stage -- "${NOT_AGDA[@]}"
  } | awk -F '\t' '
    !listed && $0 == "END" { listed = 1; next }
    !listed { blob[$3] = $2; next }
    { split($1, f, " "); h = ($2 in blob) ? blob[$2] : f[2]; print f[1], h, $2 }'
}

if top="$(git -C "$flake_dir" rev-parse --show-toplevel 2>/dev/null)"; then
  top="$(cd "$top" && pwd -P)"
  sub="${flake_dir#"$top"}"
  inputs="$(git_inputs "$top")" || fail "git could not list the files of ${top}"
  key="$(printf 'agda-for-flake key 1\nattr %s\nflake-dir %s\n%s\n' "$attr" "${sub:-/}" "$inputs" | sha256)"
  key="${key:0:32}"
  keyed_by="the tracked files of ${top} other than Agda sources"
else
  out="$(run_nix eval --raw --no-write-lock-file "${flake_ref}.outPath" </dev/null)" ||
    fail "nix eval of ${flake_ref}.outPath failed; no Agda was run"
  key="out-$(basename "$out" | cut -c1-32)"
  keyed_by="the output path ${out} (${flake_dir} is not in a git checkout)"
fi

cache="${XDG_CACHE_HOME:-$HOME/.cache}/agda-mcp/${attr//[^A-Za-z0-9._+-]/_}"
root="${cache}/${key}"
agda="${root}/bin/agda"

# ---- Build on a miss, under the lock ---------------------------------------
if [ ! -x "$agda" ]; then
  mkdir -p "$cache" || fail "cannot create the cache directory ${cache}"
  exec 9>"${root}.lock" || fail "cannot open the lock file ${root}.lock"
  if command -v flock >/dev/null 2>&1; then
    if ! flock -n 9; then
      say "waiting for another build of ${attr} for this key (${root}.lock)"
      flock 9
    fi
  fi
  # Whoever held the lock may have built it meanwhile.
  if [ ! -x "$agda" ]; then
    say "building ${attr} from ${flake_dir} (key ${key}, from ${keyed_by}); once per key"
    status=0
    run_nix build --no-write-lock-file "$flake_ref" -o "$root" </dev/null >&2 || status=$?
    if [ "$status" != 0 ]; then
      fail "nix build ${flake_ref} failed (exit ${status}; offline, or a broken flake?); no Agda was run"
    fi
    if [ ! -x "$agda" ]; then
      fail "${attr} built to $(readlink "$root" || echo "$root"), which has no executable bin/agda; name an Agda environment"
    fi
    # A note for whoever prunes the cache; the key is not reversible.  Best
    # effort: a note that cannot be written costs nothing but the note.
    if printf 'checkout %s\nattribute %s\noutput %s\nkeyed by %s\nbuilt %s\n' \
         "$flake_dir" "$attr" "$(readlink "$root")" "$keyed_by" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         > "${root}.txt.$$"; then
      mv -f "${root}.txt.$$" "${root}.txt" || true
    fi
  fi
  # Release the lock before Agda starts; it must not outlive the build.
  exec 9>&-
fi

exec "$agda" "$@"
