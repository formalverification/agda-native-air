#!/usr/bin/env bash
# run-server.sh
#
# File: scripts/run-server.sh
#
# Description:
#   Launch agda-mcp inside the Nix backend shell.
#
#   Claude Code (and other MCP clients) spawn the server as a bare subprocess
#   without the Nix environment.  This wrapper enters `nix develop .#backend`
#   before running the server, ensuring agda, cabal, and GHC are available.
#
# IMPORTANT:
#   The Nix shellHook prints a banner to stdout, which would corrupt
#   the MCP JSON-RPC framing.  We use fd juggling to route all shellHook output
#   to stderr while preserving real stdout for the server's JSON-RPC traffic.
#
# IMPORTANT (issue #76 — do not run the shell from the client's directory):
#   `nix develop` runs the shellHook in the *caller's* working directory, and an
#   MCP client spawns this script with its own project as cwd.  The hook derives
#   AGDA_DIR from `git rev-parse --show-toplevel` and creates it, so run from a
#   client's checkout it wrote a stray (and broken) agda/ directory — plus a
#   target/ from its sbt version probe — into that project's root.  The two
#   lines below remove that entirely: cd to this repository first, and hand the
#   hook an explicit anchor so its answer does not depend on cwd at all.
#   docs/agda-mcp/agda-mcp-environment.md has the reproduction and the full inventory of
#   what gets written where.
#
# IMPORTANT (issue #153 — do not inherit the client's dynamic-linker path):
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
# Usage (from anywhere):
#   scripts/run-server.sh [extra agda-mcp args...]
#
# Relative paths are resolved by the server after this launcher enters REPO_ROOT:
# --cwd itself is relative to REPO_ROOT, and later paths are relative to the
# resulting server cwd.  Use an absolute --cwd when naming another checkout.

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
unexpanded='${'
for arg in "$@"; do
  expand_pwd "$arg"
  if [[ "$REPLY" == *"$unexpanded"* ]]; then
    echo "agda-mcp: an argument still holds an unexpanded variable (this launcher substitutes \${PWD} and nothing else): $REPLY" >&2
  fi
  if [ "$REPLY" = "--cwd" ]; then has_cwd=1; fi
  SERVER_ARGS+=("$REPLY")
done
# No --cwd among the arguments: anchor the server where the client started us.
if [ "$has_cwd" = 0 ]; then SERVER_ARGS+=(--cwd "${LAUNCH_DIR}"); fi

# Anchor the shellHook to this repository, whatever the client's cwd was.
export AGDA_NATIVE_AIR_ROOT="${REPO_ROOT}"
cd "${REPO_ROOT}"

# Do not carry the client's dynamic-linker search path into `nix develop`
# (issue #153, see the header).  Both variables, as the Makefile's nested-Nix
# wrapper (NIX_CLEAN_ENV) does: LD_LIBRARY_PATH on Linux, DYLD_LIBRARY_PATH on
# Darwin, which the flake also declares as a system.
unset LD_LIBRARY_PATH DYLD_LIBRARY_PATH

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
    # Every way of ending up without a runnable server gets the same message:
    # what went wrong, how to build the binary, and the override.
    no_server() {
      echo "agda-mcp: $1" >&2
      echo "agda-mcp: build the server with:  cd '"${REPO_ROOT_Q}"'/agda-mcp && cabal build exe:agda-mcp" >&2
      echo "agda-mcp: or point AGDA_MCP_BIN at a prebuilt agda-mcp binary." >&2
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
