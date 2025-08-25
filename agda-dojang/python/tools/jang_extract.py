#!/usr/bin/env python3
# file: python/tools/jang_extract.py
"""
AgdaJang Trace extractor (v0)

(implement with `agda --interaction-json`)

+  Walk `--root` for `.agda` files.

+  For each file:

   +  Send a `load` command to Agda's JSON interaction.

   +  Request **goals/metas** and **constraints**.

   +  If a goal is already solved (e.g., after `C-c C-a`), we can reconstruct the
      term by asking Agda for the definition of the name or by parsing the file region.
      In v0, we focus on *holes filled during a session* and capture *final gives*.

   +  Record `(context, goal_type, solution_term)` when a goal gets solved via `give`.

NOTES

  Agda's JSON protocol provides:

  +  Interaction points (metas),
  +  "Give" results (when a hole is filled),
  +  Goal types and contexts.

  For a tight first pass, we can also extract examples offline by scanning Agda
  repo for patterns like:

      _ : (context) → goalType
      _ = refine⟨ CANDIDATE ⟩

  where we (or the LLM) replaced holes via `refine⟨_⟩`.  Then the extractor just
  parses the file to read `CANDIDATE` and the goal type around it. That's the
  quickest "walking skeleton."
"""
import json, subprocess, pathlib, sys, time, re
from datetime import datetime

AGDA_BIN = "agda"  # ensure on PATH (or set via env)

def agda_proc():
    return subprocess.Popen([AGDA_BIN, "--interaction-json"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)

def send(p, obj):
    p.stdin.write(json.dumps(obj) + "\n"); p.stdin.flush()

def recv(p):
    line = p.stdout.readline()
    return json.loads(line) if line else None

def load_file(p, path, include_paths):
    send(p, {"command":"load", "filepath":str(path), "includePaths":include_paths, "options":["--ignore-interfaces"]})
    # Read until we get a "done" or "status" event; in practice parse all until queue empties or timeout.

def main():
    root = pathlib.Path(sys.argv[1])
    out  = open(sys.argv[2], "w")
    inc  = [str(root)]
    p = agda_proc()
    try:
        for agda in root.rglob("*.agda"):
            load_file(p, agda, inc)
            # TODO: ask for metas, contexts, etc.
            # Pseudocode: send(p, {"command":"metas"}); parse; later hook into "give" events.
            # In v0, we can instrument our workflow to use `--log-json` and scrape successful 'give' messages.
    finally:
        p.terminate()
        out.close()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: agdadojo_extract.py <root> <out.jsonl>")
        sys.exit(1)
    main()
