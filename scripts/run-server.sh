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
#   docs/agda-mcp-environment.md has the reproduction and the full inventory of
#   what gets written where.
#
# Usage (from anywhere):
#   scripts/run-server.sh [extra agda-mcp args...]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Anchor the shellHook to this repository, whatever the client's cwd was.
export AGDA_NATIVE_AIR_ROOT="${REPO_ROOT}"
cd "${REPO_ROOT}"

# Save real stdout on fd 3, then redirect stdout → stderr.
# This catches all shellHook banner output that leaks to stdout.
exec 3>&1 1>&2

exec nix develop "${REPO_ROOT}#backend" --command \
  bash -c '
    exec 1>&3 3>&-
    cd "'"${REPO_ROOT}/agda-mcp"'"
    BIN=$(cabal list-bin exe:agda-mcp 2>&1) || {
      echo "agda-mcp: failed to resolve binary: $BIN" >&2
      exit 1
    }
    cd "'"${REPO_ROOT}"'"
    exec "$BIN" "$@"
  ' -- "$@"
