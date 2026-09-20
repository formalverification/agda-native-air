#!/usr/bin/env python3
"""
File: scripts/python/demo/replays.py

Description: The sessions the demo page replays, and how one is assembled from
  the committed archive (Issue #85).

  `ROSTER` names them.  They are not a sample: each is one half of a contrast
  the archive already holds, and the page exists to show the contrast.

    +  `algebras-kernels-ker-con`, both arms.  The same obligation, the same
       thirteen tools, two verdicts.  Opus 5 assembles the congruence from
       `kerRel`, `mkcon`, and `HomKerComp`; Sonnet 5 finds the same names and
       writes `kercon′ h = kercon h`, which the judge puts in the restated
       column and not in the solve count.
    +  `algebras-subalgebras-sub-trans-iso`, Opus 5.  A composition, watched:
       `⊙-hom` and `⊙-injective` composed with `≅toInjective`, reached through
       an `exports_of` that answered `NotInScope` and a `type_of` whose
       `NotInScope` answer carried the right name as a suggestion.
    +  `stdlib-nat-mul-comm`, both arms.  Both models needed `trans`; Opus
       added an import line and was counted a solve, Sonnet appended `; trans`
       to the fixture's own `using` list and failed the preservation gate with
       a file that type-checks.  The two final files differ by one line.

  Everything a replay carries is read out of a committed file: the obligation
  and its metadata from `data/benchmarks/`, the exchange from the subject's
  `transcript.jsonl`, the verdict from its `outcome.json`, and the file the
  judge read from its `final/`.  Nothing is re-derived and no verdict is
  formed here: the archive's judge decided, and the page reports.

Design Principles:
  +  The roster is data.  Adding a replay is one `Choice`; the assembly code
     does not know which subjects it is running over.
  +  Paths come from the index.  A benchmark row states where its obligation
     and its gold live, so no path is composed from a naming convention.
  +  The diff is computed, not described.  `marked_diff` turns the obligation
     and the final file into a marked listing, so the page shows what the
     session changed instead of asserting it.
"""

from __future__ import annotations

import difflib
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from scripts.python.demo.numbers import OPUS_RUN, SONNET_RUN
from scripts.python.demo.paths import check_clean, normalize_value
from scripts.python.demo.transcript import (
    Session,
    load,
    read_session,
)
from scripts.python.utils.file_ops import load_json, read_text
from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
)

REPLAY_SCHEMA = "agda-native-air.demo.replay.v0"


@dataclass(frozen=True)
class Choice:
    """One replay: which archived subject, and what it is here to show."""

    run: str
    subject: str
    model_label: str
    blurb: str


#: The replays, in tab order.  The flagship contrast leads; the pair that
#: differs by one import line closes, because it is the shortest session and
#: the sharpest reading of the gate.
ROSTER: Tuple[Choice, ...] = (
    Choice(
        run=OPUS_RUN,
        subject="algebras-kernels-ker-con",
        model_label="Opus 5",
        blurb=(
            "Four `type_of` queries, one `fill_hole` probe, one edit, one "
            "check.  The congruence is assembled from the pieces the "
            "fixture's own `using` lists name, under a `where` block."),
    ),
    Choice(
        run=SONNET_RUN,
        subject="algebras-kernels-ker-con",
        model_label="Sonnet 5",
        blurb=(
            "The same obligation and the same tools.  This session finds the "
            "library's own lemma for the statement, imports it, and calls "
            "it.  The file type-checks; the judge counts it restated, not "
            "solved."),
    ),
    Choice(
        run=OPUS_RUN,
        subject="algebras-subalgebras-sub-trans-iso",
        model_label="Opus 5",
        blurb=(
            "A wholesale row, where the fixture names nothing useful.  Two "
            "queries answer `NotInScope`, and the second one's error carries "
            "the name that ends up in the proof."),
    ),
    Choice(
        run=SONNET_RUN,
        subject="stdlib-nat-mul-comm",
        model_label="Sonnet 5",
        blurb=(
            "Four turns, no query, a correct induction.  Agda exits 0 and the "
            "row is still not a solve: the session reached for `trans` by "
            "editing the fixture's own import line."),
    ),
    Choice(
        run=OPUS_RUN,
        subject="stdlib-nat-mul-comm",
        model_label="Opus 5",
        blurb=(
            "The same obligation, the same four turns, the same need for "
            "`trans`.  This session added an import line instead of editing "
            "one, which is what the preservation gate allows."),
    ),
)


