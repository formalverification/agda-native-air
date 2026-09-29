#!/usr/bin/env python3
"""
File: scripts/python/demo/replays.py

Description: The sessions the demo page replays, and how one is assembled from
  the committed archive (Issue #85).

  `ROSTER` names them.  They are not a sample: each is one half of a contrast
  the archive already holds, and the page exists to show the contrast.  They
  come from the header-free arms of Issue #219 (`suite219-sonnet5-mcp-1` and
  `suite219-opus5-mcp-1`), chosen by the criteria the first roster was: a row
  one model solves and the other restates, a wholesale row, and the
  preservation gate, which recurred.

    +  `algebras-homs-mon-to-hom`, both arms.  The same obligation, the same
       fourteen tools, two verdicts.  Both find the library's `mon→hom`;
       Sonnet 5 cites it (`mon→hom′ m = mon→hom _ _ m`), which the judge puts
       in the restated column, and Opus 5 writes the pair out,
       `Data.Product._,_ _ (IsMon.isHom (proj₂ m))`, after a first probe with
       an unimported `_,_` came back a type error.  Both seeds of the first
       Opus arm, with the header's hints in view, restated this row.
    +  `algebras-subalgebras-sub-reflexive`, Opus 5.  A wholesale row, whose
       fixture names nothing useful: `get_goal`, a `definition_of` of `_≤_`
       and a Read of the file it named, then the first `search_in_scope` call
       in any archived arm, which answered with the one in-scope row, `𝒾𝒹`;
       one probe, one edit, one check.
    +  `stdlib-nat-mul-comm`, both arms.  Both models needed `trans`; Opus
       added an import line and was counted a solve, Sonnet appended `; trans`
       to the fixture's own `using` list and failed the preservation gate with
       a file that type-checks, as it had in the first Sonnet arm.

  `COMPOSITION` names the three sessions of the composition tier (Issue
  #224), from its `mcp` arms (Issue #160).  That tier sits at both models'
  ceiling (every final file of every arm checks), so no session is chosen
  as a row one configuration proves and another cannot; there is none.
  They are chosen for what the tier alone shows, as follows:

    +  `comp-group-normal-of-smaller-congruence`, Sonnet 5.  The gold's
       route: one `exports_of` lists both needles, and the middle point
       shows itself, since the first file, both arguments written, leaves
       the root lemma's implicit arguments unsolved until the session names
       them as the gold does.
    +  The same row, Opus 5.  No needle: the goal as `get_goal` prints it is
       unfolded, a `Read` shows `normalOf-mono`, and the proof is written
       pointwise, `λ p → φ≤N (θ⊆φ p)`.
    +  `comp-lattice-below-join-bound`, Sonnet 5.  A file that checks and
       lost a gate: the gold's own proof, with the needles appended to the
       fixture's `using` list, which the preservation gate refuses.

  A composition row restates nothing, so its verdict's `original` is null
  and the page reads each needle's provenance instead (`needles`).

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
     session changed instead of asserting it.  Comment lines are never
     marked: the judge strips comments before its one textual gate, and a
     fixture's header can change after a run (issue #219 removed the hint
     lines from every header), which is nothing the session did.
"""

from __future__ import annotations

import difflib
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from scripts.python.demo import needles
from scripts.python.demo.numbers import (
    COMP_OPUS_MCP_RUN,
    COMP_SONNET_MCP_RUN,
    OPUS_RUN,
    SONNET_RUN,
)
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

#: The shape of a replay file.  v1 (Issue #215) added the verdict's
#: `original` reading; v2 (Issue #224) added the obligation's needles and
#: where each came from.  `build_site` refuses a file of any other shape.
REPLAY_SCHEMA = "agda-native-air.demo.replay.v2"


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
        subject="algebras-homs-mon-to-hom",
        model_label="Opus 5",
        blurb=(
            "A search finds the library's own lemma, and this session writes "
            "the proof out instead of citing it: a first probe with `_,_`, "
            "which the file does not import, comes back a type error, and the "
            "constructor named in full is accepted."),
    ),
    Choice(
        run=SONNET_RUN,
        subject="algebras-homs-mon-to-hom",
        model_label="Sonnet 5",
        blurb=(
            "The same obligation and the same tools.  Two `exports_of` "
            "queries find `mon→hom`, and the session calls it.  The file "
            "type-checks; the judge counts it restated, not solved."),
    ),
    Choice(
        run=OPUS_RUN,
        subject="algebras-subalgebras-sub-reflexive",
        model_label="Opus 5",
        blurb=(
            "A wholesale row, where the fixture names nothing useful.  The "
            "session reads the definition of `_≤_` where `definition_of` "
            "points, and asks `search_in_scope` for the identity "
            "homomorphism: one row in scope, and it is the one the proof "
            "uses."),
    ),
    Choice(
        run=SONNET_RUN,
        subject="stdlib-nat-mul-comm",
        model_label="Sonnet 5",
        blurb=(
            "A correct induction, and Agda exits 0, and the row is still not "
            "a solve: the session reached for `trans` by editing the "
            "fixture's own import line."),
    ),
    Choice(
        run=OPUS_RUN,
        subject="stdlib-nat-mul-comm",
        model_label="Opus 5",
        blurb=(
            "The same obligation and the same need for `trans`, in four "
            "turns.  This session added an import line instead of editing "
            "one, which is what the preservation gate allows."),
    ),
)


