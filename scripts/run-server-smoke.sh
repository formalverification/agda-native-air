#!/usr/bin/env bash
# run-server-smoke.sh
#
# File: scripts/run-server-smoke.sh
#
# Description:
#   Prove that scripts/run-server.sh anchors the server where the client
#   started it (issue #242), through the real launcher and the real
#   `nix develop` it enters.
#
#   Claude Code expands ${PWD} in a registration's arguments, so every
#   registration that passes --cwd ${PWD} works there; a client that expands
#   nothing hands the launcher the literal string, and a hand-written
#   registration may leave the flag out.  The launcher substitutes the
#   directory it was started in for ${PWD} and ${PWD:-default}, and passes
#   that directory as --cwd when the arguments carry none.  The Haskell suite
#   (tier 2g) covers the server's half: without --cwd it stays where it was
#   started, and it refuses a value still holding "${".  What it cannot reach
#   is the launcher, which cds to this repository before the server starts, so
#   a launcher that forgot the client's directory would anchor every one of
#   these sessions here instead.  That is what this script would catch.
#
#   One scratch client checkout, under a path holding a space and an
#   ampersand (the two characters a careless substitution mangles), with a
#   Makefile declaring a target only it declares.  Each case is one launch,
#   sending initialize and check_project naming that target:
#
#     dollar-pwd       from the client, --cwd '${PWD}' as a client that does
#                      not expand variables passes it, and ${PWD} inside
#                      --agda-flags too, as claude-tooling's agda-flrp
#                      registration writes it (the banner must show it
#                      substituted)
#     dollar-pwd-dflt  from the client, --cwd '${PWD:-/nonexistent}', the
#                      other form Claude Code accepts
#     no-cwd           from the client, no --cwd at all
#     explicit-cwd     from another directory, --cwd naming the client: an
#                      explicit flag wins over the default
#     other-var        from the client, --cwd '${CLAUDE_PROJECT_DIR}': not
#                      substituted, named by the launcher on stderr, and
#                      refused by the server before it starts
#
#   The first four must answer check_project from the client: the gate
#   searched from the client root, found the client's own Makefile, and ran
#   there.  A launcher anchored at this repository instead finds no Makefile
#   declaring the target and fails the call by name, so a regression runs
#   nothing of this repository's.
#
# Usage:
#   scripts/run-server-smoke.sh
#
#   Needs nix, python3, and a built server (`make agda-mcp-launcher-smoke`
#   builds it first), or AGDA_MCP_BIN naming one.  Each case is one entry of
#   the backend shell, a few seconds when the shell is already built.
#
# Design notes:
#   + Every assertion is made in Python over the parsed responses: a tool
#     result's text is itself a JSON document, and grepping it would pass on
#     a malformed payload.
#   + A failure prints the case's stderr and stdout; a smoke test that says
#     only "FAILED" costs more time than it saves.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="${REPO_ROOT}/scripts/run-server.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The scratch client: a repository boundary, so the gate's upward search
# stops here, and a Makefile declaring the one target the request names.
mkdir -p "${WORK}/client dir & co/.git" "${WORK}/elsewhere"
printf 'launcher-smoke:\n\t@echo launcher-smoke-gate-ran\n' > "${WORK}/client dir & co/Makefile"
# The server reports directories as the operating system names them, so the
# expected path is the physical one.
CLIENT="$(cd "${WORK}/client dir & co" && pwd -P)"
ELSEWHERE="$(cd "${WORK}/elsewhere" && pwd -P)"

cat > "${WORK}/requests.jsonl" <<'JSON'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"check_project","arguments":{"target":"launcher-smoke","verbose":true}}}
JSON

# launch CASE DIR ARGS...: start the launcher from DIR with ARGS, keeping its
# stdout, stderr, and exit status under $WORK/CASE.*.
launch() {
  local name="$1" dir="$2"
  shift 2
  echo "run-server-smoke: ${name}: from ${dir}, args: $*"
  if (cd "$dir" && "$LAUNCHER" "$@" --check-timeout 60 \
        < "${WORK}/requests.jsonl" > "${WORK}/${name}.out" 2> "${WORK}/${name}.err"); then
    echo 0 > "${WORK}/${name}.status"
  else
    echo "$?" > "${WORK}/${name}.status"
  fi
}

