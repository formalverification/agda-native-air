"""
File: scripts/python/auto_floor.py

Description: The proof-search floor of the benchmark (issues #205, #206):
  Agda's own proof search on every obligation, with no model and no corpus
  ranking, each term it finds judged by the batch fill_hole under --safe.

  The search is Mimer, the one Agda 2.8 runs for Cmd_autoOne (it replaced
  Agsy in Agda 2.7), asked through agda-mcp's auto tool.  The number it
  produces per tier is a denominator no model had to earn: an agent's or the
  loop's solves on a tier read differently when Agda alone already solves
  some of them.

  Three phases, each one agda-mcp process fed a fixed batch of JSON-RPC
  requests on stdin (so a phase is one command, and its whole input is a
  pure function of the index):

  1.  Hints, only with --hints needles.  Each `needle:` tag of a row (the
      composition tier's, issue #160) is typed by type_of at the obligation's
      hole, and only the names Agda types there are passed on, since auto
      refuses the whole call when one hint names nothing in scope.  A needle
      dropped here is named in the row.
  2.  Search.  auto at the obligation's hole (each obligation has exactly
      one), on a server started with --auto and the subjects' flags.
  3.  Judgment.  Every term found is given to fill_hole, on a server whose
      flags add --safe (the judge's flag), parenthesized as the loop
      parenthesizes candidates.  A row is solved when that status is "ok":
      batch agda's verdict, never the lane's.

  The reference this reproduces is `agsy-suite.py` in claude-tooling's
  driving-agda-mcp skill, which drove a lane by hand: the same flags, the
  same rendering (Simplified), Agda's default options, and the same judge.

  Usage, from the repository root inside `nix develop .#backend` with the
  server built (`make auto-floor` wraps it):

    PYTHONPATH=. python3 scripts/python/auto_floor.py \\
      --server agda-mcp/dist-newstyle/.../agda-mcp \\
      --out-dir reports/auto-floor --run-id floor-1 [--hints needles] \\
      [--tiers agda-algebras-composition-v0] [--timeout-ms 1000]

  Output: <out-dir>/<run-id>/rows.jsonl (one record per obligation, in index
  order) and summary.json (the configuration and the per-tier counts).  A
  row the run could not measure names why: `failure` for a search with no
  usable answer (outcome `tool-failure`), `judgeFailure` for a found term the
  judge never ruled on (counted per tier as `unjudged`), and the summary
  lists every such row as `unmeasured`.  Both files are written either way,
  for the evidence they hold, and the exit status is 1 when any row is
  unmeasured, since the counts are then not a floor.

  fill_hole patches each obligation in place and restores it, so nothing
  else may run against the fixtures meanwhile.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, FrozenSet, List, Mapping, Optional, Sequence, Tuple

from scripts.python.utils.command_runner import run_command
from scripts.python.utils.file_ops import read_text, write_text
from scripts.python.utils.pipeline_types import ErrorType, PipelineError, Result, sequence_results

# The subjects' flags (the agent bench's, and agsy-suite.py's), relative to
# the repository root, where the server is started.  The judge adds --safe.
SUBJECT_FLAGS: Tuple[str, ...] = (
    "-i", "agda-dojang/agda", "--library-file=agda/libraries",
    "-l", "agda-dojang", "-l", "standard-library", "-l", "agda-algebras",
)
JUDGE_FLAGS: Tuple[str, ...] = SUBJECT_FLAGS + ("--safe",)
SERVER_TIMEOUT_SECONDS: int = 300

Call = Tuple[str, Mapping[str, Any]]


@dataclass(frozen=True)
class Options:
    """The command line, parsed."""
    repo: Path
    index: Path
    server: Path
    out_dir: Path
    run_id: str
    hints: str                    # "none" or "needles"
    tiers: Optional[FrozenSet[str]]
    ids: Optional[FrozenSet[str]]
    timeout_ms: Optional[int]


@dataclass(frozen=True)
class Obligation:
    """One index row, with what the phases need of it."""
    id: str
    tier: str                     # the obligation's directory, e.g. agda-stdlib-v0
    source: str
    difficulty: str
    path: Path                    # absolute
    needles: Tuple[str, ...]


@dataclass(frozen=True)
class Answer:
    """One tools/call answer: whether it was an isError, and its payload
    (the decoded JSON when the text is JSON, else the text)."""
    is_error: bool
    body: Any


# ---------------------------------------------------------------------------
# Pure core
# ---------------------------------------------------------------------------

def obligation_of(repo: Path, row: Mapping[str, Any]) -> Obligation:
    """An index row as an Obligation."""
    rel = Path(row["obligation"])
    return Obligation(
        id=row["id"],
        tier=rel.parts[2],
        source=row["source"],
        difficulty=row.get("difficulty", ""),
        path=repo / rel,
        needles=tuple(t[len("needle:"):] for t in row.get("tags", []) if t.startswith("needle:")),
    )


def selected(opts: Options, ob: Obligation) -> bool:
    """Whether the run's --tiers and --ids filters keep an obligation."""
    return ((opts.tiers is None or ob.tier in opts.tiers)
            and (opts.ids is None or ob.id in opts.ids))


