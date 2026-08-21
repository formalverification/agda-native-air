#!/usr/bin/env bash
# corpus-mcp-smoke.sh
#
# File: scripts/corpus-mcp-smoke.sh
#
# Description:
#   Drive agda-mcp's three corpus-backed search tools against a REAL assembled
#   corpus, over the real JSON-RPC stdio transport (issue #84).
#
#   `make agda-mcp-smoke` asks whether the server answers and registers its
#   tools, using the 24-row test fixture.  This asks the different question a
#   dataset card has to be able to answer: does an agent pointed at the
#   published corpus get useful results back?  So it goes through the shipped
#   binary, sends the requests a client sends, and asserts on the response
#   bodies rather than on handler return values.
#
#   Two phases, because the second query depends on the first — which is also
#   how an agent actually works:
#
#     Phase A  tools/list registers the three search tools; search_by_type
#              "Algebra" and search_by_name (a homomorphism lemma) return
#              well-formed, non-empty results.
#     Phase B  get_dependencies on a prettyQname *discovered in phase A*
#              returns that definition's dependency tokens, and with
#              expand=true resolves some of them to corpus entries.
#
# Usage:
#   scripts/corpus-mcp-smoke.sh --corpus data/corpora/agda-algebras/v0/corpus.jsonl
#     [--bin PATH]            # agda-mcp binary (default: cabal list-bin)
#     [--type-pattern STR]    # phase A search_by_type pattern   (default: Algebra)
#     [--name-pattern STR]    # phase A search_by_name pattern    (default: ∘-hom)
#     [--dep-name QNAME]      # skip discovery; use this prettyQname in phase B
#
#   Run inside `nix develop .#backend`, or through `make corpus-mcp-smoke`
#   which enters that shell itself.
#
# Design notes:
#   + No Agda is needed: the search tools read the in-memory index only, so
#     this stays fast and does not depend on a warm .agdai cache.
#   + Every assertion is made in Python over the parsed response, because a
#     tool result's `text` is itself a JSON document (double-encoded) and
#     grepping it would pass on a malformed payload.
#   + Failures print the offending response.  A smoke test that says only
#     "FAILED" costs more time than it saves.

set -euo pipefail

CORPUS=""
BIN=""
TYPE_PATTERN="Algebra"
NAME_PATTERN="∘-hom"
DEP_NAME=""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --corpus)       CORPUS="${2:?--corpus needs a path}"; shift 2 ;;
    --bin)          BIN="${2:?--bin needs a path}"; shift 2 ;;
    --type-pattern) TYPE_PATTERN="${2:?}"; shift 2 ;;
    --name-pattern) NAME_PATTERN="${2:?}"; shift 2 ;;
    --dep-name)     DEP_NAME="${2:?}"; shift 2 ;;
    -h|--help)      sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)              echo "corpus-mcp-smoke: unrecognized argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$CORPUS" ]; then
  echo "corpus-mcp-smoke: --corpus is required" >&2
  exit 2
fi

if [ ! -s "$CORPUS" ]; then
  echo "corpus-mcp-smoke: corpus not found or empty: $CORPUS" >&2
  echo "corpus-mcp-smoke: assemble one first — 'make extract-lib-nix && make corpus-nix'" >&2
  exit 2
fi

if [ -z "$BIN" ]; then
  ( cd "$REPO_ROOT/agda-mcp" && cabal build -v0 exe:agda-mcp )
  BIN="$( cd "$REPO_ROOT/agda-mcp" && cabal list-bin exe:agda-mcp )"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "corpus-mcp-smoke: binary : $BIN"
echo "corpus-mcp-smoke: corpus : $CORPUS"

# ---------------------------------------------------------------------------
# Phase A — tools/list plus the two pattern searches
# ---------------------------------------------------------------------------

# jq is not in the backend shell, so requests are built with printf and
# responses are read with python3 (which is).
python3 - "$TYPE_PATTERN" "$NAME_PATTERN" > "$WORK/phase-a-requests.jsonl" <<'PY'
import json, sys

