#!/usr/bin/env python3
"""
prompt_baseline.py
==================

File: agda-ai-prover/agda-jang/python/tools/prompt_baseline.py

What:
  Tiny "prompting baseline" that turns a list of tasks (JSONL) into a list of
  (context, goal, completion) attempts (JSONL), by invoking `jang_try.py` and
  recording Agda’s verdict.

Why:
  - Seed a small dataset before we wire larger extract/transform stages.
  - Exercise the full loop: (context, goal) → suggestion → Agda validates → log.

Input (tasks.jsonl):
  One JSON object per line. Each object MUST contain:
    - "imports": [str,...]      e.g., ["open import Agda.Builtin.Nat", "open import Agda.Builtin.Bool"]
    - "goal": str               e.g., "Nat"
  And EITHER:
    - "candidate": str          e.g., "suc zero"
    - OR "tactic": str          e.g., "applyReport:_+_"
  If neither is provided, we fallback to a trivial baseline candidate.

  Example line:

  {"imports":["open import Agda.Builtin.Nat","open import Agda.Builtin.Bool"], "goal":"Nat", "candidate":"true"}

Output (rows.jsonl):
  One or more JSON objects per input task (more than one if `jang_try.py`
  responds with a batch list). Fields:
    - "context": {"imports": [...]}
    - "goal": str
    - "completion": str         (candidate or tactic used)
    - "ok": bool                (Agda accepted)
    - "agda": object            (verbatim parsed JSON from jang_try or element)

Usage:
  The following commands will create a tiny seed `tasks.jsonl` file and run this script on it.

  ```bash
  cd agda-ai-prover
  nix develop
  cd agda-jang
  make rows
  ```

  Alternatively, use the example `tasks.json` file provided in the repository, or
  create one and run this script manually, from inside `nix develop` shell, in
  the `agda-jang` directory, as follows:

  ```bash
  PYTHONPATH=python python3 python/tools/prompt_baseline.py \
    data/tasks.jsonl data/rows.jsonl \
    --agda-flags "-i agda --library-file=agda/libraries -l agda-jang"
  ```

Tip:
  Use `make rows` to create a tiny seed tasks.jsonl and run this script.

"""

from __future__ import annotations
import json, os, sys, pathlib, subprocess
from typing import Iterable, Iterator, Dict, Any, List, Union

Task = Dict[str, Any]
AgdaJSON = Union[Dict[str, Any], List[Dict[str, Any]]]

def iter_jsonl(path: pathlib.Path) -> Iterable[Task]:
    if not path.exists():
        raise FileNotFoundError(f"tasks file not found: {path}")
    with path.open("r", encoding="utf-8") as f:
        for i, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception as e:
                raise ValueError(f"Invalid JSON on line {i} of {path}: {e}") from e
            yield obj

def run_try(tool: pathlib.Path, task: Task, agda_flags: str) -> AgdaJSON:
    # Build argv for jang_try.py
    args: List[str] = [
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
        args += ["--candidate", "suc zero"]

    # Ensure child has PYTHONPATH=python so jang_try can import local modules.
    env = dict(os.environ)
    pyroot = str(pathlib.Path(__file__).resolve().parents[1])  # agda-jang/python
    env["PYTHONPATH"] = env.get("PYTHONPATH", "") or pyroot

    p = subprocess.run(args, capture_output=True, text=True, env=env)
    out = p.stdout.strip() or ""
    try:
        parsed = json.loads(out)
    except Exception:
        # Fallback: record raw output
        return {"ok": False, "kind": "error", "rc": p.returncode, "raw": out}
    return parsed

def rows_from_result(task: Task, parsed: AgdaJSON) -> Iterator[Dict[str, Any]]:
    """
    Normalize both dict and list (batch) shapes into one-or-more rows.
    """
    ctx = {"imports": task.get("imports", [])}
    completion = task.get("candidate") or task.get("tactic") or "suc zero"

    if isinstance(parsed, list):
        # batch: emit one row per element
        for i, elem in enumerate(parsed):
            ok = bool(elem.get("ok") is True)
            yield {
                "context": ctx,
                "goal": task["goal"],
                "completion": completion,
                "ok": ok,
                "batch_index": i,
                "agda": elem,
            }
    else:
        ok = bool(parsed.get("ok") is True)
        yield {
            "context": ctx,
            "goal": task["goal"],
            "completion": completion,
            "ok": ok,
            "agda": parsed,
        }

def main():
    if len(sys.argv) < 3:
        print("usage: prompt_baseline.py <tasks.jsonl> <rows.jsonl> [--agda-flags '<flags>']", file=sys.stderr)
        sys.exit(2)

    tasks_in = pathlib.Path(sys.argv[1]).resolve()
    rows_out = pathlib.Path(sys.argv[2]).resolve()
    agda_flags = "-i agda --library-file=agda/libraries -l agda-jang"
    if len(sys.argv) > 3 and sys.argv[3] == "--agda-flags":
        agda_flags = sys.argv[4]

    tool = pathlib.Path(__file__).resolve().parent / "jang_try.py"
    rows_out.parent.mkdir(parents=True, exist_ok=True)

    count_in = 0
    count_out = 0
    with rows_out.open("w", encoding="utf-8") as w:
        for task in iter_jsonl(tasks_in):
            count_in += 1
            parsed = run_try(tool, task, agda_flags)
            for row in rows_from_result(task, parsed):
                w.write(json.dumps(row, ensure_ascii=False) + "\n")
                count_out += 1

    print(f"[baseline] processed {count_in} tasks → wrote {count_out} rows to {rows_out}", file=sys.stderr)

if __name__ == "__main__":
    main()