#: The composition tier's replays, in tab order: one row by both models,
#: whose routes differ, then the shortest session that lost a gate.
COMPOSITION: Tuple[Choice, ...] = (
    Choice(
        run=COMP_SONNET_MCP_RUN,
        subject="comp-group-normal-of-smaller-congruence",
        model_label="Sonnet 5",
        blurb=(
            "The gold's route.  One `exports_of` on the module the fixture "
            "opens lists both needles.  The first file writes both "
            "arguments of `≤ⁿ-trans` and still comes back with unsolved "
            "metas at it: `_≤ⁿ_` unfolds to a function space, which fixes "
            "no normal subgroup.  With the three it relates named, as the "
            "gold names them, the file checks."),
    ),
    Choice(
        run=COMP_OPUS_MCP_RUN,
        subject="comp-group-normal-of-smaller-congruence",
        model_label="Opus 5",
        blurb=(
            "The same row, and no needle in the proof.  `get_goal` prints "
            "the goal unfolded, a membership to a membership; a Read of the "
            "file `definition_of` located has `normalOf-mono` in it; and "
            "the session writes `λ p → φ≤N (θ⊆φ p)`, probes it with "
            "`fill_hole`, and checks it."),
    ),
    Choice(
        run=COMP_SONNET_MCP_RUN,
        subject="comp-lattice-below-join-bound",
        model_label="Sonnet 5",
        blurb=(
            "A file that checks and is not a solve.  One `exports_of` lists "
            "both needles and the session writes the gold's proof, "
            "`≤-trans x≤y∨z (∨-least y≤w z≤w)`, supplying the middle point "
            "through the second needle's conclusion.  To bring the two "
            "into scope it appended them to the fixture's own `using` "
            "list, and the preservation gate refused the file.  `≤-trans` "
            "is the root lemma the loop reached for on this row, and "
            "`fill_hole` refused it with holes for its arguments."),
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


def _is_comment(line: str) -> bool:
    """A `--` line comment, the only comment form a fixture header uses."""
    return line.lstrip().startswith("--")


def marked_diff(before: str, after: str) -> Tuple[Tuple[str, str], ...]:
    """The second file as a listing, each line marked against the first.

    The marks come from `difflib.ndiff` over the two files' code lines, with
    comment lines (`-- …`) left out of the comparison and shown unmarked
    where the second file has them: the judge strips comments before its
    textual gate, and a fixture's header can change after a run (issue #219
    removed the hint lines from every header), which is nothing the session
    did.  `ndiff`'s hint lines (`? `) describe intra-line changes for a human
    reading a diff and would render as noise here, so they are dropped.
    """
    code_before = [l for l in before.splitlines() if not _is_comment(l)]
    code_after = [l for l in after.splitlines() if not _is_comment(l)]
    marks = [(line[0], line[2:]) for line in difflib.ndiff(code_before, code_after) if line[0] != "?"]
    out: List[Tuple[str, str]] = []
    i = 0
    for line in after.splitlines():
        if _is_comment(line):
            out.append((" ", line))
            continue
        # A code line of the second file is the next "+" or " " mark; the
        # "-" marks before it are lines of the first file gone from here.
        while marks[i][0] == "-":
            out.append(marks[i]); i += 1
        mark, text = marks[i]; i += 1
        out.append((mark if mark == "+" else " ", text))
    out.extend(marks[i:])
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
        # The judge's reading of whether the library's own proof of the
        # lemma this row restates was in view before the last edit (Issue
        # #188), `null` on a row with no original.  Reported, never gated.
        # Its `file` is an absolute store path until the one normalization
        # pass below; the page prints the original's name, not the file.
        "original": outcome.get("original"),
    }


def _outcome_label(verdict: Dict[str, Any],
                   restates: Optional[str]) -> Tuple[str, str]:
    """The verdict's short name and the one sentence the page prints with it.

    The sentence explains the archive's fields; it never adds a judgment of
    its own, and every name it uses is quoted from `outcome.json`.  On a row
    whose index entry names no original (no `restates:` tag: every
    composition row, and every standard-library row) the judge looks for no
    citation, so the sentence claims none was absent.
    """
    if verdict["solved"] and restates is None:
        return "solved", (
            "Every gate passed, so the row counts as a solve.  Its index "
            "entry names no library original, so the judge looks for no "
            "citation of one.")
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
    tags = [str(t) for t in (outcome.get("tags") or [])]
    verdict = _verdict(outcome)
    kind, sentence = _outcome_label(verdict, tag_value(tags, "restates"))
    row_needles = needles.needles_of(tags)

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
            "needles": list(row_needles),
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
        # Where each needle came from, by `needles`' rule; empty on a row
        # with no needle, which is every row of the mined suite.
        "needles": [found.as_dict() for found
                    in needles.sources(records, row_needles, final)],
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
