#!/usr/bin/env python3
"""
File: scripts/python/demo/needles.py

Description: Where each needle of a composition row came from, and whether
  the file the judge read uses it (Issue #224).

  A composition row (Issue #160) has no library original to restate.  Its
  gold strings two to four library lemmas together, the row's *needles*,
  one `needle:` tag each in the benchmark index, so the question the judge's
  `original` reading answers on a mined row (was the original's proof in
  view?) has no subject here, and its place is taken by this one: for each
  needle, which event of the session first named it.

  The rule is the one `needle-source.py` states (the
  `running-proof-search-sweeps` skill), which the guide's § 4.7 and ADR 0001
  § 9 were written from, ported rather than paraphrased so the page and the
  write-up cannot disagree:

    +  A session is read as a sequence of events in transcript order: the
       model's visible text, each call's arguments (as JSON), and each call's
       answer.
    +  A needle is named by an event when its last dotted component occurs
       in the event's text bounded by Agda's delimiters (`DELIMITERS`), so
       `GroupCongruences.≤ⁿ-trans` is found as `≤ⁿ-trans` and `≤-refl` is
       not taken for `≤-trans`.
    +  The first such event decides: an answer means the needle came from
       that answer (`answer`); the model's own text or call means the
       session named it before any answer had (`subject`, with whether a
       search call of some kind came before); no event means `never`.
    +  The final file *uses* a needle when the same pattern occurs in it,
       and a row is on the gold's whole route when its final file uses
       every needle.

  One reading the skill does not make is added: whether a needle first
  shown by a `Read` was in a file that an earlier `definition_of` answer
  had named (`located`), which is what the guide's § 4.7 says the server
  arms' reads mostly were.

  `needle-source.py` calls the `subject` origin `memory`.  The page does
  not: the archive keeps no thinking text, and a name the model wrote
  before any answer showed it may have come from training or from a guess
  at a neighbor's name (the three such needles in the tier were each handed
  straight to `search_by_name`), which the transcript cannot tell apart.

Design Principles:
  +  Pure over decoded records: nothing here reads a file.
  +  Faithful before pretty.  Call arguments are matched as the skill
     matches them, in their JSON encoding, so the counts this module gives
     over the archive are the skill's, which `test_demo_needles.py` checks
     against the ADR's table and the guide's figures.
"""

from __future__ import annotations

import json
import os
import re
from collections import Counter
from dataclasses import dataclass
from typing import Any, Dict, List, Mapping, Optional, Pattern, Sequence, Tuple

#: The characters that may bound a name in Agda source: whitespace,
#: parentheses, braces, a dot of a qualified name, a semicolon of a `using`
#: list, quotation marks, backticks, brackets, and a comma.
DELIMITERS = r"\s(){}.;\"'`\[\],"

#: How the client names a tool served by the `agda` MCP server.
MCP_PREFIX = "mcp__agda__"

#: Calls that search, by the label `label` gives them: the server's search
#: and location tools, and the shell's searching programs.
SEARCHES = frozenset({
    "search_by_type", "search_by_name", "search_in_scope", "exports_of",
    "definition_of", "Bash:grep", "Bash:rg", "Bash:find", "Bash:ls"})

#: The origins a needle can have, in the order the page tabulates them.
ANSWER, SUBJECT, NEVER = "answer", "subject", "never"


def needles_of(tags: Sequence[str]) -> Tuple[str, ...]:
    """A row's needles, qualified, in the order its index entry lists them."""
    return tuple(tag[len("needle:"):] for tag in tags
                 if tag.startswith("needle:"))


def short_name(needle: str) -> str:
    """The needle's last dotted component, which is how a session writes it."""
    return needle if needle.endswith(".") else needle.split(".")[-1]


def _pattern(needle: str) -> Pattern[str]:
    name = re.escape(short_name(needle))
    return re.compile(rf"(?<![^{DELIMITERS}]){name}(?![^{DELIMITERS}])")


def mentions(needle: str, text: str) -> bool:
    """Whether `text` names the needle, bounded by Agda's delimiters."""
    return _pattern(needle).search(text) is not None


def label(name: str, arguments: Mapping[str, Any]) -> str:
    """A call as the skill labels it: the tool's bare name, and for Bash the
    program the command runs (after a leading `cd DIR &&`)."""
    bare = name.split("__")[-1]
    if bare != "Bash":
        return bare
    command = re.sub(r"^\s*cd\s+\S+\s*&&\s*", "",
                     str(arguments.get("command", ""))).strip().split()
    return "Bash:" + (os.path.basename(command[0]) if command else "?")


@dataclass(frozen=True)
class Event:
    """One thing a session said, asked, or was told, in transcript order.

    `call` is the 1-based position of the call among the session's calls,
    for a call and for its answer, and None for the model's text;
    `searched` is whether a search call had been made before this event.
    A call's `text` is its arguments as JSON, which is how the skill reads
    them, and its `path` the file a `Read` names, or "".
    """

    kind: str                   # "said" | "call" | "answer"
    tool: str                   # the raw tool name, "" for text
    label: str
    text: str
    call: Optional[int]
    searched: bool
    path: str = ""


