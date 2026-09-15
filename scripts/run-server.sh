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
# Usage (from anywhere):
#   scripts/run-server.sh [extra agda-mcp args...]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Anchor the shellHook to this repository, whatever the client's cwd was.
export AGDA_NATIVE_AIR_ROOT="${REPO_ROOT}"
cd "${REPO_ROOT}"

# Do not carry the client's dynamic-linker search path into `nix develop`
# (issue #153, see the header).  Both variables, as the Makefile's nested-Nix
# wrapper (NIX_CLEAN_ENV) does: LD_LIBRARY_PATH on Linux, DYLD_LIBRARY_PATH on
# Darwin, which the flake also declares as a system.
unset LD_LIBRARY_PATH DYLD_LIBRARY_PATH

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
      echo "agda-mcp: build the server with:  cd '"${REPO_ROOT}"'/agda-mcp && cabal build exe:agda-mcp" >&2
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
  ' -- "$@"
