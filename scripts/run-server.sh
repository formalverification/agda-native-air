#!/usr/bin/env bash
# run-server.sh
#
# File: scripts/run-server.sh
#
# Description:
#   Launch agda-mcp inside the Nix backend shell, or directly when the
#   registration names everything the shell would supply.
#
#   Claude Code (and other MCP clients) spawn the server as a bare subprocess
#   without the Nix environment.  This wrapper enters `nix develop .#backend`
#   before running the server, ensuring agda, cabal, and GHC are available.
#   A registration that names a prebuilt server (AGDA_MCP_BIN) and its own
#   Agda (--agda-bin) needs none of them, and skips the shell (issue #249, the
#   last IMPORTANT block below).
#
# IMPORTANT:
#   The Nix shellHook prints a banner to stdout, which would corrupt
#   the MCP JSON-RPC framing.  We use fd juggling to route all shellHook output
#   to stderr while preserving real stdout for the server's JSON-RPC traffic.
#
# IMPORTANT (issue #76: do not run the shell from the client's directory):
#   `nix develop` runs the shellHook in the *caller's* working directory, and an
#   MCP client spawns this script with its own project as cwd.  The hook derives
#   AGDA_DIR from `git rev-parse --show-toplevel` and creates it, so run from a
#   client's checkout it wrote a stray (and broken) agda/ directory, plus a
#   target/ from its sbt version probe, into that project's root.  The two
#   lines below remove that entirely: cd to this repository first, and hand the
#   hook an explicit anchor so its answer does not depend on cwd at all.
#   docs/agda-mcp/agda-mcp-environment.md has the reproduction and the full inventory of
#   what gets written where.
#
# IMPORTANT (issue #153: do not inherit the client's dynamic-linker path):
#   Every devShell of this flake exports LD_LIBRARY_PATH (Nix runtime libraries
#   for the Python wheels; issue #96).  A client started from inside such a
#   shell hands that variable to this script, and the profile `nix` we exec
#   then loads the shell's older libssl and aborts before any JSON-RPC:
#     nix: .../libssl.so.3: version `OPENSSL_3.2.0' not found (required by libcurl)
#   which the client reports as CONNECTION_CLOSED.  The variable is cleared
#   below; the devShell re-exports its own value inside, so the server and
#   `agda` see exactly what they saw before.
#
# Binary resolution:
#   AGDA_MCP_BIN, when set, names the server binary to run (the same variable
#   the Make targets honor), so a worktree can point at a prebuilt server.
#   Otherwise the binary is what `cabal list-bin exe:agda-mcp` names, and it
#   must be an executable regular file: `cabal list-bin` builds nothing, so a
#   fresh worktree needs `cabal build exe:agda-mcp` first.  Whichever way the
#   resolution fails (list-bin itself failing, a missing build, an override
#   naming a directory), the message says how to build it and names the
#   override, instead of the bare "No such file" the client would otherwise see.
#   An override that is not an executable file is refused before the shell is
#   entered, so the message arrives while the client is still listening.
#
# IMPORTANT (issue #242: the server works where the client started it):
#   The cd above is for the shellHook, not for the server.  The directory the
#   client started this script in (for Claude Code, the directory `claude` was
#   launched from) is captured first, as LAUNCH_DIR, and the server is anchored
#   there: when the arguments carry no --cwd, the script passes
#   --cwd LAUNCH_DIR, so the server behaves as it would if the client had
#   spawned the binary itself.  A --cwd the arguments do carry wins, so every
#   registration that names its checkout explicitly is unchanged.
#   Claude Code expands ${PWD} in a registration's arguments at launch, and
#   every registration in claude-tooling passes --cwd ${PWD} on that strength;
#   a client that does not expand variables hands over the literal string.  So
#   this script substitutes LAUNCH_DIR for ${PWD} and for ${PWD:-default} (the
#   two forms Claude Code accepts) wherever they occur in an argument, scanning
#   left to right so a substituted path is never rescanned.  No other variable
#   is expanded: a general expander in a launcher is a surprise waiting for a
#   value with a space in it.  An argument that still holds "${" afterwards is
#   named on stderr, and the server refuses a --cwd that does.
#
# IMPORTANT (issue #249: the fast path, and what each path does not provide):
#   When AGDA_MCP_BIN names an executable file and the arguments, after the
#   ${PWD} substitution, carry --agda-bin with a value, this script runs the
#   server directly: the same substitution, --cwd default, cd to this
#   repository, and cleared LD_LIBRARY_PATH as below, then exec, with no
#   `nix develop`.  The shell cost 5 to 32 s before the server could answer
#   initialize, and Codex CLI's `exec` does not wait for a server: in issue
#   #243's trial its model looked for the tools 8 ms before they arrived.  The
#   fast path is never the default; without --agda-bin the server resolves
#   `agda` on PATH, which only the shell makes this repository's.
#   What the fast path does not provide is the shell's environment.  The server
#   and everything it spawns inherit the client's: `make` for a check_project
#   gate, the program a --check-command names (`make`, `env`), an --agda-bin
#   given as a bare name, and, when --agda-flags names no --library-file, the
#   registry the server reads ($AGDA_DIR/libraries, which the shell points at
#   this repository's agda/libraries) all come from the client's PATH and
#   environment.  A registration that needs the shell's tools leaves
#   AGDA_MCP_BIN unset.  The shell path has the mirror image of that gap: a
#   check_project call naming a `target` runs bare `make <target>`, and a
#   recipe that says `agda` gets the shell's Agda, the wrong one for a project
#   with its own, unless the Makefile is told which.
#
# IMPORTANT (issue #342: say when a pinned Agda has fallen behind its flake):
#   A registration whose --agda-bin is a fixed pin (a symlink into the store,
#   built by hand with `nix build <checkout>#<attr> -o <link>`) matches one
#   lock and goes stale in silence when the project's lock moves; the only
#   symptom is a NotInScope inside a dependency at the first load.  So when
#   --agda-bin resolves, two levels up, to a store path, this script lists the
#   packages that the flake at or above --cwd builds now (`nix eval`, about a
#   second, in the background beside the server, so the client's wait for
#   initialize does not grow), and when the pin is none of them but one of
#   them has the pin's package name, it prints one line on stderr naming both
#   paths and the remedy.  It says nothing when it cannot tell: no flake, an
#   evaluation that fails, a pin of a name the flake does not build, or a
#   binary inside the checkout (a dev shell's .agda/bin/agda, which follows
#   the checkout).  scripts/agda-for-flake.sh, the launcher keyed by the
#   lock, needs no check: it is the remedy.  The line sits beside the one
#   issue #282 plans for a server binary older than its sources, in the same
#   voice, and a client shows both where it shows this script's stderr.
#
# Usage (from anywhere):
#   scripts/run-server.sh [extra agda-mcp args...]
#   AGDA_MCP_BIN=/path/to/agda-mcp scripts/run-server.sh --agda-bin /path/to/agda [...]
#
# Relative paths are resolved by the server after this launcher enters REPO_ROOT,
# on either path: --cwd itself is relative to REPO_ROOT, and later paths are
# relative to the resulting server cwd.  Use an absolute --cwd when naming
# another checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The same path, shell-escaped, for the commands the diagnostics ask the
# operator to paste: a checkout path with a space must survive the paste.
REPO_ROOT_Q="$(printf %q "${REPO_ROOT}")"

