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
# Usage (from repo root):
#   scripts/run-server.sh [extra agda-mcp args...]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
