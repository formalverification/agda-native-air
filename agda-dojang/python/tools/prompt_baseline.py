#!/usr/bin/env python3
from __future__ import annotations
import json, sys, pathlib, shlex, subprocess
from typing import Iterable

def iter_jsonl(path: pathlib.Path) -> Iterable[dict]:
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)

def run_try(tool: pathlib.Path, task: dict, agda_flags: str) -> dict:
    args = [
        sys.executable, str(tool),
        "--goal", task["goal"],
        "--format", "json",
        "--agda-flags", agda_flags,
    ]
    for imp in task.get("imports", []):
        args += ["--imports", imp]
    if "candidate" in task:
        args += ["--candidate", task["candidate"]]
    elif "tactic" in task:
        args += ["--tactic", task["tactic"]]
    else:
        # fallback tiny heuristic for Nat
        args += ["--candidate", "suc zero"]

    p = subprocess.run(args, capture_output=True, text=True)
    out = p.stdout.strip() or ""
    try:
        parsed = json.loads(out)
    except Exception:
        # text mode fallback (unlikely if jang_try always uses --format json)
        parsed = {"ok": False, "kind": "error", "raw": out, "rc": p.returncode}
    return parsed

def main():
    if len(sys.argv) < 3:
        print("usage: prompt_baseline.py <tasks.jsonl> <rows.jsonl> [--agda-flags '<flags>']")
        sys.exit(2)
    tasks_in = pathlib.Path(sys.argv[1])
    rows_out = pathlib.Path(sys.argv[2])
    agda_flags = "-i agda --library-file=agda/libraries -l agda-jang"
    if len(sys.argv) > 3 and sys.argv[3] == "--agda-flags":
        agda_flags = sys.argv[4]

    tool = pathlib.Path(__file__).parent / "jang_try.py"
    rows_out.parent.mkdir(parents=True, exist_ok=True)

    with rows_out.open("w", encoding="utf-8") as w:
        for t in iter_jsonl(tasks_in):
            res = run_try(tool, t, agda_flags)
            # normalize shape → (context, goal, completion) + metadata
            row = {
                "context": {"imports": t.get("imports", [])},
                "goal": t["goal"],
                "completion": t.get("candidate") or t.get("tactic") or "suc zero",
                "ok": (res.get("ok") is True),
                "agda": res,
            }
            w.write(json.dumps(row, ensure_ascii=False) + "\n")

if __name__ == "__main__":
    main()
