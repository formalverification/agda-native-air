#!/usr/bin/env bash
# =============================================================================
#  corpus-stdlib-depgraph.sh
# -----------------------------------------------------------------------------
#
#  File: scripts/corpus-stdlib-depgraph.sh
#
#  Purpose
#  -------
#  Produce the module-level dependency DOT for the agda-stdlib corpus lane
#  (issue #123).  The agda-algebras lane gets its DOT from the metadata
#  scanner, which must write a temporary Everything module INSIDE the library
#  root — impossible for the Nix-store stdlib, which is read-only.  This
#  script does the same job from a scratch directory instead: it reads the
#  extraction run-manifest, writes an Everything module importing every
#  successfully extracted stdlib module (with the union of infective flags
#  the library needs: --guardedness, --sized-types for Codata, --rewriting
#  for Debug.Trace), and checks it once with --dependency-graph.  The check
#  is warm — the store ships prebuilt interfaces — so this is minutes, not
#  hours.
#
#  Usage
#  -----
#    corpus-stdlib-depgraph.sh RUN_MANIFEST OUT_DOT LIBRARIES_FILE
#
#  Requires `agda` and `python3` on PATH (run inside a project dev shell).
#
# =============================================================================
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 RUN_MANIFEST OUT_DOT LIBRARIES_FILE" >&2
  exit 2
fi

MANIFEST=$(realpath "$1")
OUT_DOT=$(realpath -m "$2")
LIB_FILE=$(realpath "$3")

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

python3 - "$MANIFEST" "$WORKDIR/EverythingStdlib.agda" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
ok = [r["module"] for r in manifest["results"] if r["ok"]]
with open(sys.argv[2], "w") as f:
    f.write("{-# OPTIONS --guardedness --sized-types --rewriting #-}\n")
    f.write("module EverythingStdlib where\n")
    for mod in ok:
        f.write(f"import {mod}\n")
print(f"[depgraph] EverythingStdlib over {len(ok)} extracted modules")
PY

( cd "$WORKDIR" \
  && agda --library-file="$LIB_FILE" --library standard-library -i . \
          --dependency-graph="$OUT_DOT" EverythingStdlib.agda >/dev/null )

echo "[depgraph] wrote $OUT_DOT ($(wc -l < "$OUT_DOT") lines)"
