#!/usr/bin/env python3
"""
File: scripts/python/demo/transcript.py

Description: Read one archived `claude -p` transcript into the steps the demo
  page replays (Issue #85).

  A transcript under `reports/agent-bench/<run>/subjects/<id>/` is JSON Lines
  and is not all conversation.  `jq -r .type` over one file gives `system`
  records (an `init` record naming the tools and the working directory, and a
  stream of `thinking_tokens` estimates), `assistant` records, `user` records,
  `rate_limit_event` records, and one `result` record.

## What is kept, and what is dropped

  Kept, in the order the assistant produced them:

    +  every `text` block of an `assistant` record: the model's own words;
    +  every `thinking` block, as a marker only (see below);
    +  every `tool_use` block, with its arguments and with the matching
       `tool_result` attached as its answer.

  Dropped:

    +  `rate_limit_event` records, which describe the account's usage window
       and not the session;
    +  the `init` record's body, beyond the two facts the page states (the
       tools presented, and the server's connection status) and the working
       directory, which `paths.PathMap` needs as an anchor;
    +  the `result` record's body, beyond the run totals (turns, cost, wall),
       which `outcome.json` states anyway and which the page takes from there.

## Thinking blocks

  The archive holds no thinking *text*.  Every one of the 289 `thinking`
  blocks across the 170 archived transcripts carries `"thinking": ""` and a
  signature; the client's `stream-json` output does not emit the reasoning.
  What it does emit is a running estimate, in the `system`/`thinking_tokens`
  records that stream while the model thinks and reset at each new block.  So
  a thinking step here carries that estimate and nothing else, and the page
  labels it as an estimate of a passage it does not have.  Inventing a
  paraphrase and presenting it as the model's reasoning is the one thing this
  module must never do.

## Answers

  A tool answer is long: a `get_goal` reply is a full context dump and a
  `search_by_name` reply is a list of corpus rows.  Each step therefore
  carries both the whole body, normalized, and a `headline`: a short list of
  `(field path, value)` pairs read straight out of the body by
  `HEADLINE_FIELDS`.  A headline entry is a quotation of a named field, never
  a summary of one, and the whole body always travels with it, so an
  abbreviation can never hide a `type_error` or a failed verdict.

Design Principles:
  +  Pure over parsed records.  `steps_of` takes the decoded record list and
     returns immutable values; only `load` touches the filesystem.
  +  Two passes, because answers arrive after calls.  Results are collected by
     `tool_use_id` first, then the assistant's blocks are walked in order and
     each call is handed its own answer.
  +  Declarative headlines.  `HEADLINE_FIELDS` is an ordered list of dotted
     paths, not a table of per-tool rules, so a tool whose answer carries a
     `status` or an `error.code` gets a headline without a code change.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from scripts.python.demo.paths import PathMap, normalize_text, normalize_value
from scripts.python.utils.file_ops import read_text
from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
)

#: The prefix the client gives a tool served by an MCP server, and the server
#: name the agent-bench protocol used.
MCP_PREFIX = "mcp__agda__"

#: Scalar fields worth putting in a headline, as dotted paths, in the order
#: they are shown.  Every one is a field name from an `agda-mcp` answer or a
#: `tool_result` envelope; a body that has none falls back to its first line.
HEADLINE_FIELDS: Tuple[str, ...] = (
    "status",
    "success",
    "error.code",
    "inScope",
    "type",
    "goal",
    "normalForm",
    "remainingHoles",
    "holesCount",
    "diagnosticsTotal",
    "verdict.exitCode",
    "elapsedMs",
)

#: List-valued fields reported as a count rather than a value.
HEADLINE_COUNTS: Tuple[str, ...] = (
    "context",
    "exports",
    "modules",
    "definitions",
    "candidates",
    "dependencies",
    "neighbors",
    "diagnostics",
    "holes",
)

#: How much of a plain-text answer the headline may quote.  The whole body is
#: always carried beside it, so this truncates a preview and never the record.
HEADLINE_TEXT_CHARS = 120


@dataclass(frozen=True)
class Answer:
    """One `tool_result`, as the page shows it."""

    is_error: bool
    body: str
    is_json: bool
    headline: Tuple[Tuple[str, str], ...]

    def as_dict(self) -> Dict[str, Any]:
        return {
            "isError": self.is_error,
            "body": self.body,
            "isJson": self.is_json,
            "headline": [list(pair) for pair in self.headline],
        }


@dataclass(frozen=True)
class Step:
    """One beat of the replay: the model's words, a thought, or a call."""

    kind: str                                   # "text" | "thinking" | "call"
    text: str = ""
    tokens: Optional[int] = None
    tool: str = ""
    args: Tuple[Tuple[str, str], ...] = ()
    in_turn: int = 1            # how many calls the model issued in this turn
    answer: Optional[Answer] = None

    def as_dict(self) -> Dict[str, Any]:
        out: Dict[str, Any] = {"kind": self.kind}
        if self.kind == "text":
            out["text"] = self.text
        elif self.kind == "thinking":
            out["tokens"] = self.tokens
        else:
            out["tool"] = self.tool
            out["server"] = self.tool.startswith(MCP_PREFIX)
            out["display"] = display_name(self.tool)
            out["args"] = [list(pair) for pair in self.args]
            out["inTurn"] = self.in_turn
            out["answer"] = self.answer.as_dict() if self.answer else None
        return out