# The directory the client started us in, before the cd below moves us: the
# server's anchor (issue #242, see the header).  Bash's $PWD is the logical
# path when the inherited one names this directory, as Claude Code's ${PWD}
# is, and the physical one otherwise.
LAUNCH_DIR="${PWD}"

# expand_pwd ARG: set REPLY to ARG with each ${PWD} and ${PWD:-default}
# replaced by LAUNCH_DIR.  Each pass moves the text before the next "${PWD"
# into the result, so the substituted path is never scanned again, and a
# "${PWD" that opens some other name (${PWDX}, ${PWD:x}) is kept as written.
#
# The literal tokens live in variables and are matched as "$open" and
# "$close": a quoted variable in a pattern matches as plain text, which
# sidesteps the rules for single quotes inside a double-quoted ${var%%pat}.
expand_pwd() {
  local rest="$1" out="" open='${PWD' close='}'
  while [[ "$rest" == *"$open"* ]]; do
    out+="${rest%%"$open"*}"
    rest="${rest#*"$open"}"
    case "$rest" in
      "$close"*)       rest="${rest#"$close"}";  out+="${LAUNCH_DIR}" ;;
      ":-"*"$close"*)  rest="${rest#*"$close"}"; out+="${LAUNCH_DIR}" ;;
      *)               out+="$open" ;;
    esac
  done
  REPLY="${out}${rest}"
}

SERVER_ARGS=()
has_cwd=0
has_agda_bin=0
agda_bin_value=""
cwd_value=""
prev=""
unexpanded='${'
for arg in "$@"; do
  expand_pwd "$arg"
  if [[ "$REPLY" == *"$unexpanded"* ]]; then
    echo "agda-mcp: an argument still holds an unexpanded variable (this launcher substitutes \${PWD} and nothing else): $REPLY" >&2
  fi
  if [ "$REPLY" = "--cwd" ]; then has_cwd=1; fi
  # --agda-bin with a non-empty value, read after the substitution (lean2agda's
  # registration passes --agda-bin ${PWD}/.agda/bin/agda): half of the fast
  # path's condition (issue #249, see the header).
  if [ "$prev" = "--agda-bin" ] && [ -n "$REPLY" ]; then has_agda_bin=1; agda_bin_value="$REPLY"; fi
  if [ "$prev" = "--cwd" ]; then cwd_value="$REPLY"; fi
  prev="$REPLY"
  SERVER_ARGS+=("$REPLY")