def _sha256(text: str) -> str:
    """The digest a stale replay can be detected by, as `gen_proof` does."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def tag_value(tags: Sequence[str], prefix: str) -> Optional[str]:
    """The first `prefix:...` tag's value, or None."""
    for tag in tags:
        if tag.startswith(prefix + ":"):
            return tag[len(prefix) + 1:]
    return None


def tag_values(tags: Sequence[str], prefix: str) -> Tuple[str, ...]:
    """Every `prefix:...` tag's value, in order."""
    return tuple(tag[len(prefix) + 1:] for tag in tags
                 if tag.startswith(prefix + ":"))


def marked_diff(before: str, after: str) -> Tuple[Tuple[str, str], ...]:
    """The second file as a listing, each line marked against the first.

    `difflib.ndiff`'s hint lines (`? `) describe intra-line changes for a
    human reading a diff and would render as noise here, so they are dropped;
    every other line keeps its mark.
    """
    out: List[Tuple[str, str]] = []
    for line in difflib.ndiff(before.splitlines(), after.splitlines()):
        mark, _, text = line[0], line[1], line[2:]
        if mark == "?":
            continue
        out.append((mark if mark in "+-" else " ", text))
    return tuple(out)


def index_rows(index: Path) -> Result[Dict[str, Dict[str, Any]], PipelineError]:
    """The benchmark index, by obligation id."""

    def decode(text: str) -> Result[Dict[str, Dict[str, Any]], PipelineError]:
        rows: Dict[str, Dict[str, Any]] = {}
        for number, line in enumerate(text.splitlines(), start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                return Result.err(PipelineError(
                    ErrorType.PARSING_ERROR,
                    f"{index}: line {number} is not JSON", cause=exc))
            rows[str(row.get("id"))] = row
        return Result.ok(rows)

    return read_text(index).and_then(decode)


def _verdict(outcome: Dict[str, Any]) -> Dict[str, Any]:
    """The judge's fields, as the page reports them.

    Nothing here is recomputed: `outcome.json` is the archive's verdict, and
    the page's job is to print it, not to read the Agda and form an opinion.
    """
    return {
        "solved": bool(outcome.get("solved")),
        "restated": bool(outcome.get("restated")),
        "gate": outcome.get("gate"),
        "gateDetail": outcome.get("gateDetail"),
        "restatementEvidence": outcome.get("restatementEvidence") or [],
        "addedImports": outcome.get("addedImports") or [],
        "terminal": outcome.get("terminal"),
        "turns": outcome.get("turns"),
        "toolCalls": outcome.get("toolCallsTotal"),
        "perTool": outcome.get("toolCalls") or {},
        "wallMs": outcome.get("wallMs"),
        "costUsd": outcome.get("costUsd"),
        "agdaExit": outcome.get("agdaExit"),
        "checkExit": outcome.get("checkExit"),
        "statementEqual": bool((outcome.get("statement") or {}).get("equal")),
        "permissionDenials": outcome.get("permissionDenials"),
        "isolation": outcome.get("isolation") or {},
        "lastWords": outcome.get("lastWords"),
    }


def _outcome_label(verdict: Dict[str, Any]) -> Tuple[str, str]:
    """The verdict's short name and the one sentence the page prints with it.

    The sentence explains the archive's fields; it never adds a judgment of
    its own, and every name it uses is quoted from `outcome.json`.
    """
    if verdict["solved"]:
        return "solved", (
            "Every gate passed, and the definition does not refer to the "
            "library's own lemma for this statement, so the row counts as a "
            "solve.")
    if verdict["restated"]:
        evidence = ", ".join(f"`{item}`" for item
                             in verdict["restatementEvidence"])
        return "restated", (
            "Every gate passed, including the type-check.  The judge's "
            f"restatement evidence is {evidence}: the definition refers to "
            "the library's own lemma for this statement, so the row goes in "
            "the restated column and never into the solve count.")
    gate = verdict["gate"] or "a"
    detail = verdict["gateDetail"]
    return "gate", (
        f"Refused at the {gate} gate"
        + (f": {detail}." if detail else ".")
        + f"  Agda itself exited {verdict['agdaExit']} on this file.")


def build_replay(archive: Path, repo: Path, rows: Dict[str, Dict[str, Any]],
                 choice: Choice,
                 model: str) -> Result[Dict[str, Any], PipelineError]:
    """One replay's JSON, assembled from the subject's archived files.

    `model` is the arm's model id, which lives in the run's `report.json` and
    not in the subject's own files; the caller reads each report once and
    hands it down rather than opening it per subject.
    """
    subject_dir = archive / choice.run / "subjects" / choice.subject
    row = rows.get(choice.subject)
    if row is None:
        return Result.err(PipelineError(
            ErrorType.FILE_NOT_FOUND,
            f"{choice.subject} is not in the benchmark index"))

    def with_outcome(outcome: Dict[str, Any]) -> Result[Dict[str, Any], PipelineError]:
        final_name = Path(str(outcome.get("finalPath", ""))).name
        if not final_name:
            return Result.err(PipelineError(
                ErrorType.PARSING_ERROR,
                f"{choice.subject}: outcome.json has no finalPath"))
        return (load(subject_dir / "transcript.jsonl")
                .and_then(lambda records: load_json(subject_dir / "mcp.json")
                          .and_then(lambda mcp: read_session(records, mcp))
                          .map(lambda session: (records, session)))
                .and_then(lambda pair: _finish(
                    archive, repo, row, choice, model, outcome, final_name,
                    pair[0], pair[1])))

    return load_json(subject_dir / "outcome.json").and_then(with_outcome)


def _finish(archive: Path, repo: Path, row: Dict[str, Any], choice: Choice,
            model: str, outcome: Dict[str, Any], final_name: str,
            records: Sequence[Dict[str, Any]],
            session: Session) -> Result[Dict[str, Any], PipelineError]:
    """Assemble the replay once its transcript has been read."""
    subject_rel = f"reports/agent-bench/{choice.run}/subjects/{choice.subject}"
    subject_dir = archive / choice.run / "subjects" / choice.subject
    obligation_rel = str(row.get("obligation", ""))

    texts = {
        "obligation": read_text(repo / obligation_rel),
        "final": read_text(subject_dir / "final" / final_name),
        "prompt": read_text(subject_dir / "prompt.txt"),
        "transcript": read_text(subject_dir / "transcript.jsonl"),
    }
    for name, result in texts.items():
        if result.is_err:
            return Result.err(result.unwrap_err().with_context(
                subject=choice.subject, reading=name))

    obligation = texts["obligation"].unwrap()
    final = texts["final"].unwrap()
    verdict = _verdict(outcome)
    kind, sentence = _outcome_label(verdict)
    tags = [str(t) for t in (outcome.get("tags") or [])]

    replay = {
        "schema": REPLAY_SCHEMA,
        "id": f"{choice.run}--{choice.subject}",
        "run": choice.run,
        "subject": choice.subject,
        "model": model,
        "modelLabel": choice.model_label,
        "blurb": choice.blurb,
        "label": str(outcome.get("hole") or choice.subject),
        "obligation": {
            "hole": outcome.get("hole"),
            "goal": outcome.get("goal"),
            "statement": (outcome.get("statement") or {}).get("gold"),
            "difficulty": outcome.get("difficulty"),
            "stratum": outcome.get("stratum"),
            "library": outcome.get("source"),
            "module": row.get("module"),
            "restates": tag_value(tags, "restates"),
            "targets": list(tag_values(tags, "target")),
            "path": obligation_rel,
            "text": obligation,
        },
        "prompt": texts["prompt"].unwrap().strip(),
        "session": {
            "tools": list(session.tools),
            "serverStatus": session.server_status,
            "steps": [step.as_dict() for step in session.steps],
            "totals": session.totals,
        },
        "verdict": {**verdict, "kind": kind, "sentence": sentence},
        "final": {
            "path": f"{subject_rel}/final/{final_name}",
            "text": final,
            "marked": [list(pair) for pair in marked_diff(obligation, final)],
        },
        "provenance": {
            "transcript": f"{subject_rel}/transcript.jsonl",
            "transcriptSha256": _sha256(texts["transcript"].unwrap()),
            "transcriptRecords": len(records),
            "outcome": f"{subject_rel}/outcome.json",
            "report": f"reports/agent-bench/{choice.run}/report.json",
            "command": "make demo-data",
        },
    }
    # One normalization pass over the whole assembled value, not only over the
    # transcript: `outcome.json` carries the machine's paths too (a refused
    # Read names the library source it reached for), and a rule applied in one
    # place cannot be the rule somebody forgot to apply in another.
    normalized = normalize_value(replay, session.pmap)
    encoded = json.dumps(normalized, ensure_ascii=False)
    return check_clean(encoded).map(lambda _: normalized)