launch dollar-pwd      "$CLIENT"    --cwd '${PWD}' --agda-flags '-i ${PWD}/src'
launch dollar-pwd-dflt "$CLIENT"    --cwd '${PWD:-/nonexistent}'
launch no-cwd          "$CLIENT"
launch explicit-cwd    "$ELSEWHERE" --cwd "$CLIENT"
launch other-var       "$CLIENT"    --cwd '${CLAUDE_PROJECT_DIR}'

python3 - "$WORK" "$CLIENT" <<'PY'
import json, os, sys

work, client = sys.argv[1], sys.argv[2]
failures = []

def read(name, ext):
    with open(os.path.join(work, f"{name}.{ext}"), encoding="utf-8") as handle:
        return handle.read()

def fail(name, msg):
    failures.append(name)
    print(f"run-server-smoke: FAILED {name}: {msg}", file=sys.stderr)
    print(f"--- {name} stderr (tail) ---\n{read(name, 'err')[-3000:]}", file=sys.stderr)
    print(f"--- {name} stdout (head) ---\n{read(name, 'out')[:2000]}", file=sys.stderr)

def answer(name, wanted):
    """The decoded tool answer of response `wanted`, or None."""
    for line in read(name, "out").splitlines():
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("id") == wanted and "result" in msg:
            return json.loads(msg["result"]["content"][0]["text"])
    return None

def anchored_at_client(name):
    status = read(name, "status").strip()
    if status != "0":
        return fail(name, f"the launcher exited {status}")
    if f"cwd: {client}\n" not in read(name, "err"):
        return fail(name, f"the startup banner does not name cwd: {client}")
    a = answer(name, 2)
    if a is None:
        return fail(name, "no check_project answer for id 2")
    gate, command = a.get("gate", {}), a.get("command", {})
    checks = [
        (a.get("success") is True, "success is not true"),
        (gate.get("searchedFrom") == client, f"gate.searchedFrom is {gate.get('searchedFrom')!r}"),
        (gate.get("makefile") == os.path.join(client, "Makefile"), f"gate.makefile is {gate.get('makefile')!r}"),
        (command.get("cwd") == client, f"command.cwd is {command.get('cwd')!r}"),
        ("launcher-smoke-gate-ran" in a.get("outputTail", ""), "the client's gate did not print its marker"),
    ]
    bad = [why for ok, why in checks if not ok]
    if bad:
        return fail(name, "; ".join(bad) + f"\n{json.dumps(a, indent=2)[:2000]}")
    print(f"run-server-smoke: ok {name}: check_project ran the client's gate in {client}")

for name in ["dollar-pwd", "dollar-pwd-dflt", "no-cwd", "explicit-cwd"]:
    anchored_at_client(name)

# ${PWD} inside a longer argument is substituted too.  (The server splits
# --agda-flags on whitespace, so a path with a space would not survive as a
# flag; the banner joins the words with single spaces, which is what this
# compares, and the check is about the substitution, not the flag.)
name = "dollar-pwd"
if f"flags: -i {client}/src\n" not in read(name, "err"):
    fail(name, f"the banner does not show --agda-flags with ${{PWD}} substituted ({client}/src)")
else:
    print(f"run-server-smoke: ok {name}: ${{PWD}} inside --agda-flags became {client}/src")

name = "other-var"
err = read(name, "err")
checks = [
    (read(name, "status").strip() != "0", "the launcher exited 0"),
    ("this launcher substitutes ${PWD} and nothing else" in err, "the launcher did not name the unexpanded argument"),
    ("--cwd ${CLAUDE_PROJECT_DIR} holds a variable the client did not expand" in err, "the server did not refuse the value by name"),
    (answer(name, 2) is None, "the server answered check_project"),
]
bad = [why for ok, why in checks if not ok]
if bad:
    fail(name, "; ".join(bad))
else:
    print(f"run-server-smoke: ok {name}: named by the launcher and refused by the server")

if failures:
    print(f"run-server-smoke: FAILED: {', '.join(failures)}", file=sys.stderr)
    raise SystemExit(1)
print("run-server-smoke: OK: the launcher anchors the server where the client started it")
PY