done
# No --cwd among the arguments: anchor the server where the client started us.
if [ "$has_cwd" = 0 ]; then SERVER_ARGS+=(--cwd "${LAUNCH_DIR}"); cwd_value="${LAUNCH_DIR}"; fi

# ---- The pin check (issue #342, see the header) ----------------------------
# drv_pname STORE_PATH: the package name in STORE_PATH without its hash or
# version, split as Nix's builtins.parseDrvName splits a name: the version
# begins after the first "-" that is not followed by a letter.
drv_pname() {
  local rest="${1##*/}" out="" part
  rest="${rest#*-}"
  while [[ "$rest" == *-* ]]; do
    part="${rest%%-*}"
    rest="${rest#*-}"
    out+="${out:+-}${part}"
    if [[ ! "$rest" =~ ^[A-Za-z] ]]; then REPLY="$out"; return; fi
  done
  REPLY="${out:+${out}-}${rest}"
}

# pin_check AGDA_BIN CWD: print one line when AGDA_BIN is a fixed pin that
# the project's flake no longer builds.  Silent whenever it cannot tell.
pin_check() {
  local bin="$1" cwd="$2" store_dir="${NIX_STORE_DIR:-/nix/store}" store dir system listing
  local name path pin_pname stale=""
  # A binary inside the checkout (a dev shell's .agda/bin/agda) follows the
  # checkout, and this launcher's own agda-for-flake.sh is not a store path.
  case "$bin" in "$cwd"/*) return 0 ;; esac
  # The pin is the store path two levels above bin/agda, wherever the
  # registration's symlinks lead (a wrapper's bin/agda may itself point into
  # another store path, which names the unwrapped Agda, not the environment).
  store="$(readlink -f -- "$(dirname -- "$(dirname -- "$bin")")" 2>/dev/null)" || return 0
  case "$store" in "${store_dir}"/*/*|"${store_dir}"/) return 0 ;; "${store_dir}"/*) ;; *) return 0 ;; esac
  # The project's flake: the nearest flake.nix at or above CWD, within the
  # repository (the rule agda-for-flake.sh uses).
  dir="$cwd"
  while [ ! -f "${dir}/flake.nix" ]; do
    if [ -e "${dir}/.git" ] || [ "$dir" = / ]; then return 0; fi
    dir="$(dirname -- "$dir")"
  done
  system="$(nix eval --impure --raw --expr builtins.currentSystem 2>/dev/null)" || return 0
  # Every package the flake builds now, as "ATTR OUTPATH" lines; a package
  # whose evaluation fails is left out rather than failing the listing.  The
  # ${...} in the expression are Nix's, so the quotes are single.
  # shellcheck disable=SC2016
  listing="$(nix eval --raw --no-write-lock-file "${dir}#packages.${system}" --apply '
    ps: builtins.concatStringsSep "\n" (builtins.concatMap (n:
      let r = builtins.tryEval ps.${n}.outPath; in
      if r.success then [ "${n} ${r.value}" ] else [ ]) (builtins.attrNames ps))' \
    2>/dev/null)" || return 0
  drv_pname "$store"; pin_pname="$REPLY"
  while read -r name path; do
    [ -n "$path" ] || continue
    # The pin is one of them: current.
    if [ "$path" = "$store" ]; then return 0; fi
    drv_pname "$path"
    if [ -z "$stale" ] && [ "$REPLY" = "$pin_pname" ]; then stale="${name} ${path}"; fi
  done <<< "$listing"
  # No package of the pin's name: a pin from elsewhere, nothing to say.
  [ -n "$stale" ] || return 0
  echo "agda-mcp: --agda-bin ${bin} is ${store}, but the flake at ${dir} now builds ${stale%% *} as ${stale#* }: the pin predates a change to that flake (its lock, most often), so loads may fail inside a dependency; rebuild the pin, or register ${REPO_ROOT}/scripts/agda-for-flake.sh (docs/agda-mcp/registering-a-project.md)." >&2
}

# Run it beside the server, never before it: the evaluation takes a second
# or more, and the client is waiting for initialize.  The doubled
# parentheses detach it, so no zombie waits on a server that never reaps it;
# its stdout is stderr, so not a byte reaches the JSON-RPC stream.  A
# relative --cwd is the server's, resolved against this repository.
if [ -n "$agda_bin_value" ] && command -v nix >/dev/null 2>&1; then
  case "$cwd_value" in /*) ;; *) cwd_value="$(cd "${REPO_ROOT}" && cd "$cwd_value" 2>/dev/null && pwd)" || cwd_value="" ;; esac
  if [ -n "$cwd_value" ]; then
    ( ( unset LD_LIBRARY_PATH DYLD_LIBRARY_PATH; pin_check "$agda_bin_value" "$cwd_value" || true ) </dev/null 1>&2 & )
  fi
fi

# Anchor the shellHook to this repository, whatever the client's cwd was.
export AGDA_NATIVE_AIR_ROOT="${REPO_ROOT}"
cd "${REPO_ROOT}"

# Do not carry the client's dynamic-linker search path into `nix develop`
# (issue #153, see the header).  Both variables, as the Makefile's nested-Nix
# wrapper (NIX_CLEAN_ENV) does: LD_LIBRARY_PATH on Linux, DYLD_LIBRARY_PATH on
# Darwin, which the flake also declares as a system.
unset LD_LIBRARY_PATH DYLD_LIBRARY_PATH

# Every way of ending up without a runnable server gets the same message:
# what went wrong, how to build the binary, and the override.  The two hints
# are spliced into the shell's copy of this function below, so both paths
# say exactly this.
BUILD_HINT="build the server with:  cd ${REPO_ROOT_Q}/agda-mcp && cabal build exe:agda-mcp"
OVERRIDE_HINT="or point AGDA_MCP_BIN at a prebuilt agda-mcp binary."
no_server() {
  echo "agda-mcp: $1" >&2
  echo "agda-mcp: ${BUILD_HINT}" >&2
  echo "agda-mcp: ${OVERRIDE_HINT}" >&2
  exit 1
}

if [ -n "${AGDA_MCP_BIN:-}" ]; then
  # An override must name a regular, executable file (-x alone is true of a
  # directory as well), on either path.  Tested here, after the cd, so a
  # relative value means what it means inside the shell, and before the
  # shell's seconds, so the client's log keeps the message.
  [ -f "$AGDA_MCP_BIN" ] && [ -x "$AGDA_MCP_BIN" ] ||
    no_server "server binary is not an executable file: $AGDA_MCP_BIN"
  # The fast path (issue #249, see the header): the registration names the
  # server and its Agda, so run the server now, in the client's environment.
  # Stdout is still the client's pipe; no banner can reach it.
  if [ "$has_agda_bin" = 1 ]; then
    exec "$AGDA_MCP_BIN" "${SERVER_ARGS[@]}"
  fi
fi

# Say the most likely cause of a failed launch FIRST.  The MCP client keeps
# only the stderr that arrives before the connection closes, and the
# authoritative check below runs after the shell entry, which takes seconds;
# in the field the client's log ended at the shellHook's first bytes and the
# real message never showed.  This is a heuristic (a glob where the check
# below asks cabal), so it warns and continues rather than deciding.
if [ -z "${AGDA_MCP_BIN:-}" ]; then
  prebuilt=""
  for candidate in "${REPO_ROOT}"/agda-mcp/dist-newstyle/build/*/ghc-*/agda-mcp-*/x/agda-mcp/build/agda-mcp/agda-mcp; do
    # The same test the authoritative check applies: a regular, executable file.
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then prebuilt="$candidate"; break; fi
  done
  if [ -z "$prebuilt" ]; then
    echo "agda-mcp: no executable server binary under ${REPO_ROOT}/agda-mcp/dist-newstyle (a fresh worktree?)." >&2
    echo "agda-mcp: if this launch fails, build it first:  cd ${REPO_ROOT_Q}/agda-mcp && cabal build exe:agda-mcp   (inside nix develop .#backend)" >&2
    echo "agda-mcp: or point AGDA_MCP_BIN at a prebuilt agda-mcp binary." >&2
  fi
fi

# Save real stdout on fd 3, then redirect stdout → stderr.
# This catches all shellHook banner output that leaks to stdout.
exec 3>&1 1>&2

exec nix develop "${REPO_ROOT}#backend" --command \
  bash -c '
    exec 1>&3 3>&-
    # The outer no_server, with the same two hints.
    no_server() {
      echo "agda-mcp: $1" >&2
      echo "agda-mcp: '"${BUILD_HINT}"'" >&2
      echo "agda-mcp: '"${OVERRIDE_HINT}"'" >&2
      exit 1
    }
    if [ -n "${AGDA_MCP_BIN:-}" ]; then
      BIN="$AGDA_MCP_BIN"
    else
      cd "'"${REPO_ROOT}/agda-mcp"'"
      BIN=$(cabal list-bin exe:agda-mcp 2>&1) || no_server "failed to resolve the server binary: $BIN"
      cd "'"${REPO_ROOT}"'"
    fi
    # A regular, executable file: -x alone is true of a directory as well.
    [ -f "$BIN" ] && [ -x "$BIN" ] || no_server "server binary is not an executable file: $BIN"
    exec "$BIN" "$@"
  ' -- "${SERVER_ARGS[@]}"