def _blocks(record: Mapping[str, Any]) -> List[Mapping[str, Any]]:
    message = record.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    return [b for b in content if isinstance(b, dict)] \
        if isinstance(content, list) else []


def _result_text(block: Mapping[str, Any]) -> str:
    content = block.get("content")
    if isinstance(content, str):
        return content
    return "".join(part.get("text", "") for part in content or []
                   if isinstance(part, dict))


def events_of(records: Sequence[Mapping[str, Any]]) -> Tuple[Event, ...]:
    """Every event of a transcript, in order."""
    events: List[Event] = []
    calls: Dict[str, Tuple[str, str, int]] = {}
    searched = False
    for record in records:
        kind = record.get("type")
        for block in _blocks(record):
            if kind == "assistant" and block.get("type") == "text":
                events.append(Event("said", "", "text",
                                    str(block.get("text", "")), None,
                                    searched))
            elif kind == "assistant" and block.get("type") == "tool_use":
                name = str(block.get("name") or "")
                arguments = block.get("input") or {}
                at = len(calls) + 1
                named = label(name, arguments if isinstance(arguments, dict)
                              else {})
                calls[str(block.get("id"))] = (name, named, at)
                path = (arguments.get("file_path", "")
                        if isinstance(arguments, dict) else "")
                events.append(Event("call", name, named,
                                    json.dumps(arguments, ensure_ascii=False),
                                    at, searched, str(path or "")))
                searched = searched or named in SEARCHES
            elif kind == "user" and block.get("type") == "tool_result":
                name, named, at = calls.get(str(block.get("tool_use_id")),
                                            ("", "?", 0))
                events.append(Event("answer", name, named,
                                    _result_text(block), at or None,
                                    searched))
    return tuple(events)


@dataclass(frozen=True)
class Source:
    """Where one needle came from in one session, and whether it stayed."""

    needle: str
    name: str
    origin: str                 # ANSWER | SUBJECT | NEVER
    tool: str                   # the raw tool name of the deciding event
    label: str
    call: Optional[int]
    searched: bool
    used: bool
    located: bool = False

    def as_dict(self) -> Dict[str, Any]:
        return {
            "needle": self.needle,
            "name": self.name,
            "origin": self.origin,
            "tool": self.tool,
            "label": self.label,
            "call": self.call,
            "searched": self.searched,
            "used": self.used,
            "located": self.located,
        }


def located(call: Optional[int], events: Sequence[Event]) -> bool:
    """Whether the `Read` that is call `call` read a file that an earlier
    `definition_of` answer had named."""
    read = next((e for e in events if e.kind == "call" and e.call == call
                 and e.tool == "Read"), None)
    if read is None or not read.path:
        return False
    return any(e.kind == "answer" and e.label == "definition_of"
               and e.call is not None and e.call < read.call
               and read.path in e.text for e in events)


def source(needle: str, events: Sequence[Event], final: str) -> Source:
    """Where one needle came from: the first event that names it."""
    pattern = _pattern(needle)
    first = next((event for event in events if pattern.search(event.text)),
                 None)
    used = pattern.search(final) is not None
    if first is None:
        return Source(needle, short_name(needle), NEVER, "", "", None,
                      False, used)
    origin = ANSWER if first.kind == "answer" else SUBJECT
    return Source(needle, short_name(needle), origin, first.tool,
                  first.label, first.call, first.searched, used,
                  origin == ANSWER and located(first.call, events))


def sources(records: Sequence[Mapping[str, Any]], needles: Sequence[str],
            final: str) -> Tuple[Source, ...]:
    """Every needle of a row, traced through one session."""
    events = events_of(records)
    return tuple(source(needle, events, final) for needle in needles)


def group(found: Source) -> str:
    """The row of the page's provenance table a needle's origin falls in."""
    if found.origin != ANSWER:
        return found.origin
    if found.tool.startswith(MCP_PREFIX):
        return "server"
    if found.tool == "Read":
        return "read"
    if found.tool == "Bash":
        return "shell"
    return "other"


#: The provenance table's rows, in order, and how the page heads each.
GROUPS: Tuple[Tuple[str, str], ...] = (
    ("server", "an answer of the server’s tools"),
    ("read", "a Read of a file"),
    ("shell", "a shell command’s output"),
    ("other", "another tool’s answer"),
    (SUBJECT, "the session’s own words or call, before any answer"),
    (NEVER, "never named in the session"),
)


def tally(found: Sequence[Source]) -> Dict[str, Any]:
    """One arm's provenance over every needle of its rows: how many the
    final files use, how many first appeared in each group, and by which
    call; `located` counts the reads of a file a `definition_of` answer had
    named first.  The rows on the gold's whole route are the caller's to
    count, since they need the row boundaries this list has lost."""
    return {
        "needles": len(found),
        "used": sum(1 for s in found if s.used),
        "located": sum(1 for s in found if s.located),
        "byGroup": {name: sum(1 for s in found if group(s) == name)
                    for name, _ in GROUPS},
        "byLabel": dict(sorted(Counter(
            s.label for s in found if s.origin == ANSWER).items(),
            key=lambda pair: (-pair[1], pair[0]))),
    }