def hole_line(source: str) -> Optional[int]:
    """The 1-based line of the obligation's hole: the first line whose code,
    before any line comment, holds the hole token.  The benchmark's
    obligations have exactly one hole and no block comments."""
    return next((n for n, ln in enumerate(source.splitlines(), 1)
                 if "{!!}" in ln.split("--", 1)[0]), None)


def rpc_input(calls: Sequence[Call]) -> str:
    """The JSON-RPC lines for one phase: initialize, then one tools/call per
    call, numbered from 1 in order."""
    init = {"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {}}
    reqs = [init] + [
        {"jsonrpc": "2.0", "id": n, "method": "tools/call",
         "params": {"name": name, "arguments": dict(args)}}
        for n, (name, args) in enumerate(calls, 1)
    ]
    return "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in reqs)


def answer_of(response: Mapping[str, Any]) -> Answer:
    """A tools/call response as an Answer.  The payload is JSON inside the
    content's text, except for refusals the server words as prose.  A
    JSON-RPC error (no result at all) is an error answer carrying its
    message, not an empty success."""
    if "error" in response or not isinstance(response.get("result"), dict):
        err = response.get("error")
        return Answer(is_error=True, body=(err.get("message") if isinstance(err, dict) else None)
                      or f"no result in the response: {json.dumps(response)[:300]}")
    result = response["result"]
    text = (result.get("content") or [{}])[0].get("text", "")
    try:
        body: Any = json.loads(text)
    except json.JSONDecodeError:
        body = text
    return Answer(is_error=bool(result.get("isError")), body=body)


def json_object(line: str) -> Optional[Dict[str, Any]]:
    """A line as a JSON object, or None when it is not one."""
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def answers_of(stdout: str) -> Dict[int, Answer]:
    """Every tools/call answer in a phase's output, by request id.  A line
    that is not a JSON object (a server cut off mid-line, say) answers
    nothing, so the call it was answering becomes a row's named failure
    rather than a traceback that loses the whole phase."""
    responses = (r for r in (json_object(ln) for ln in stdout.splitlines() if ln.strip()) if r is not None)
    return {r["id"]: answer_of(r) for r in responses if isinstance(r.get("id"), int) and r["id"] > 0}


def needle_calls(obs: Sequence[Obligation], lines: Mapping[str, int]) -> List[Call]:
    """Phase 1: one type_of per needle, at the obligation's hole."""
    return [("type_of", {"filePath": str(ob.path), "expr": nd, "line": lines[ob.id]})
            for ob in obs for nd in ob.needles]


def nameable_needles(obs: Sequence[Obligation], got: Mapping[int, Answer]) -> Dict[str, Tuple[str, ...]]:
    """Each obligation's needles that Agda typed at the hole, in tag order,
    read off phase 1's answers (numbered as needle_calls numbered them)."""
    numbered = [(ob.id, nd) for ob in obs for nd in ob.needles]
    typed = {n for n, a in got.items()
             if not a.is_error and isinstance(a.body, dict) and "type" in a.body}
    return {ob.id: tuple(nd for n, (oid, nd) in enumerate(numbered, 1) if oid == ob.id and n in typed)
            for ob in obs}


def auto_call(ob: Obligation, hints: Sequence[str], timeout_ms: Optional[int]) -> Call:
    """Phase 2: auto at the obligation's one hole."""
    args: Dict[str, Any] = {"filePath": str(ob.path), "holeIndex": 0}
    if hints:
        args["hints"] = list(hints)
    if timeout_ms is not None:
        args["timeoutMs"] = timeout_ms
    return ("auto", args)


def usable_term(body: Mapping[str, Any]) -> Optional[str]:
    """A found answer's term when it is one the judge can be given: a
    nonempty string.  A `found` without one is a malformed answer, never a
    term to judge."""
    term = body.get("term")
    return term if body.get("outcome") == "found" and isinstance(term, str) and term.strip() else None


def found_term(a: Optional[Answer]) -> Optional[str]:
    """The term an auto answer found, when it found a usable one."""
    if a is None or a.is_error or not isinstance(a.body, dict):
        return None
    return usable_term(a.body)


def judge_call(ob: Obligation, term: str) -> Call:
    """Phase 3: fill_hole with the found term, parenthesized as the loop
    parenthesizes a candidate."""
    return ("fill_hole", {"filePath": str(ob.path), "holeIndex": 0, "candidate": f"({term})"})


def failure_of(phase: str, answer: Optional[Answer], field: str) -> Optional[str]:
    """Why a phase's answer carries no usable `field`, or None when it does:
    no answer at all, a failed call, or an answer without the field."""
    if answer is None:
        return f"the {phase} phase's server gave no answer for this obligation"
    if answer.is_error:
        return (answer.body if isinstance(answer.body, str) else json.dumps(answer.body))[:500]
    if not isinstance(answer.body, dict) or field not in answer.body:
        return f"the {phase} answer has no {field}: {json.dumps(answer.body)[:300]}"
    return None


def record_of(ob: Obligation, hints: Sequence[str], searched: Optional[Answer],
              judged: Optional[Answer]) -> Dict[str, Any]:
    """One obligation's row: what the search said, and what the judge said of
    the term it found.  Every failure is named in the row: a search with no
    usable answer (a `found` with no nonempty term included) is a
    `tool-failure` with its `failure`, and a found term the judge never ruled
    on carries `judgeFailure`, so it is never read as a term the judge
    refused."""
    search_failure = failure_of("search", searched, "outcome")
    body = searched.body if search_failure is None and searched is not None else {}
    if body.get("outcome") == "found" and usable_term(body) is None:
        # A found answer the judge could not be given: the floor counts every
        # found term judged, so this is a failure, not an unsolved row.
        search_failure = f"the search answer says found with no usable term: {json.dumps(body)[:300]}"
        body = {}
    err = body.get("error") or {}
    term = usable_term(body)
    judge_failure = failure_of("judge", judged, "status") if term is not None else None
    status = judged.body["status"] if term is not None and judge_failure is None and judged is not None else None
    rec: Dict[str, Any] = {
        "id": ob.id, "tier": ob.tier, "source": ob.source, "difficulty": ob.difficulty,
        "hints": list(hints),
        "unnamedHints": [nd for nd in ob.needles if nd not in hints],
        "outcome": body["outcome"] if search_failure is None else "tool-failure",
        "term": body.get("term"),
        "message": body.get("message"),
        "errorStage": err.get("stage"),
        "errorCode": err.get("code"),
        "errorMessage": (err.get("message") or "")[:300] or None,
        "searchMs": body.get("searchMs"),
        "fillHole": status,
        "solved": status == "ok",
    }
    if search_failure is not None:
        rec["failure"] = search_failure
    if judge_failure is not None:
        rec["judgeFailure"] = judge_failure
    return rec


def failed_rows(records: Sequence[Mapping[str, Any]]) -> List[str]:
    """The rows a run could not measure: a search with no usable answer, or
    a found term the judge never ruled on.  A run with any is not a floor."""
    return [r["id"] for r in records if "failure" in r or "judgeFailure" in r]


def summary_of(opts: Options, records: Sequence[Mapping[str, Any]], server: str) -> Dict[str, Any]:
    """The run's configuration and its counts, per tier and in total."""
    tiers = list(dict.fromkeys(r["tier"] for r in records))
    def counts(rs: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
        return {"solved": sum(1 for r in rs if r["solved"]), "total": len(rs),
                "outcomes": dict(sorted(Counter(r["outcome"] for r in rs).items())),
                "unjudged": sum(1 for r in rs if "judgeFailure" in r)}
    return {
        "runId": opts.run_id,
        "config": {
            "server": server, "subjectFlags": list(SUBJECT_FLAGS), "judgeFlags": list(JUDGE_FLAGS),
            "hints": opts.hints, "timeoutMs": opts.timeout_ms,
            "tiers": sorted(opts.tiers) if opts.tiers else None,
            "ids": sorted(opts.ids) if opts.ids else None,
        },
        "perTier": {t: counts([r for r in records if r["tier"] == t]) for t in tiers},
        "total": counts(records),
        # The rows the run could not measure; nonempty means these counts are
        # not a floor, said in the file itself so no reader of it can miss it.
        "unmeasured": failed_rows(records),
    }


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------

def load_index(opts: Options) -> Result[List[Obligation], PipelineError]:
    """The selected obligations, in index order."""
    def parse(text: str) -> Result[List[Obligation], PipelineError]:
        try:
            rows = [json.loads(ln) for ln in text.splitlines() if ln.strip()]
        except json.JSONDecodeError as e:
            return Result.err(PipelineError(ErrorType.PARSING_ERROR, f"bad index line: {e}"))
        return Result.ok([ob for ob in (obligation_of(opts.repo, r) for r in rows) if selected(opts, ob)])
    return read_text(opts.index).and_then(parse)


def hole_lines(obs: Sequence[Obligation]) -> Result[Dict[str, int], PipelineError]:
    """Each obligation's hole line, read from its file."""
    def one(ob: Obligation) -> Result[Tuple[str, int], PipelineError]:
        def found(src: str) -> Result[Tuple[str, int], PipelineError]:
            ln = hole_line(src)
            return (Result.ok((ob.id, ln)) if ln is not None else
                    Result.err(PipelineError(ErrorType.VALIDATION_ERROR, f"no hole in {ob.path}")))
        return read_text(ob.path).and_then(found)
    return sequence_results([one(ob) for ob in obs]).map(dict)


def serve(opts: Options, flags: Sequence[str], extra: Sequence[str],
          calls: Sequence[Call]) -> Result[Dict[int, Answer], PipelineError]:
    """One phase: a server answering a fixed batch of calls, its answers."""
    if not calls:
        return Result.ok({})
    cmd = [str(opts.server), "--agda-flags", " ".join(flags),
           "--timeout", str(SERVER_TIMEOUT_SECONDS), *extra]
    return (run_command(cmd, cwd=opts.repo, capture_output=True, text=True, input_text=rpc_input(calls))
            .map(lambda p: answers_of(p.stdout)))


def run(opts: Options) -> Result[Tuple[List[Dict[str, Any]], Dict[str, Any]], PipelineError]:
    """The three phases over the selected obligations."""
    obs_r = load_index(opts)
    if obs_r.is_err:
        return Result.err(obs_r.unwrap_err())
    obs = obs_r.unwrap()
    hinted = [ob for ob in obs if ob.needles] if opts.hints == "needles" else []
    if hinted:
        lines_r = hole_lines(hinted)
        if lines_r.is_err:
            return Result.err(lines_r.unwrap_err())
        typed_r = serve(opts, SUBJECT_FLAGS, [], needle_calls(hinted, lines_r.unwrap()))
        if typed_r.is_err:
            return Result.err(typed_r.unwrap_err())
        hints = nameable_needles(hinted, typed_r.unwrap())
    else:
        hints = {}
    searched_r = serve(opts, SUBJECT_FLAGS, ["--auto"],
                       [auto_call(ob, hints.get(ob.id, ()), opts.timeout_ms) for ob in obs])
    if searched_r.is_err:
        return Result.err(searched_r.unwrap_err())
    searched = searched_r.unwrap()
    found = [(n, ob, found_term(searched.get(n))) for n, ob in enumerate(obs, 1)]
    to_judge = [(n, ob, t) for n, ob, t in found if t is not None]
    judged_r = serve(opts, JUDGE_FLAGS, [], [judge_call(ob, t) for _, ob, t in to_judge])
    if judged_r.is_err:
        return Result.err(judged_r.unwrap_err())
    judged = {n: judged_r.unwrap().get(k) for k, (n, _, _) in enumerate(to_judge, 1)}
    records = [record_of(ob, hints.get(ob.id, ()), searched.get(n), judged.get(n))
               for n, ob in enumerate(obs, 1)]
    server = (str(opts.server.relative_to(opts.repo)) if opts.server.is_relative_to(opts.repo)
              else str(opts.server))
    return Result.ok((records, summary_of(opts, records, server)))


def comma_set(text: str) -> Optional[FrozenSet[str]]:
    """A comma-separated filter; empty means no filter."""
    return frozenset(x for x in text.split(",") if x) or None


def parse_options(argv: Sequence[str]) -> Options:
    p = argparse.ArgumentParser(description="Agda's own proof search on every benchmark obligation.")
    p.add_argument("--repo", type=Path, default=Path.cwd())
    p.add_argument("--index", type=Path, default=Path("data/benchmarks/benchmark-index.jsonl"))
    p.add_argument("--server", type=Path, required=True)
    p.add_argument("--out-dir", type=Path, default=Path("reports/auto-floor"))
    p.add_argument("--run-id", required=True)
    p.add_argument("--hints", choices=["none", "needles"], default="none")
    p.add_argument("--tiers", default="")
    p.add_argument("--ids", default="")
    p.add_argument("--timeout-ms", type=int, default=None)
    a = p.parse_args(argv)
    # The server refuses a bound outside these on every call, so a run with
    # one would write a row of tool failures per obligation and a summary
    # of 0 solved; refuse it here, before anything runs.
    ceiling = SERVER_TIMEOUT_SECONDS * 1000
    if a.timeout_ms is not None and not 0 < a.timeout_ms < ceiling:
        p.error(f"--timeout-ms must be a positive number of milliseconds below the "
                f"server's --timeout of {SERVER_TIMEOUT_SECONDS} s ({ceiling} ms); got {a.timeout_ms}")
    repo = a.repo.resolve()
    return Options(repo=repo, index=repo / a.index, server=(repo / a.server).resolve(),
                   out_dir=repo / a.out_dir, run_id=a.run_id, hints=a.hints,
                   tiers=comma_set(a.tiers), ids=comma_set(a.ids), timeout_ms=a.timeout_ms)


def main(argv: Sequence[str]) -> int:
    opts = parse_options(argv)
    outcome = run(opts)
    if outcome.is_err:
        sys.stderr.write(f"auto_floor: {outcome.unwrap_err()}\n")
        return 1
    records, summary = outcome.unwrap()
    out = opts.out_dir / opts.run_id
    written = (write_text(out / "rows.jsonl", "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records))
               .and_then(lambda _: write_text(out / "summary.json",
                                              json.dumps(summary, indent=2, ensure_ascii=False) + "\n")))
    if written.is_err:
        sys.stderr.write(f"auto_floor: {written.unwrap_err()}\n")
        return 1
    for tier, c in summary["perTier"].items():
        sys.stderr.write(f"  {tier:32} {c['solved']:3} / {c['total']:3}  {c['outcomes']}\n")
    t = summary["total"]
    sys.stderr.write(f"auto_floor: {t['solved']} / {t['total']} solved; rows in {out}\n")
    failed = failed_rows(records)
    if failed:
        sys.stderr.write(f"auto_floor: {len(failed)} row(s) not measured (a tool failure or an "
                         f"unjudged term), so these counts are not a floor: {', '.join(failed)}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