type_pattern, name_pattern = sys.argv[1], sys.argv[2]
requests = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
     "params": {"name": "search_by_type",
                "arguments": {"pattern": type_pattern, "limit": 5}}},
    {"jsonrpc": "2.0", "id": 4, "method": "tools/call",
     "params": {"name": "search_by_name",
                "arguments": {"pattern": name_pattern, "limit": 5}}},
]
for r in requests:
    print(json.dumps(r, ensure_ascii=False))
PY

"$BIN" --corpus "$CORPUS" \
  < "$WORK/phase-a-requests.jsonl" \
  > "$WORK/phase-a.jsonl" \
  2> "$WORK/phase-a.err" || {
    echo "corpus-mcp-smoke: server exited non-zero in phase A; stderr was:" >&2
    cat "$WORK/phase-a.err" >&2
    exit 1
  }

DISCOVERED="$(
  python3 - "$WORK/phase-a.jsonl" "$TYPE_PATTERN" "$NAME_PATTERN" "$DEP_NAME" <<'PY'
import json, sys

responses_path, type_pattern, name_pattern, dep_name = sys.argv[1:5]

def fail(msg, payload=None):
    print(f"corpus-mcp-smoke: FAILED — {msg}", file=sys.stderr)
    if payload is not None:
        print(json.dumps(payload, indent=2, ensure_ascii=False)[:4000], file=sys.stderr)
    raise SystemExit(1)

by_id = {}
with open(responses_path, encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            fail(f"server wrote a non-JSON line on stdout: {line[:200]!r}")
        if "id" in message:
            by_id[message["id"]] = message

def result(rid, what):
    message = by_id.get(rid)
    if message is None:
        fail(f"no response to {what} (id={rid})", sorted(by_id))
    if "error" in message:
        fail(f"{what} returned a JSON-RPC error", message)
    return message["result"]

# --- the three search tools must be registered when a corpus is loaded ------
tools = {t["name"] for t in result(2, "tools/list").get("tools", [])}
missing = {"search_by_name", "search_by_type", "get_dependencies"} - tools
if missing:
    fail(f"corpus loaded but these tools are not registered: {sorted(missing)}", sorted(tools))

def payload(rid, what):
    """Unwrap a tool result: content[0].text is itself a JSON document."""
    res = result(rid, what)
    if res.get("isError"):
        fail(f"{what} answered isError", res)
    content = res.get("content") or []
    if not content or "text" not in content[0]:
        fail(f"{what} returned no text content", res)
    try:
        return json.loads(content[0]["text"])
    except json.JSONDecodeError:
        fail(f"{what} text is not JSON: {content[0]['text'][:400]!r}")

REQUIRED = {"prettyQname", "type", "defKind", "module", "hasBody"}

def check_hits(doc, what, pattern, field):
    # The search tools answer with a bare JSON array of results; accept an
    # object with a "results" key too, so a later envelope does not silently
    # turn this assertion off.
    if isinstance(doc, list):
        hits = doc
    elif isinstance(doc, dict):
        hits = doc.get("results", [])
    else:
        fail(f"{what} returned neither an array nor an object", doc)
    if not hits:
        fail(f"{what} for {pattern!r} found nothing in a real corpus", doc)
    for hit in hits:
        absent = REQUIRED - set(hit)
        if absent:
            fail(f"{what} result is missing {sorted(absent)}", hit)
    # The server promises a substring match; hold it to that.
    lowered = pattern.lower()
    if not any(lowered in str(hit.get(field, "")).lower() for hit in hits):
        fail(f"no {what} result actually contains {pattern!r} in its {field}", hits)
    return hits

type_hits = check_hits(payload(3, "search_by_type"), "search_by_type", type_pattern, "type")
name_hits = check_hits(payload(4, "search_by_name"), "search_by_name", name_pattern, "prettyQname")

print(f"corpus-mcp-smoke: search_by_type {type_pattern!r} -> {len(type_hits)} hits, "
      f"first {type_hits[0]['prettyQname']}", file=sys.stderr)
print(f"corpus-mcp-smoke: search_by_name {name_pattern!r} -> {len(name_hits)} hits, "
      f"first {name_hits[0]['prettyQname']}", file=sys.stderr)

# Phase B drills into a definition phase A actually found, unless one was named.
print(dep_name or name_hits[0]["prettyQname"])
PY
)"

