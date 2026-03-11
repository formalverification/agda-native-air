#!/usr/bin/env bash
# ==============================================================================
# run-sbt.sh
# ------------------------------------------------------------------------------
# Purpose
#   Run sbt in a reproducible, pinned-JDK environment, with a clean Java-related
#   env and optional AGDA_JSON_BIN injection for the AgdaJsonlDriver pipeline.
#
# Why this exists
#   Our Makefile targets were getting unreadable because each sbt invocation
#   needed:
#     - JAVA_HOME pinning (so sbt and forked JVM use the intended JDK)
#     - PATH adjustment to put that java first
#     - removal of COURSIER_JAVA_HOME / _JAVA_OPTIONS / JDK_JAVA_OPTIONS
#     - JAVA_TOOL_OPTIONS open-module flags needed by Spark / Java 17+
#     - optional AGDA_JSON_BIN export (consumed by Scala code)
#
# Usage
#   run-sbt.sh [options] -- <sbt command tokens...>
#
# Options
#   --project-dir DIR     (required) directory containing build.sbt
#   --java-home   DIR     (required) JAVA_HOME to pin (must contain bin/java)
#   --sbt         BIN     sbt executable (default: sbt)
#   --sbt-flags   "..."   extra flags passed to sbt (default: empty)
#   --jmo         "..."   JAVA_TOOL_OPTIONS value (e.g. --add-opens flags)
#   --agda-json-bin PATH  if set, exports AGDA_JSON_BIN=PATH for sbt subprocess
#   --no-show             suppress diagnostic banner
#
# Examples
#   ./scripts/run-sbt.sh \
#     --project-dir proof-parser \
#     --java-home "$JAVA_HOME" \
#     --jmo "$JMO" \
#     -- \
#     "test"
#
#   ./scripts/run-sbt.sh \
#     --agda-json-bin "$AGDA_JSON_BIN" \
#     --project-dir proof-parser \
#     --java-home "$JAVA_HOME" \
#     --jmo "$JMO" \
#     -- \
#     "project ProofParser" \
#     "runMain proofparser.extract.AgdaJsonlDriver $AGDA_JSONL_ARGS"
# ==============================================================================

set -euo pipefail

AGDA_JSON_BIN_ENV=""
PROJECT_DIR=""
JAVA_HOME_ARG=""
SBT_BIN="sbt"
SBT_FLAGS=""
JMO=""
NO_SHOW=0

log() {
    echo "[info] $(date +"%Y-%m-%d %H:%M:%S") - [run-sbt] $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agda-json-bin) AGDA_JSON_BIN_ENV="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --java-home)   JAVA_HOME_ARG="$2"; shift 2 ;;
    --sbt)         SBT_BIN="$2"; shift 2 ;;
    --sbt-flags)   SBT_FLAGS="$2"; shift 2 ;;
    --jmo)         JMO="$2"; shift 2 ;;
    --no-show)     NO_SHOW=1; shift ;;
    --)            shift; break ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$PROJECT_DIR" ]]  || { echo "ERROR: --project-dir is required" >&2; exit 2; }
[[ -n "$JAVA_HOME_ARG" ]] || { echo "ERROR: --java-home is empty; cannot pin JDK for sbt" >&2; exit 2; }

[[ -x "$JAVA_HOME_ARG/bin/java" ]] || {
  echo "ERROR: $JAVA_HOME_ARG/bin/java not found or not executable" >&2
  exit 2
}

if [[ "${NO_SHOW:-0}" != "1" ]]; then
  log "- project-dir   : $PROJECT_DIR"
  log "- JAVA_HOME     : $JAVA_HOME_ARG"
  log "- java          : $(command -v java || true)"
  log "- pinned java   : $JAVA_HOME_ARG/bin/java"
  log "- java -version : $("$JAVA_HOME_ARG/bin/java" -version 2>&1 | head -n 1 || true)"
  log "- sbt           : $SBT_BIN"
fi

if [[ -n "$AGDA_JSON_BIN_ENV" ]]; then
  export AGDA_JSON_BIN="$AGDA_JSON_BIN_ENV"
fi

cd "$PROJECT_DIR"

# shellcheck disable=SC2086
env \
  -u COURSIER_JAVA_HOME \
  -u _JAVA_OPTIONS -u JDK_JAVA_OPTIONS \
  JAVA_HOME="$JAVA_HOME_ARG" \
  PATH="$JAVA_HOME_ARG/bin:$PATH" \
  JAVA_TOOL_OPTIONS="$JMO" \
  "$SBT_BIN" $SBT_FLAGS \
    -java-home "$JAVA_HOME_ARG" \
    "$@"