@dataclass(frozen=True)
class Session:
    """One transcript, read: its steps and the two facts the init record has."""

    steps: Tuple[Step, ...]
    tools: Tuple[str, ...]
    server_status: str
    pmap: PathMap
    totals: Dict[str, Any] = field(default_factory=dict)


def display_name(tool: str) -> str:
    """`mcp__agda__type_of` reads as `type_of`; `Read` reads as `Read`."""
    return tool[len(MCP_PREFIX):] if tool.startswith(MCP_PREFIX) else tool


def load(path: Path) -> Result[List[Dict[str, Any]], PipelineError]:
    """Decode one JSON Lines transcript into its records."""

    def decode(text: str) -> Result[List[Dict[str, Any]], PipelineError]:
        records: List[Dict[str, Any]] = []
        for number, line in enumerate(text.splitlines(), start=1):
            if not line.strip():
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as exc:
                return Result.err(PipelineError(
                    ErrorType.PARSING_ERROR,
                    f"{path}: line {number} is not JSON", cause=exc))
        if not records:
            return Result.err(PipelineError(
                ErrorType.PARSING_ERROR, f"{path}: no records"))
        return Result.ok(records)

    return read_text(path).and_then(decode)


def init_record(records: Sequence[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """The `system`/`init` record, which opens a well-formed transcript."""
    for record in records:
        if record.get("type") == "system" and record.get("subtype") == "init":
            return record
    return None


def result_record(records: Sequence[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """The single `result` record, which closes a session that finished."""
    for record in records:
        if record.get("type") == "result":
            return record
    return None


def _blocks(record: Dict[str, Any]) -> List[Dict[str, Any]]:
    """The content blocks of an `assistant` or `user` record, if any."""
    message = record.get("message")
    if not isinstance(message, dict):
        return []
    content = message.get("content")
    if not isinstance(content, list):
        return []
    return [block for block in content if isinstance(block, dict)]


def _result_text(block: Dict[str, Any]) -> str:
    """The text of a `tool_result`, whose content is a string or a block list."""
    content = block.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(part.get("text", "")
                       for part in content if isinstance(part, dict))
    return ""


def _dotted(body: Dict[str, Any], path: str) -> Any:
    """`body["a"]["b"]` for the dotted path `a.b`, or None if absent."""
    node: Any = body
    for segment in path.split("."):
        if not isinstance(node, dict) or segment not in node:
            return None
        node = node[segment]
    return node


def _scalar(value: Any) -> str:
    """One headline value, as the page prints it."""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def headline_of(body_text: str) -> Tuple[bool, Tuple[Tuple[str, str], ...]]:
    """The `(is_json, headline)` pair for one answer body.

    An object body is read by `HEADLINE_FIELDS` and `HEADLINE_COUNTS`; an
    array body reports its length, which is what a search answer is; anything
    else quotes its first line, truncated, with the whole body kept beside it.
    """
    try:
        body = json.loads(body_text)
    except (json.JSONDecodeError, ValueError):
        return False, _text_headline(body_text)

    if isinstance(body, list):
        return True, (("results", str(len(body))),)
    if not isinstance(body, dict):
        return True, (("value", _scalar(body)),)

    pairs: List[Tuple[str, str]] = []
    for path in HEADLINE_FIELDS:
        value = _dotted(body, path)
        if value is None or isinstance(value, (list, dict)):
            continue
        pairs.append((path, _scalar(value)))
    for name in HEADLINE_COUNTS:
        value = body.get(name)
        if isinstance(value, list):
            pairs.append((name, str(len(value))))
    if not pairs:
        return True, _text_headline(body_text)
    return True, tuple(pairs)


def _text_headline(body_text: str) -> Tuple[Tuple[str, str], ...]:
    """A plain answer's first line, truncated for the preview."""
    first = body_text.strip().splitlines()[0] if body_text.strip() else ""
    if len(first) > HEADLINE_TEXT_CHARS:
        first = first[:HEADLINE_TEXT_CHARS].rstrip() + "…"
    return (("", first),) if first else ()


def answers_of(records: Sequence[Dict[str, Any]],
               pmap: PathMap) -> Dict[str, Answer]:
    """Every `tool_result` in the transcript, by the id of the call it answers.

    Answers arrive in `user` records after the calls that provoked them, and a
    turn issuing two calls is answered by one record carrying two results, so
    they are collected first and handed to their calls in the second pass.
    """
    out: Dict[str, Answer] = {}
    for record in records:
        if record.get("type") != "user":
            continue
        for block in _blocks(record):
            if block.get("type") != "tool_result":
                continue
            call_id = block.get("tool_use_id")
            if not isinstance(call_id, str):
                continue
            body = normalize_text(_result_text(block), pmap)
            is_json, headline = headline_of(body)
            out[call_id] = Answer(
                is_error=bool(block.get("is_error")),
                body=body,
                is_json=is_json,
                headline=headline,
            )
    return out


def thinking_runs(records: Sequence[Dict[str, Any]]) -> Tuple[int, ...]:
    """The estimated size of each thinking passage, in stream order.

    The client streams `system`/`thinking_tokens` records while the model
    thinks: `estimated_tokens` climbs within one passage and drops back when
    the next begins.  So a maximal ascending run is one passage, and its last
    value is that passage's estimate.
    """
    runs: List[int] = []
    previous: Optional[int] = None
    for record in records:
        if record.get("subtype") != "thinking_tokens":
            continue
        estimate = record.get("estimated_tokens")
        if not isinstance(estimate, int):
            continue
        if previous is None or estimate <= previous:
            runs.append(estimate)
        else:
            runs[-1] = estimate
        previous = estimate
    return tuple(runs)


def turn_index(records: Sequence[Dict[str, Any]]) -> List[int]:
    """The turn each record belongs to, by position.

    A turn is one exchange: everything the assistant emits before the tool
    answers come back.  The client emits one record per content block, so a
    turn that issues two calls is three `assistant` records and not one; what
    ends a turn is the `user` record carrying the answers.  `system` records
    (the thinking-token estimates) stream through the middle of a turn and do
    not end it.
    """
    turns: List[int] = []
    turn = 0
    opened = False
    for record in records:
        kind = record.get("type")
        if kind == "assistant":
            if not opened:
                turn += 1
                opened = True
        elif kind in ("user", "result"):
            opened = False
        turns.append(turn)
    return turns


def steps_of(records: Sequence[Dict[str, Any]],
             pmap: PathMap) -> Tuple[Step, ...]:
    """The replay's beats, in the order the assistant produced them."""
    answers = answers_of(records, pmap)
    # The estimate stream and the thinking blocks are two independent parts of
    # the same output, so they are only attributable to each other when they
    # agree on how many passages there were.  If they do not, the page says a
    # passage happened and no more; a number attached to the wrong passage
    # would be worse than no number.
    thinking = thinking_runs(records)
    blocks_thinking = sum(
        1 for record in records if record.get("type") == "assistant"
        for block in _blocks(record) if block.get("type") == "thinking")
    estimates = thinking if len(thinking) == blocks_thinking else ()

    turns = turn_index(records)
    calls_per_turn: Dict[int, int] = {}
    for position, record in enumerate(records):
        if record.get("type") != "assistant":
            continue
        for block in _blocks(record):
            if block.get("type") == "tool_use":
                at = turns[position]
                calls_per_turn[at] = calls_per_turn.get(at, 0) + 1

    thought = 0
    steps: List[Step] = []
    for position, record in enumerate(records):
        if record.get("type") != "assistant":
            continue
        for block in _blocks(record):
            kind = block.get("type")
            if kind == "text":
                text = (block.get("text") or "").strip()
                if text:
                    steps.append(Step(kind="text",
                                      text=normalize_text(text, pmap)))
            elif kind == "thinking":
                tokens = (estimates[thought]
                          if thought < len(estimates) else None)
                thought += 1
                steps.append(Step(kind="thinking", tokens=tokens))
            elif kind == "tool_use":
                steps.append(Step(
                    kind="call",
                    tool=str(block.get("name") or ""),
                    args=_args_of(block.get("input"), pmap),
                    in_turn=calls_per_turn.get(turns[position], 1),
                    answer=answers.get(str(block.get("id"))),
                ))
    return tuple(steps)


def _args_of(raw: Any, pmap: PathMap) -> Tuple[Tuple[str, str], ...]:
    """A call's arguments, normalized, as ordered name/value pairs.

    Values keep their JSON shape only when they are not strings: a string
    argument is an Agda expression or a path and reads better bare than
    quoted, while a number or a boolean would be ambiguous unquoted.
    """
    if not isinstance(raw, dict):
        return ()
    pairs: List[Tuple[str, str]] = []
    for name, value in raw.items():
        shown = normalize_value(value, pmap)
        pairs.append((str(name), shown if isinstance(shown, str)
                      else json.dumps(shown, ensure_ascii=False)))
    return tuple(pairs)


def totals_of(records: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    """The run totals of the closing `result` record, if it is there."""
    record = result_record(records)
    if record is None:
        return {}
    usage = record.get("usage") or {}
    details = usage.get("output_tokens_details") or {}
    return {
        "turns": record.get("num_turns"),
        "costUsd": record.get("total_cost_usd"),
        "wallMs": record.get("duration_ms"),
        "terminal": record.get("terminal_reason"),
        "thinkingTokens": details.get("thinking_tokens"),
    }


def read_session(records: Sequence[Dict[str, Any]],
                 mcp_config: Dict[str, Any]) -> Result[Session, PipelineError]:
    """One transcript, read into the page's shape."""
    init = init_record(records)
    if init is None:
        return Result.err(PipelineError(
            ErrorType.PARSING_ERROR,
            "the transcript has no system/init record"))

    def build(pmap: PathMap) -> Result[Session, PipelineError]:
        servers = init.get("mcp_servers") or []
        status = next((s.get("status", "unknown") for s in servers
                       if isinstance(s, dict) and s.get("name") == "agda"),
                      "absent")
        tools = tuple(str(t) for t in (init.get("tools") or []))
        return Result.ok(Session(
            steps=steps_of(records, pmap),
            tools=tools,
            server_status=str(status),
            pmap=pmap,
            totals=totals_of(records),
        ))

    return PathMap.of(mcp_config, init).and_then(build)