echo "corpus-mcp-smoke: phase A OK — tools registered, both searches answered"

# ---------------------------------------------------------------------------
# Phase B — get_dependencies on the definition phase A found
# ---------------------------------------------------------------------------

python3 - "$DISCOVERED" > "$WORK/phase-b-requests.jsonl" <<'PY'
import json, sys

name = sys.argv[1]
requests = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
     "params": {"name": "get_dependencies", "arguments": {"name": name}}},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
     "params": {"name": "get_dependencies",
                "arguments": {"name": name, "expand": True}}},
    {"jsonrpc": "2.0", "id": 4, "method": "tools/call",
     "params": {"name": "get_dependencies",
                "arguments": {"name": "No.Such.Definition"}}},
]
for r in requests:
    print(json.dumps(r, ensure_ascii=False))
PY

"$BIN" --corpus "$CORPUS" \
  < "$WORK/phase-b-requests.jsonl" \
  > "$WORK/phase-b.jsonl" \
  2> "$WORK/phase-b.err" || {
    echo "corpus-mcp-smoke: server exited non-zero in phase B; stderr was:" >&2
    cat "$WORK/phase-b.err" >&2
    exit 1
  }

python3 - "$WORK/phase-b.jsonl" "$DISCOVERED" <<'PY'
import json, sys

responses_path, name = sys.argv[1:3]

def fail(msg, payload=None):
    print(f"corpus-mcp-smoke: FAILED — {msg}", file=sys.stderr)
    if payload is not None:
        print(json.dumps(payload, indent=2, ensure_ascii=False)[:4000], file=sys.stderr)
    raise SystemExit(1)

by_id = {}
with open(responses_path, encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if line:
            message = json.loads(line)
            if "id" in message:
                by_id[message["id"]] = message

def tool_result(rid, what):
    message = by_id.get(rid)
    if message is None:
        fail(f"no response to {what} (id={rid})", sorted(by_id))
    if "error" in message:
        fail(f"{what} returned a JSON-RPC error", message)
    return message["result"]

def payload(rid, what):
    res = tool_result(rid, what)
    if res.get("isError"):
        fail(f"{what} answered isError", res)
    content = res.get("content") or []
    if not content or "text" not in content[0]:
        fail(f"{what} returned no text content", res)
    return json.loads(content[0]["text"])

plain = payload(2, "get_dependencies")
if plain.get("name") != name:
    fail(f"get_dependencies echoed {plain.get('name')!r}, asked about {name!r}", plain)
if not plain.get("type"):
    fail("get_dependencies returned no type for a definition in the corpus", plain)
deps = plain.get("dependencies") or []
if not deps:
    fail(f"{name} has no dependency tokens; a real lemma depends on something", plain)
if plain.get("neighbors"):
    fail("get_dependencies expanded neighbors without expand=true", plain)

expanded = payload(3, "get_dependencies expand=true")
neighbors = expanded.get("neighbors") or []
if not neighbors:
    fail(f"expand=true resolved none of {name}'s {len(deps)} tokens to corpus entries",
         expanded)
for neighbor in neighbors:
    absent = {"prettyQname", "type", "defKind", "module", "hasBody"} - set(neighbor)
    if absent:
        fail(f"expanded neighbor is missing {sorted(absent)}", neighbor)

# A name that is not in the corpus must be refused, not answered with an empty
# shell: an agent has to be able to tell "no such definition" from "no deps".
absent_res = tool_result(4, "get_dependencies on an absent name")
if not absent_res.get("isError"):
    fail("get_dependencies answered a nonexistent definition without an error",
         absent_res)

print(f"corpus-mcp-smoke: get_dependencies {name} -> {len(deps)} tokens, "
      f"{len(neighbors)} resolved in-corpus", file=sys.stderr)
PY

echo "corpus-mcp-smoke: phase B OK — get_dependencies answered, expanded, and refused an absent name"
echo "corpus-mcp-smoke: OK"
