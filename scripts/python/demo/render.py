#!/usr/bin/env python3
"""
File: scripts/python/demo/render.py

Description: Render the demo site's page from the data `make demo-data`
  wrote (Issues #85 and #215).

## What the page claims, and what it does not

  The sessions on the page come from the project's first agent measurement
  (Issue #154), in which every subject had the server and nothing else.  So
  they are evidence of what a frontier model does *with* the tools, and of
  nothing about whether the tools help: that is the control's question
  (Issue #162), which the numbers section sets beside them, read from its own
  reports and checked against ADR 0001 § 9 like the archived arms' table.
  Issue #215 brought
  the page's framing up to that record, under the following rules:

    +  The header carries no solve count.  It says what the page is (the
       sessions, their calls, the suite they come from), because a solve
       count needs its instrument, its run, and a caveat the header has no
       room for.  The loop's count is not there either: the loop is a
       different instrument with no model in it, and not the agents'
       baseline.
    +  No result of the archived arms stands anywhere without the
       control's beside it.  Every element that prints an arm's results (a
       solve, a restatement, a gate, an anomaly, a tool call) names the
       arm's run in `data-runs`; configuration (caps, dates, tool counts) is
       not marked.  `test_demo_render.py` checks the rule per section, and
       pins the attribute on every such element the page has: a new one
       needs it too, or the section check cannot see it.
    +  The restated rule is stated with its limit: it reads references, so it
       catches a proof that cites the library and not one that transcribes
       it.  What the judge's `original` reading (Issue #188) says about each
       session on the page is read from the session's own verdict.
    +  No figure is typed here.  Counts, caps, dates, tool counts, and the
       archive's size are all read from the data, and the few qualitative
       claims that rest on the record (which arm came out ahead, which arms
       could read the libraries) have their premises pinned by tests.

## The contract with the replay script

  This renderer emits every session in its *finished* state: every step
  present, every answer beside its call, the verdict stated, the file the
  judge read at the bottom.  A crawler, a reader with JavaScript off, and a
  reader with `prefers-reduced-motion` on all see complete sessions with
  `assets/replay.js` doing nothing.  The script only rewinds that state and
  types it back in; it invents no content and quotes nothing this file did
  not already put on the page.

  What the script finds, and what it may therefore assume:

    +  `.replay`, the player.  Inside it `.replay-tabs`, a tablist shipped
       `hidden` (without the script the buttons would switch nothing, and a
       control that does nothing should not exist), and one `.replay-panel`
       per session carrying `data-index`.
    +  Inside a panel, `.replay-stream` holding `.step` items in session
       order.  A step carries `data-kind` (`text`, `thinking`, or `call`);
       the parts that are *typed* carry `data-type-text`, and the parts
       that appear whole once the typing stops carry `data-after`.  That
       split is the honest one: the agent typed its words and its calls, and
       the server answered in one response, the way a compiler answers in
       whole lines.
    +  `.replay-again`, one control per panel, shipped `hidden` for the same
       reason as the tablist.  The script gives it two states: while a panel
       plays it stops the replay, and at rest it starts one.  The stop is
       not decoration: the first session starts on its own when the player
       scrolls into view, and the five run 6 to 25 seconds, which is exactly
       what WCAG 2.2.2 asks for a way to stop.

  Panels other than the first are shipped visible and are hidden by CSS only
  when the document element carries `has-js`, which a one-line script in the
  head sets before this markup is parsed.  A reader without JavaScript then
  gets all five sessions in document order rather than the first one and four
  dead tabs.

## The seam Issue #85 leaves for a live type-checker

  A "check it yourself" lane (`#103` on the site repository: Agda compiled to
  wasm) would attach to the panels without touching anything else: each one
  carries `data-obligation-path` and `data-final-path`, and its `.replay-file`
  block already holds the obligation and the file the judge read, as text.  A
  lane that wanted to re-check them in the browser has its input in the DOM
  and needs no new data file and no server.

Design Principles:
  +  Pure.  `page` takes decoded data and returns a string; nothing here
     reads or writes a file.
  +  Escape once, at the edge.  Every value reaching the HTML goes through
     `_esc`; the only unescaped strings are the literals in this file.
  +  Say where a number came from.  The page says which files its figures
     are read from; the two tables checked against ADR 0001 § 9 each name
     the ADR table they were checked against (the others have none to be
     checked against); and every element that prints an arm's results
     names the arm's run in `data-runs`.
"""

from __future__ import annotations

import re
from html import escape
from typing import (Any, Dict, Iterable, List, Mapping, Optional, Sequence,
                    Tuple)

#: The repository this page belongs to, for the links back to the evidence.
REPO_URL = "https://github.com/formalverification/agda-native-air"

#: The page's own title.  It names no tool count: thirteen was true of the
#: sessions it replays and is not true of the server since PR #161 added a
#: fourteenth, so a count here would be false of one or the other.
TITLE = "agda-native-air: an agent, Agda, and the tools between them"
HEADLINE = "An agent, Agda, and the tools between them"

#: The reader's guide to every number on this page, linked on GitHub until
#: the site publishes it (Issue #171).  Its sections are linked by their
#: headings, through GitHub's own rule for a heading's anchor, and
#: `test_demo_render.py` checks every heading named here against the guide.
GUIDE = "docs/reading-the-results.md"
GUIDE_SECTIONS: Dict[str, str] = {
    "1": "1.  The four instruments",
    "4.3": "4.3  The control, and the comparison",
    "4.5": "4.5  The hard tier",
    "5": "5.  How to tell a win from a loss",
}

#: The decision record both tables are checked against, and the two
#: subsections of its § 9 that hold them.
ADR = "docs/adr/0001-proof-search-on-agda-mcp.md"
ADR_SECTIONS: Dict[str, str] = {
    "agents": "The agent in the loop",
    "control": "The attribution arms: what the server is worth",
}

def _esc(value: Any) -> str:
    """Everything that reaches the HTML goes through here."""
    return escape("" if value is None else str(value), quote=True)


def _blob(path: str, label: str = "") -> str:
    """A link to a file of this repository on its default branch."""
    return (f'<a class="src" href="{REPO_URL}/blob/main/{_esc(path)}">'
            f'{_esc(label or path)}</a>')


def _tree(path: str, label: str = "") -> str:
    """A link to a directory.  GitHub serves those under `tree`, not `blob`."""
    return (f'<a class="src" href="{REPO_URL}/tree/main/{_esc(path)}">'
            f'{_esc(label or path)}</a>')


def anchor(heading: str) -> str:
    """The fragment GitHub gives a Markdown heading.

    Lower-cased, every character that is not a letter, a digit, a space, a
    hyphen, or an underscore dropped, and each space made a hyphen, so the
    two spaces after a section number become two hyphens.  Checked against
    every anchor GitHub rendered for the guide and for ADR 0001 (38 of 38)
    when Issue #215 was written.
    """
    return re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")


def _guide(section: str, label: str = "") -> str:
    """A link to one section of the guide, by its heading."""
    return (f'<a class="src" href="{REPO_URL}/blob/main/{GUIDE}#'
            f'{anchor(GUIDE_SECTIONS[section])}">'
            f'{_esc(label or "§ " + section)}</a>')


def _adr(section: str, label: str) -> str:
    """A link to one subsection of ADR 0001 § 9, by its heading."""
    return (f'<a class="src" href="{REPO_URL}/blob/main/{ADR}#'
            f'{anchor(ADR_SECTIONS[section])}">{_esc(label)}</a>')


def _issue(number: int) -> str:
    """A link to an issue of this repository, as `#N`."""
    return f'<a class="src" href="{REPO_URL}/issues/{number}">#{number}</a>'


def _plural(n: Any, one: str, many: str) -> str:
    return f"{n} {one}" if n == 1 else f"{n} {many}"


#: Counts the prose spells out; above twenty it writes digits.
_WORDS = ("zero", "one", "two", "three", "four", "five", "six", "seven",
          "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
          "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty")


def _word(n: Any) -> str:
    """A count as the prose writes it: a word up to twenty, digits above."""
    if not isinstance(n, int) or isinstance(n, bool):
        return "?"
    return _WORDS[n] if 0 <= n < len(_WORDS) else f"{n:,}"


def _num(n: Any) -> str:
    """A measured count, as digits: where the prose compares figures, digits
    are what a reader scans, and the guide writes them the same way."""
    if not isinstance(n, int) or isinstance(n, bool):
        return "?"
    return f"{n:,}"


def _count(n: Any, one: str, many: str) -> str:
    """A count and its noun, spelled out: "one row", "eleven rows"."""
    return f"{_word(n)} {one if n == 1 else many}"


def _times(n: int) -> str:
    return {1: "once", 2: "twice"}.get(n, f"{_word(n)} times")


def _money(value: Any) -> str:
    try:
        return f"USD {float(value):.2f}"
    except (TypeError, ValueError):
        return "USD ?"


def _seconds(ms: Any) -> str:
    try:
        return f"{float(ms) / 1000:.0f} s"
    except (TypeError, ValueError):
        return "?"


def _megabytes(size: Any) -> str:
    """Bytes of content, in decimal megabytes, as `du` would not count them."""
    try:
        return f"{float(size) / 1_000_000:.0f}&nbsp;MB"
    except (TypeError, ValueError):
        return "? MB"


def _runs(*ids: Any) -> str:
    """The `data-runs` attribute of an element that prints arms' figures."""
    return f' data-runs="{_esc(" ".join(str(i) for i in ids if i))}"'


# ----------------------------------------------------------------- steps

def _args(args: Sequence[Sequence[str]]) -> str:
    """A call's arguments, as the page prints them.

    The file path is dropped from the printed form of an `agda-mcp` call: it
    is the same one file in every call of a session, the panel states it
    once, and repeating it nine times would bury the argument that differs.
    The whole call is still in the answer's own body below it.
    """
    shown = [(name, value) for name, value in args
             if name not in ("filePath", "file_path")]
    parts = []
    for name, value in shown:
        text = value if len(value) <= 160 else value[:160] + "…"
        parts.append(f'<span class="arg"><span class="arg-name">'
                     f'{_esc(name)}</span>: <span class="arg-value">'
                     f'{_esc(text)}</span></span>')
    return '<span class="sep">, </span>'.join(parts)


def _headline(headline: Sequence[Sequence[str]]) -> str:
    """The named fields the answer is summarized by."""
    parts = []
    for pair in headline:
        name, value = (list(pair) + ["", ""])[:2]
        shown = value if len(value) <= 220 else value[:220] + "…"
        label = (f'<span class="field">{_esc(name)}</span>'
                 '<span class="sep">: </span>') if name else ""
        parts.append(f'<span class="pair">{label}'
                     f'<span class="value">{_esc(shown)}</span></span>')
    return "".join(parts) or '<span class="pair"><span class="value">' \
                             '(an empty answer)</span></span>'


def _answer(answer: Mapping[str, Any], index: str) -> str:
    """One tool answer: the named fields, and the whole body behind a control.

    The body is always here in full.  An abbreviation that hid a `type_error`
    or a failed verdict would be a lie, so the summary above it quotes named
    fields rather than describing them, and the control says how much is
    behind it.
    """
    body = str(answer.get("body", ""))
    state = "error" if answer.get("isError") else "ok"
    kind = "JSON" if answer.get("isJson") else "text"
    return (
        f'<div class="answer answer-{state}" data-after>'
        f'<div class="answer-who">'
        f'<span class="answer-badge">{"refused" if state == "error" else "answered"}</span>'
        f'</div>'
        f'<div class="answer-body">'
        f'<div class="answer-headline">{_headline(answer.get("headline") or [])}</div>'
        f'<details class="answer-full" id="answer-{_esc(index)}">'
        f'<summary>the whole answer, as the agent saw it '
        f'({len(body):,} characters of {kind})</summary>'
        f'<pre class="wide"><code>{_esc(body)}</code></pre>'
        f'</details>'
        f'</div></div>'
    )


def _step(step: Mapping[str, Any], panel: int, index: int) -> str:
    """One beat of the session."""
    kind = str(step.get("kind"))
    at = f"{panel}-{index}"

    if kind == "text":
        return (
            f'<li class="step" data-kind="text">'
            f'<div class="who who-model">the model</div>'
            f'<div class="said" data-type-text>{_esc(step.get("text"))}</div>'
            f'</li>')

    if kind == "thinking":
        tokens = step.get("tokens")
        estimate = (f'about {int(tokens):,} tokens by the client’s '
                    'running estimate' if isinstance(tokens, int)
                    else 'of unrecorded length')
        return (
            f'<li class="step step-thought" data-kind="thinking">'
            f'<div class="who who-thought">thought</div>'
            f'<div class="said thought">'
            f'<em>The model thought here, {estimate}.  The archive keeps the '
            f'block’s signature and not its text, so there is nothing to '
            f'quote and nothing is quoted.</em>'
            f'</div></li>')

    server = bool(step.get("server"))
    where = "agda-mcp" if server else "the work directory"
    answer = step.get("answer")
    at_once = int(step.get("inTurn") or 1)
    together = (f'<span class="together" data-after>one of {at_once} calls '
                f'the model issued in this turn</span>'
                if at_once > 1 else "")
    return (
        f'<li class="step step-call{" step-mcp" if server else ""}" '
        f'data-kind="call">'
        f'<div class="who who-call">{_esc(where)}</div>'
        f'<div class="said">'
        f'<div class="call" data-type-text>'
        f'<span class="call-tool">{_esc(step.get("display"))}</span>'
        f'<span class="sep">(</span>{_args(step.get("args") or [])}'
        f'<span class="sep">)</span></div>{together}'
        + (_answer(answer, at) if answer else
           '<div class="answer answer-error" data-after><div '
           'class="answer-body"><div class="answer-headline">(this call has '
           'no answer in the archive)</div></div></div>')
        + '</div></li>')


# ---------------------------------------------------------------- panels

_PIP = {"solved": "solved", "restated": "restated", "gate": "refused"}


def _facts(replay: Mapping[str, Any]) -> str:
    """The obligation's own row, as the benchmark index states it."""
    ob = replay.get("obligation") or {}
    verdict = replay.get("verdict") or {}
    items = [
        ("obligation", _blob(str(ob.get("path")), str(replay.get("subject")))),
        ("tier", _esc(ob.get("difficulty"))),
        ("stratum", _esc(ob.get("stratum"))),
        ("model", _esc(replay.get("model"))),
        ("turns", _esc(verdict.get("turns"))),
        ("tool calls", _esc(verdict.get("toolCalls"))),
        ("wall", _seconds(verdict.get("wallMs"))),
        ("cost, list price", _money(verdict.get("costUsd"))),
    ]
    if ob.get("restates"):
        items.insert(3, ("the library original",
                         f'<code>{_esc(ob["restates"])}</code>'))
    cells = "".join(f'<div class="fact"><dt>{name}</dt><dd>{value}</dd></div>'
                    for name, value in items)
    return f'<dl class="facts">{cells}</dl>'


def _verdict(replay: Mapping[str, Any]) -> str:
    """The archive's verdict, printed, never re-formed here."""
    verdict = replay.get("verdict") or {}
    kind = str(verdict.get("kind"))
    lines = [
        f'<span class="v-field">Agda’s exit code</span> '
        f'<span class="v-value">{_esc(verdict.get("agdaExit"))}</span>',
        f'<span class="v-field">statement preserved</span> '
        f'<span class="v-value">'
        f'{"yes" if verdict.get("statementEqual") else "no"}</span>',
        f'<span class="v-field">turns</span> '
        f'<span class="v-value">{_esc(verdict.get("turns"))}</span>',
    ]
    if verdict.get("addedImports"):
        added = "; ".join(str(line) for line in verdict["addedImports"])
        lines.append(f'<span class="v-field">import lines added</span> '
                     f'<span class="v-value"><code>{_esc(added)}</code>'
                     f'</span>')
    if verdict.get("restatementEvidence"):
        shown = "; ".join(str(x) for x in verdict["restatementEvidence"])
        lines.append(f'<span class="v-field">restatement evidence</span> '
                     f'<span class="v-value"><code>{_esc(shown)}</code>'
                     f'</span>')
    return (
        f'<div class="verdict verdict-{_esc(kind)}">'
        f'<div class="verdict-head">'
        f'<span class="pip pip-{_esc(kind)}">{_esc(_PIP.get(kind, kind))}'
        f'</span>'
        f'<span class="verdict-by">the judge, in '
        f'{_blob(str((replay.get("provenance") or {}).get("outcome")), "outcome.json")}'
        f'</span></div>'
        f'<p class="verdict-says">{_esc(replay.get("verdict", {}).get("sentence"))}</p>'
        f'<div class="verdict-fields">' + "".join(
            f'<div class="v-row">{line}</div>' for line in lines)
        + '</div></div>')


def _listing(marked: Iterable[Sequence[str]]) -> str:
    """The final file, each line marked against the obligation it started as."""
    rows = []
    for pair in marked:
        mark, text = (list(pair) + [" ", ""])[:2]
        name = {"+": "add", "-": "del"}.get(mark, "same")
        rows.append(f'<span class="line line-{name}">'
                    f'<span class="gutter" aria-hidden="true">{_esc(mark)}'
                    f'</span>{_esc(text)}</span>')
    return "\n".join(rows)


def _panel(index: int, replay: Mapping[str, Any]) -> str:
    """One session, finished."""
    ob = replay.get("obligation") or {}
    session = replay.get("session") or {}
    verdict = replay.get("verdict") or {}
    steps = "".join(_step(step, index, at) for at, step
                    in enumerate(session.get("steps") or []))
    totals = session.get("totals") or {}
    thinking = totals.get("thinkingTokens")
    thought = (f'  The client billed {int(thinking):,} thinking tokens over '
               'the session; their text is not in the archive.'
               if isinstance(thinking, int) else "")
    return (
        f'<section class="replay-panel" role="tabpanel" '
        f'id="replay-panel-{index}" aria-labelledby="replay-tab-{index}" '
        f'data-index="{index}" '
        f'data-obligation-path="{_esc(ob.get("path"))}" '
        f'data-final-path="{_esc((replay.get("final") or {}).get("path"))}">'
        f'<h3 class="panel-title">'
        f'<code>{_esc(replay.get("label"))}</code> '
        f'<span class="panel-model">{_esc(replay.get("modelLabel"))}</span> '
        f'<span class="pip pip-{_esc(verdict.get("kind"))}">'
        f'{_esc(_PIP.get(str(verdict.get("kind")), ""))}</span></h3>'
        f'<p class="panel-blurb">{_esc(replay.get("blurb"))}</p>'
        f'{_facts(replay)}'
        f'<div class="goal"><span class="goal-label">the hole’s goal, as '
        f'<code>get_goal</code> reported it</span>'
        f'<pre class="wide"><code>{_esc(ob.get("goal"))}</code></pre></div>'
        f'<div class="stream-head">'
        f'<span>the session, {_plural(verdict.get("turns"), "turn", "turns")}'
        f' and {_plural(verdict.get("toolCalls"), "tool call", "tool calls")}'
        f'</span>'
        f'<button class="replay-again" type="button" hidden>'
        f'↻ replay</button></div>'
        f'<ol class="replay-stream" tabindex="0" '
        f'aria-label="The session, turn by turn">{steps}</ol>'
        f'<p class="stream-note">The model’s words and its calls are '
        f'quoted from '
        f'{_blob(str((replay.get("provenance") or {}).get("transcript")), "transcript.jsonl")}'
        f'; every answer below a call is the server’s own, in full.'
        f'{_esc(thought)}</p>'
        f'{_verdict(replay)}'
        f'<details class="replay-file">'
        f'<summary>the file the judge read, marked against the obligation it '
        f'started as</summary>'
        f'<pre class="wide listing"><code>'
        f'{_listing((replay.get("final") or {}).get("marked") or [])}'
        f'</code></pre>'
        f'<p class="stream-note">'
        f'{_blob(str((replay.get("final") or {}).get("path")))}</p>'
        f'</details>'
        f'</section>')


def _tabs(replays: Sequence[Mapping[str, Any]]) -> str:
    buttons = []
    for index, replay in enumerate(replays):
        kind = str((replay.get("verdict") or {}).get("kind"))
        first = index == 0
        buttons.append(
            f'<button class="replay-tab" type="button" role="tab" '
            f'id="replay-tab-{index}" aria-controls="replay-panel-{index}" '
            f'aria-selected="{"true" if first else "false"}"'
            f'{"" if first else " tabindex=-1"}>'
            f'<span class="tab-name"><code>{_esc(replay.get("label"))}</code>'
            f'</span>'
            f'<span class="tab-model">{_esc(replay.get("modelLabel"))}</span>'
            f'<span class="pip pip-{_esc(kind)}">'
            f'{_esc(_PIP.get(kind, kind))}</span></button>')
    return (f'<div class="replay-tabs" role="tablist" '
            f'aria-label="Sessions" hidden>{"".join(buttons)}</div>')


def player(replays: Sequence[Mapping[str, Any]]) -> str:
    panels = "".join(_panel(index, replay)
                     for index, replay in enumerate(replays))
    return (f'<div class="replay" role="group" aria-label="Replays of '
            f'archived agda-mcp sessions">{_tabs(replays)}{panels}</div>')


# ------------------------------------------------- pointing at a tab

#: Positions the prose can name.  The roster is five long and is data, so a
#: sentence that says "the last tab" is a claim about it that can go stale in
#: a way nothing catches; these are computed instead, and
#: `test_demo_render.py` checks the published sentence against the rendered
#: tab strip.
_ORDINALS = ("first", "second", "third", "fourth", "fifth", "sixth",
             "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth",
             "thirteenth", "fourteenth", "fifteenth", "sixteenth",
             "seventeenth", "eighteenth", "nineteenth", "twentieth")


def _ordinal(index: int) -> str:
    return _ORDINALS[index] if index < len(_ORDINALS) else f"number {index + 1}"


def _one_tab(replays: Sequence[Mapping[str, Any]],
             verdict: str) -> Optional[Tuple[int, Mapping[str, Any]]]:
    """The single tab with this verdict, or None if it is not unique."""
    hits = [(at, replay) for at, replay in enumerate(replays)
            if (replay.get("verdict") or {}).get("kind") == verdict]
    return hits[0] if len(hits) == 1 else None


def _names(replay: Mapping[str, Any]) -> str:
    """How the prose refers to one session: the way its own tab reads."""
    return (f'<code>{_esc(replay.get("label"))}</code> as '
            f'{_esc(replay.get("modelLabel"))} left it')


def _the_pair(replays: Sequence[Mapping[str, Any]]) -> Optional[Tuple[int, int]]:
    """The two adjacent tabs that are one obligation given to two models."""
    for at in range(len(replays) - 1):
        here, then = replays[at], replays[at + 1]
        if here.get("subject") == then.get("subject") and \
                (here.get("verdict") or {}).get("kind") != \
                (then.get("verdict") or {}).get("kind"):
            return at, at + 1
    return None


# ----------------------------------------------------------------- table

def _arms(numbers: Mapping[str, Any]) -> Tuple[Mapping[str, Any], Mapping[str, Any]]:
    """The two archived arms' summaries: Sonnet 5's, then Opus 5's."""
    arms = numbers.get("arms") or {}
    return arms.get("sonnet") or {}, arms.get("opus") or {}


def _control_arm(numbers: Mapping[str, Any], arm: str) -> Mapping[str, Any]:
    """One of the control's three arms (`shell`, `mcp`, `both`) by name.

    The archived Sonnet arm is also an `mcp` arm and leads the control's
    columns, so it is skipped: the control's own arms are the rest.
    """
    arms = list((numbers.get("control") or {}).get("arms") or [])
    return next((a for a in arms[1:] if a.get("arm") == arm), {})


def _calls(numbers: Mapping[str, Any], run: Any, tool: str) -> int:
    """How many times one run's subjects called one tool, by its bare name."""
    per_tool = ((numbers.get("control") or {}).get("perTool") or {}).get(run)
    counts = {str(name).replace("mcp__agda__", ""): int(n)
              for name, n in per_tool or []}
    return counts.get(tool, 0)


def table(numbers: Mapping[str, Any]) -> str:
    """The archived arms' table, regenerated and checked against ADR 0001
    § 9, with the loop's columns set apart as the other instrument they are."""
    sonnet, opus = _arms(numbers)
    rows = []
    for row in numbers.get("rows") or []:
        total = row.get("stratum") == "total"
        cells = (row.get("stratum"), row.get("n"),
                 row.get("sonnetSolved"), row.get("sonnetRestated"),
                 row.get("opusSolved"), row.get("opusRestated"),
                 row.get("loopFixed"), row.get("loopRetrieval"))
        tag = "th" if total else "td"
        body = "".join(
            f'<{tag} class="{"name" if at == 0 else "num"}'
            f'{" apart" if at == 6 else ""}">{_esc(cell)}</{tag}>'
            for at, cell in enumerate(cells))
        rows.append(f'<tr{" class=total" if total else ""}>{body}</tr>')
    return (f'<div class="table-wrap"><table class="numbers agents"'
            f'{_runs(sonnet.get("runId"), opus.get("runId"))}>'
            f'<caption>Solved and restated per stratum, for the two arms the '
            f'sessions above come from, checked against '
            f'{_adr("agents", "ADR 0001 § 9’s agent table")}.  The last two '
            f'columns are the proof-search loop’s solves: a different '
            f'instrument, with no model in it.</caption>'
            f'<colgroup><col><col></colgroup><colgroup span="2"></colgroup>'
            f'<colgroup span="2"></colgroup>'
            f'<colgroup span="2"></colgroup>'
            f'<thead><tr>'
            f'<th scope="col" rowspan="2">stratum</th>'
            f'<th scope="col" rowspan="2">n</th>'
            f'<th scope="colgroup" colspan="2">Sonnet 5, with the server</th>'
            f'<th scope="colgroup" colspan="2">Opus 5, with the server</th>'
            f'<th scope="colgroup" colspan="2" class="apart">the search '
            f'loop, no model</th></tr><tr>'
            f'<th scope="col">solved</th><th scope="col">restated</th>'
            f'<th scope="col">solved</th><th scope="col">restated</th>'
            f'<th scope="col" class="apart">fixed space</th>'
            f'<th scope="col">retrieval</th></tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div>')


def _column_label(column: str) -> str:
    """How the control table heads one of its arm columns."""
    if column == "archive mcp":
        return "archived <code>mcp</code>"
    return f"<code>{_esc(column)}</code>"


def control_table(numbers: Mapping[str, Any]) -> str:
    """The control's table, the ADR's attribution table regenerated: one
    column pair per arm, the archived Sonnet arm first."""
    control = numbers.get("control") or {}
    columns = [str(c) for c in control.get("columns") or []]
    runs = [a.get("runId") for a in control.get("arms") or []]
    rows = []
    for row in control.get("rows") or []:
        total = row.get("stratum") == "total"
        tag = "th" if total else "td"
        cells = [row.get("stratum"), row.get("n")] + [
            value for cell in row.get("cells") or []
            for value in (cell.get("solved"), cell.get("restated"))]
        body = "".join(
            f'<{tag} class="{"name" if at == 0 else "num"}">{_esc(cell)}'
            f'</{tag}>' for at, cell in enumerate(cells))
        rows.append(f'<tr{" class=total" if total else ""}>{body}</tr>')
    groups = "".join(
        f'<th scope="colgroup" colspan="2">{_column_label(column)}</th>'
        for column in columns)
    names = ('<th scope="col">solved</th><th scope="col">restated</th>'
             * len(columns))
    spans = '<colgroup span="2"></colgroup>' * len(columns)
    return (f'<div class="table-wrap"><table class="numbers control"'
            f'{_runs(*runs)}>'
            f'<caption>The control, solved and restated per stratum, checked '
            f'against {_adr("control", "ADR 0001 § 9’s attribution table")}.'
            f'  Sonnet 5 in every column; the archived <code>mcp</code> '
            f'column is the Sonnet arm above.</caption>'
            f'<colgroup><col><col></colgroup>{spans}'
            f'<thead><tr><th scope="col" rowspan="2">stratum</th>'
            f'<th scope="col" rowspan="2">n</th>{groups}</tr>'
            f'<tr>{names}</tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div>')


def tiers(numbers: Mapping[str, Any]) -> str:
    sonnet, opus = _arms(numbers)
    rows = "".join(
        f'<tr><th scope="row">{_esc(row.get("tier"))}</th>'
        f'<td class="num">{_esc(row.get("n"))}</td>'
        f'<td class="num">{_esc(row.get("sonnetSolved"))}</td>'
        f'<td class="num">{_esc(row.get("opusSolved"))}</td></tr>'
        for row in numbers.get("perTier") or [])
    return (f'<div class="table-wrap"><table class="numbers small"'
            f'{_runs(sonnet.get("runId"), opus.get("runId"))}>'
            f'<caption>By difficulty tier.</caption>'
            f'<thead><tr><th scope="col">tier</th><th scope="col">n</th>'
            f'<th scope="col">Sonnet 5 solved</th>'
            f'<th scope="col">Opus 5 solved</th></tr></thead>'
            f'<tbody>{rows}</tbody></table></div>')


def _arm(arm: Mapping[str, Any]) -> str:
    gates = arm.get("gates") or {}
    refused = "; ".join(
        f"{count} refused at the {name} gate" for name, count in gates.items())
    client = str(arm.get("clientVersion") or "").replace(" (Claude Code)", "")
    return (
        f'<div class="arm"{_runs(arm.get("runId"))}>'
        f'<h3><code>{_esc(arm.get("model"))}</code></h3>'
        f'<p class="arm-run">run {_tree("reports/agent-bench/" + str(arm.get("runId")), str(arm.get("runId")))}'
        f', Claude Code {_esc(client)}</p>'
        f'<ul class="arm-facts">'
        f'<li><strong>{_esc(arm.get("solved"))}</strong> of '
        f'{_esc(arm.get("total"))} solved</li>'
        f'<li>{_esc(arm.get("restated"))} restated'
        f'{"; " + _esc(refused) if refused else ""}</li>'
        f'<li>{_esc(arm.get("turns"))} turns, '
        f'{_esc(arm.get("toolCalls"))} tool calls</li>'
        f'<li>{_money(arm.get("costUsd"))} at list price</li>'
        f'<li>{_esc(arm.get("anomalies"))} anomalies</li>'
        f'</ul></div>')


def _never_called(numbers: Mapping[str, Any]) -> List[str]:
    """The server's tools both archived arms were presented and never called."""
    sonnet, opus = _arms(numbers)
    presented = (set(sonnet.get("agdaTools") or [])
                 | set(opus.get("agdaTools") or []))
    called = {str(name).replace("mcp__agda__", "")
              for arm in ("sonnet", "opus")
              for name, _ in (numbers.get("perTool") or {}).get(arm) or []}
    return sorted(presented - called)


def tools_table(numbers: Mapping[str, Any]) -> str:
    """Per-tool call counts, the two arms side by side."""
    sonnet_arm, opus_arm = _arms(numbers)
    sonnet = {name: count for name, count
              in (numbers.get("perTool") or {}).get("sonnet") or []}
    opus = {name: count for name, count
            in (numbers.get("perTool") or {}).get("opus") or []}
    names = sorted(set(sonnet) | set(opus),
                   key=lambda n: (-(sonnet.get(n, 0) + opus.get(n, 0)), n))
    rows = "".join(
        f'<tr><th scope="row"><code>'
        f'{_esc(name.replace("mcp__agda__", ""))}</code></th>'
        f'<td class="num">{sonnet.get(name, 0)}</td>'
        f'<td class="num">{opus.get(name, 0)}</td></tr>'
        for name in names)
    never = _never_called(numbers)
    unused = (" and ".join(f"<code>{_esc(name)}</code>" for name in never)
              + (" was" if len(never) == 1 else " were")
              + " presented and never called.") if never else ""
    return (f'<div class="table-wrap"><table class="numbers small"'
            f'{_runs(sonnet_arm.get("runId"), opus_arm.get("runId"))}>'
            f'<caption>Every tool call of both arms, by tool.  {unused}'
            f'</caption>'
            f'<thead><tr><th scope="col">tool</th>'
            f'<th scope="col">Sonnet 5</th>'
            f'<th scope="col">Opus 5</th></tr></thead>'
            f'<tbody>{rows}</tbody></table></div>')


# ------------------------------------------------------------------ page

HEAD = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{tagline}">
<meta name="color-scheme" content="light dark">
<link rel="icon" href="assets/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="assets/demo.css">
<script>document.documentElement.className = "has-js";</script>
</head>
<body>
"""

FOOT = """<script src="assets/replay.js" defer></script>
</body>
</html>
"""


def tagline(replays: Sequence[Mapping[str, Any]]) -> str:
    """The page's one-line description: what the sessions are evidence of."""
    return ("What a frontier model does with the agda-mcp server’s tools: "
            f"{_word(len(replays))} real sessions from the committed archive, "
            "replayed with every call and every answer in full.")


def _tool_calls(replays: Sequence[Mapping[str, Any]]) -> int:
    """Every call the replayed sessions made, as the page shows them."""
    return sum(1 for replay in replays
               for step in (replay.get("session") or {}).get("steps") or []
               if step.get("kind") == "call")


def _suite(numbers: Mapping[str, Any]) -> Any:
    """How many obligations the suite has: the table's total row's `n`."""
    return ((numbers.get("rows") or [{}])[-1]).get("n")


def _hero(numbers: Mapping[str, Any],
          replays: Sequence[Mapping[str, Any]]) -> str:
    # No solve count and no loop count: the figures say what the page is.
    # A solve count needs its instrument, its run, and a caveat, and the
    # header has room for none of the three (Issue #215).
    return f"""<header class="hero">
<p class="eyebrow">formalverification / agda-native-air</p>
<h1>{_esc(HEADLINE)}</h1>
<p class="lede">{_esc(tagline(replays))}</p>
<ul class="hero-figures">
<li><strong>{_esc(len(replays))}</strong> sessions, replayed from their
transcripts</li>
<li><strong>{_esc(_tool_calls(replays))}</strong> tool calls, and every
answer in full</li>
<li><strong>{_esc(_suite(numbers))}</strong> obligations in the benchmark
they come from</li>
</ul>
<nav class="jump" aria-label="Sections">
<a href="#sessions">the sessions</a>
<a href="#restated">what restated means</a>
<a href="#numbers">the numbers</a>
<a href="#control">the control</a>
<a href="#haystack">one tier that measures nothing about the model</a>
<a href="#built">how this page is built</a>
</nav>
</header>"""


def _intro(numbers: Mapping[str, Any],
           replays: Sequence[Mapping[str, Any]]) -> str:
    sonnet, _ = _arms(numbers)
    # The premises of the last sentence are the record's, and
    # `test_the_intros_reading_of_the_control_still_holds` pins them: the
    # shell arm solved at least as many rows as the server arm, and the
    # control's arms could read the originals the archived arms could not.
    return f"""<section class="prose" id="what">
<h2>What this is</h2>
<p><code>agda-native-air</code> gives a coding agent a way to ask Agda
questions.  Its server, <code>agda-mcp</code>, offers tools over MCP that load
a file, report a hole&rsquo;s goal and context, infer the type of an
expression, resolve a name, list a module&rsquo;s exports, search a corpus,
probe a candidate term into a hole, and type-check the result.</p>
<p>The {_word(len(replays))} sessions below come from the project&rsquo;s
first agent measurement ({_issue(154)}): each of {_word(_suite(numbers))}
proof obligations handed to one fresh, non-interactive Claude Code session
with the server&rsquo;s {_word(sonnet.get("toolCount"))} tools as they stood
on {_esc(sonnet.get("startedOn"))}, Read and Edit on a single staged file, and
nothing else (no shell, no settings, no project instructions, no memory),
under caps of {_word(sonnet.get("turnCap"))} turns,
{_word(sonnet.get("wallCapSec"))} seconds, and
{_money(sonnet.get("budgetCapUsd"))}.</p>
<p>They are evidence of what a frontier model does with the tools: which ones
it calls, what it asks, what the answers say, and what it writes from them.
They are not evidence that the tools help.  Every session in that measurement
had the server, so nothing in it compares the tools with their absence.  That
comparison is <a href="#control">the control</a> ({_issue(162)}): the same
model, prompts, caps, and judge, with a shell and the same <code>agda</code>
in place of the server.  The numbers below set it beside these sessions&rsquo;
arms, and the guide to the results reads it in {_guide("4.3")}.  In short:
the server did not come out ahead on the count, and the count does not settle
the question, because the control could read the library&rsquo;s own proofs,
which these sessions could not.</p>
<p>Every fact the judge uses about the <em>Agda</em> in the file a session
left behind is Agda&rsquo;s own answer, asked through the same server and the
same <code>agda</code> invocation the benchmark&rsquo;s gold solutions are
verified with: the elaborated type of the definition, the references in its
body, the safe-flag refusals, the hole list, the exit code.  One gate is
textual and stays textual, because it asks about the file rather than about
the Agda in it: whether the module line and every original import line are
still there, read as a line diff with comments stripped on both sides.  The
marked listing at the foot of each session below is the page&rsquo;s own diff
of the obligation against the final file, for the reader; the judge never
saw it.</p>
<p>The sessions on this page are replayed out of the transcripts committed in
this repository, under {_tree("reports/agent-bench", "reports/agent-bench/")}.
The replay types what the model typed and shows what the server answered; it
invents nothing, and the page is complete and readable with JavaScript
switched off.</p>
</section>"""


def _original(replay: Mapping[str, Any]) -> Optional[Mapping[str, Any]]:
    """The judge's `original` reading of one session, or None on a row that
    restates no library lemma."""
    found = (replay.get("verdict") or {}).get("original")
    return found if isinstance(found, dict) else None


def reading(original: Mapping[str, Any]) -> str:
    """What one `original` block says, in words.

    `reads` counts the successful calls that named the original's file and
    `refusedReads` the ones the client refused; neither is the proof in
    view, which only a body line in an answer makes (Issue #188).
    """
    reads = int(original.get("reads") or 0)
    refused = int(original.get("refusedReads") or 0)
    if original.get("inView"):
        return ("a line of its proof came back in one of the session&rsquo;s "
                "tool answers before the last edit")
    if reads:
        return (f"the session read the file that holds it {_times(reads)}, "
                "and no answer showed the proof before the last edit")
    if refused:
        return (f"the session asked to read the file that holds it "
                f"{_times(refused)}, and the client refused")
    return "no call the session made named the file that holds it"


def _readings(replays: Sequence[Mapping[str, Any]]) -> str:
    """One line per session on a row with an original, read from its block."""
    items = []
    for replay in replays:
        original = _original(replay)
        if original is None:
            continue
        kind = str((replay.get("verdict") or {}).get("kind"))
        restates = (replay.get("obligation") or {}).get("restates")
        items.append(
            f'<li>{_names(replay)} ({_esc(_PIP.get(kind, kind))}): the '
            f'original is <code>{_esc(restates)}</code>; '
            f'{reading(original)}.</li>')
    return f'<ul class="readings">{"".join(items)}</ul>'


def _readings_summary(replays: Sequence[Mapping[str, Any]],
                      numbers: Mapping[str, Any]) -> str:
    """What the readings add up to, for these sessions and their arms."""
    held = [r for r in replays if _original(r) is not None]
    bare = [r for r in replays if _original(r) is None]
    rows = {r.get("subject") for r in bare}
    seen = [r for r in held if (_original(r) or {}).get("inView")]
    parts = []
    if bare:
        where = ("one row" if len(rows) == 1
                 else f"{_word(len(rows))} rows")
        parts.append(
            f"The other {_word(len(bare))} sessions are on {where} whose "
            "index entry names no original, so the judge makes no such "
            "reading there.")
    if held and not seen:
        parts.append(
            f"None of the {_word(len(held))} sessions on a row with an "
            "original had its proof in view: each of their files, solve or "
            "restatement, was written without the library&rsquo;s proof in "
            "front of the model.")
    elif seen:
        parts.append(
            f"{_capital(_word(len(seen)))} of the {_word(len(held))} "
            "sessions on a row with an original had its proof in view.")
    arms = _arms(numbers)
    if all((arm.get("withOriginal") or {}).get("reads") == 0
           and (arm.get("withOriginal") or {}).get("inView") == 0
           and (arm.get("withOriginal") or {}).get("refusedReads", 0) > 0
           for arm in arms):
        parts.append(
            "In the arms these sessions come from, no session read an "
            "original: the client confined the file tools to the staged "
            "file and refused every such read.")
    parts.append(
        '<a href="#control">The control</a> could read the libraries&rsquo; '
        "sources, and there the same reading changes what the counts mean.")
    return "<p>" + "  ".join(parts) + "</p>"


def _restated(replays: Sequence[Mapping[str, Any]],
              numbers: Mapping[str, Any]) -> str:
    pair = _the_pair(replays)
    which = (f"The {_ordinal(pair[0])} and {_ordinal(pair[1])} tabs above"
             if pair else "Two of the tabs above")
    return f"""<section class="prose" id="restated">
<h2>What <em>restated</em> means</h2>
<p class="callout">A file that type-checks, keeps the statement it was given,
and proves it by calling the library&rsquo;s own lemma for that statement is not
counted as a solve.  It goes in a column of its own.</p>
<p>The benchmark&rsquo;s obligations were mined from two Agda libraries, so for
most of them the library already contains a proof.  An agent that finds that
proof and calls it has done something useful and has not done the thing being
measured, which is whether the model can build the proof.  So the judge
separates the two mechanically: it reads the references in the finished
definition off Agda&rsquo;s internal terms, through the
<code>agda-strux</code> extractor, and compares them with the original the
obligation was mined from, which each row of the benchmark index names in a
<code>restates:</code> tag.  A match is a restatement, whatever else the file
earned.</p>
<p>{which} are one obligation, given to two models with the same tools.
Both files type-check.  One is a solve and one is a restatement, and the judge
told them apart from Agda&rsquo;s own terms, not from a reading of the
text.</p>
<h3>What the rule cannot see</h3>
<p>The rule reads references, so it catches a proof that cites the
library&rsquo;s lemma and not one that transcribes the lemma&rsquo;s own proof
under a new name: a transcription passes as a solve.  So on every row with an
original the judge also reports, beside its verdict and deciding nothing,
whether a line of the original&rsquo;s own proof came back in one of the
session&rsquo;s tool answers before its last edit of the file
({_issue(188)}).  For the sessions on this page that reading is as
follows:</p>
{_readings(replays)}
{_readings_summary(replays, numbers)}
</section>"""


def _days(arms: Sequence[Mapping[str, Any]]) -> str:
    """The day or days some arms began, as a phrase."""
    days = sorted({str(arm.get("startedOn")) for arm in arms})
    return " and ".join(_esc(day) for day in days)


def _capital(text: str) -> str:
    """A phrase, opening a sentence."""
    return text[:1].upper() + text[1:]


def _archived_readings(numbers: Mapping[str, Any],
                       replays: Sequence[Mapping[str, Any]]) -> str:
    """The paragraph under the tools table: what the table does not show."""
    sonnet, _ = _arms(numbers)
    rows = {row.get("stratum"): row for row in numbers.get("rows") or []}
    restated = int((rows.get("total") or {}).get("sonnetRestated") or 0)
    algebras = sum(int(row.get("sonnetRestated") or 0)
                   for name, row in rows.items()
                   if str(name).startswith("agda-algebras"))
    wholesale = int((rows.get("agda-algebras/wholesale") or {})
                    .get("sonnetRestated") or 0)
    where = ("all <code>agda-algebras</code> rows" if algebras == restated
             else f"{_word(algebras)} of them <code>agda-algebras</code> rows")
    gate = _one_tab(replays, "gate")
    refused = (f"the {_ordinal(gate[0])} tab above, {_names(gate[1])}:"
               if gate else "one of the tabs above:")
    unsolved = sum(int(n) for n in (sonnet.get("gates") or {}).values())
    # One unsolved row is the one on the page; with more, the sentence names
    # the one it shows among them.
    rows_word = ("the one row that is" if unsolved == 1
                 else f"the {_word(unsolved)} rows that are")
    verb = "is" if unsolved == 1 else "include"
    return f"""<p{_runs(sonnet.get("runId"))}>Two readings the table does not
show on its own.
Sonnet&rsquo;s {_word(restated)} restatements are {where},
{_word(wholesale)} of them from the stratum whose fixtures import whole modules
and name nothing useful.  And {rows_word} neither solved nor restated {verb}
{refused} a file Agda accepts, refused because the session reached for
<code>trans</code> by editing the fixture&rsquo;s own import line instead of
adding one.  The gate is the protocol&rsquo;s, the file is fine, and the row
stays unsolved.</p>"""


def _ended(numbers: Mapping[str, Any]) -> str:
    """How the archived arms' sessions ended, from their own counts."""
    arms = _arms(numbers)
    anomalies = [int(arm.get("anomalies") or 0) for arm in arms]
    capped = sum(int(arm.get("total") or 0) - int(arm.get("completed") or 0)
                 for arm in arms)
    first = ("Neither arm produced an anomaly" if not any(anomalies)
             else f"The arms produced {_word(anomalies[0])} and "
                  f"{_word(anomalies[1])} anomalies")
    second = ("no subject reached a cap: every session stopped because the "
              "model stopped" if capped == 0
              else f"{_count(capped, 'session', 'sessions')} ended at a cap "
                   "or a crash")
    return f"{first}, and {second}."


def _control(numbers: Mapping[str, Any]) -> str:
    """The control's subsection: who ran, how the protocol differs, the
    table, and what it shows, every figure read from the data."""
    control = numbers.get("control") or {}
    arms = list(control.get("arms") or [])
    archived = arms[0] if arms else {}
    shell, mcp, both = (_control_arm(numbers, name)
                        for name in ("shell", "mcp", "both"))
    added = sorted(set(mcp.get("agdaTools") or [])
                   - set(archived.get("agdaTools") or []))
    uncalled = all(_calls(numbers, arm.get("runId"), tool) == 0
                   for arm in (mcp, both) for tool in added)
    offered = " and ".join(f"<code>{_esc(tool)}</code>" for tool in added)
    by_hand = sum(int(n) for kind, n in (both.get("perShell") or {}).items()
                  if str(kind).startswith("agda"))
    verdicts = int((both.get("verdictVia") or {}).get("mcp") or 0)
    s_orig = shell.get("withOriginal") or {}
    m_orig = mcp.get("withOriginal") or {}
    a_orig = archived.get("withOriginal") or {}
    gap = int(shell.get("solved") or 0) - int(mcp.get("solved") or 0)
    ran = ("never ran <code>agda</code> on the shell" if by_hand == 0
           else f"ran <code>agda</code> on the shell {_times(by_hand)}")
    called = "no subject called it" if uncalled else "subjects called it"
    share = ("all" if verdicts == both.get("total") else _word(verdicts))
    both_run, mcp_run = both.get("runId"), mcp.get("runId")
    dropped = (f"<code>definition_of</code> "
               f"{_num(_calls(numbers, both_run, 'definition_of'))} calls "
               f"against {_num(_calls(numbers, mcp_run, 'definition_of'))} "
               f"in the <code>mcp</code> arm, <code>search_by_name</code> "
               f"{_num(_calls(numbers, both_run, 'search_by_name'))} against "
               f"{_num(_calls(numbers, mcp_run, 'search_by_name'))}")
    return f"""<h3 id="control">The control</h3>
<p>Every subject of those two arms had the server, so the tables above
cannot say whether it helps.  The control ({_issue(162)}) can: Sonnet 5
again, over the same {_word(_suite(numbers))} obligations with the same
prompts, caps, and judge, in three arms run one at a time on
{_days(arms[1:])}.  The
<code>shell</code> arm has Bash with the same pinned <code>agda</code> and no
server, the <code>mcp</code> arm has the server, and the <code>both</code> arm
has both.  Their counts are regenerated from their reports and checked against
ADR 0001 &sect; 9 the same way, beside the archived Sonnet arm above.</p>
<p>The control&rsquo;s protocol differs from the archived arms&rsquo; in three
ways, and the differences travel with any comparison across the columns: its
server offered {offered} besides the {_word(archived.get("toolCount"))} tools
above, and {called}; the libraries&rsquo; own sources were readable on every
arm, where the
archived arms&rsquo; reads of them were refused; and the subjects&rsquo;
servers carried the judge&rsquo;s <code>--safe</code>.</p>
{control_table(numbers)}
<p>What it shows, read with the guide&rsquo;s {_guide("4.3")} and
{_guide("5")}, is as follows:</p>
<ul{_runs(*[a.get("runId") for a in arms])}>
<li><strong>Solved</strong>: {_num(shell.get("solved"))} with a shell and
{_num(mcp.get("solved"))} with the server, so the server did not come out
ahead on the count.  The difference is {_count(gap, "row", "rows")}, on one
seed of one model.</li>
<li><strong>Restated</strong>: {_num(shell.get("restated"))} with a shell and
{_num(mcp.get("restated"))} with the server, and the zero is not evidence of
construction.  With the sources readable, the <code>shell</code> arm had the
original&rsquo;s own proof in view before its last edit for
{_num(s_orig.get("inView"))} of its {_num(s_orig.get("solved"))}
<code>agda-algebras</code> solves, and the <code>mcp</code> arm for
{_num(m_orig.get("inView"))} of its {_num(m_orig.get("solved"))}; the
archived arm, which could read none, for {_num(a_orig.get("inView"))} of its
{_num(a_orig.get("solved"))}.  The restated rule cannot see a transcription,
so on these rows the counts measure access to the library&rsquo;s text as
much as the instrument.</li>
<li><strong>Given both</strong>, the subject took {share}
{_num(both.get("total"))} of its verdicts from the server and {ran}, and it
all but dropped the server&rsquo;s knowledge tools, the ones that answer a
question and give no verdict: {dropped}.  What a model keeps from the server,
offered a shell as well, is the verdict.</li>
</ul>
<p>Three measurements followed, and the guide carries each with its numbers.
Lean answers ({_issue(184)}, {_guide("4.3")}) cut the size of the
server&rsquo;s answers and little of its cost, with the tool mix and the solve
counts within the runs&rsquo; spread: answer size was not what made a server
arm cost more than the shell arm.  A trimmed tool surface ({_issue(191)},
{_guide("4.3")}) cut what a server arm reads every turn, and its cost with it,
without closing the gap to the shell arm&rsquo;s cost.  And a hard tier of
statements posed with no proof on disk ({_issue(189)}, {_guide("4.5")}) left
nothing to transcribe: every file
Opus&nbsp;5 left there, with the server, with a shell, and with both,
type-checks with its statement kept, so that tier sits at the model&rsquo;s
ceiling and cannot yet tell the instruments apart.</p>"""


def _numbers_section(numbers: Mapping[str, Any],
                     replays: Sequence[Mapping[str, Any]]) -> str:
    sonnet, opus = _arms(numbers)
    return f"""<section class="prose" id="numbers">
<h2>The numbers</h2>
<p>The sessions above come from two arms, one subject per obligation, run
{_word(sonnet.get("parallelism"))} at a time on {_days((sonnet, opus))}.
Every figure below is read from the archive at build time, and the two tables
ADR 0001 &sect; 9 states, this one and the control&rsquo;s, are also compared
with the ADR cell by cell, so a number in either that drifts fails the build.
The loop&rsquo;s two columns are the exception: no report in the repository
carries them, so they are read from the ADR, which is their record, and the
build checks only that the ADR&rsquo;s totals for them are the sums of its
rows.</p>
<p>The <em>loop</em> is a different instrument:
<code>agda-native-air</code>&rsquo;s own proof-search loop, with no model in
it, first over a fixed space of candidate terms and then with corpus retrieval
composed around it, and judged by its own final check rather than by the
agents&rsquo; judge.  It is not a baseline for the agents (the guide&rsquo;s
{_guide("1")}); its columns stand apart at the right of the table, for the
tier below that was built to test it.</p>
{table(numbers)}
<p>These columns say what a model does with the server, and nothing about
whether the server helps, since every subject had it.
<a href="#control">The control</a>, at the end of this section, measures
that.</p>
<div class="arms">{_arm(sonnet)}{_arm(opus)}</div>
{tiers(numbers)}
<p{_runs(sonnet.get("runId"), opus.get("runId"))}>Turns and tool calls are
the comparable columns.  Subjects ran
{_word(sonnet.get("parallelism"))} at a time, so the wall clocks are
indicative only, and the costs are the client&rsquo;s own list-price
accounting.  {_ended(numbers)}</p>
{tools_table(numbers)}
{_archived_readings(numbers, replays)}
{_control(numbers)}
</section>"""


def _haystack(numbers: Mapping[str, Any]) -> str:
    sonnet, opus = _arms(numbers)
    rows = {row.get("stratum"): row for row in numbers.get("rows") or []}
    tier = rows.get("agda-stdlib/haystack") or {}
    n = tier.get("n")
    control = list((numbers.get("control") or {}).get("arms") or [])[1:]
    every = all((arm.get("haystack") or {}).get("solved") == n
                for arm in control)
    both = (tier.get("sonnetSolved") == n and tier.get("opusSolved") == n)
    quiet = sonnet.get("haystack") or {}
    turns = quiet.get("quietTurns") or []
    asked = ", ".join(f"{_word(count)} <code>{_esc(tool)}</code>"
                      for tool, count in (quiet.get("queries") or {}).items())
    runs = [sonnet.get("runId"), opus.get("runId")] + [
        arm.get("runId") for arm in control]
    fixed = ("none" if tier.get("loopFixed") == 0
             else _word(tier.get("loopFixed")))
    solved = (f"Both model arms solve all {_word(n)}" if both
              else f"The model arms solve {_word(tier.get('sonnetSolved'))} "
                   f"and {_word(tier.get('opusSolved'))}")
    control_too = (", and so does every arm of the control, including the "
                   "shell arm, which has no server at all" if every else "")
    in_turns = " or ".join(_word(t) for t in turns)
    rest = _ordinal(int(quiet.get("quiet") or 0))
    # The rest of the tier is one session and one query, and the name it
    # asked about is quoted here; `test_the_haystack_sentence_still_holds`
    # pins all three against the archive, the name from the transcript.
    return f"""<section class="prose" id="haystack">
<h2>One tier that measures nothing about the model</h2>
<p>{_capital(_word(n))} of the {_word(_suite(numbers))} obligations are a tier
built to defeat retrieval by construction: each gold applies one
standard-library lemma that the fixture imports but does not name in its
<code>using</code> list, so the needle is never handed over in the answer key.
The search loop&rsquo;s fixed space solves {fixed} of the {_word(n)}; with
corpus retrieval it solves {_word(tier.get("loopRetrieval"))}, its first
solves under target exclusion anywhere in the project.</p>
<p{_runs(*runs)}>{solved}{control_too}.  Sonnet&nbsp;5 solves
{_word(quiet.get("quiet"))} of them in {in_turns} turns, asking Agda nothing
before its final check (read the file, edit it, check it) and naming the
needle qualified from memory; the {rest} takes {asked} on
<code>Data.Nat.Properties.+-&#8760;-assoc</code>.  These are standard-library
lemmas, and they are in every frontier model&rsquo;s training data.</p>
<p class="callout">The tier measures a ranker.  It does not measure a model,
and a page that reported its {_word(n)} solves as a result about the agent
would be reporting a result about the corpus the tier was designed to
stress.</p>
</section>"""


def _built(data: Mapping[str, Any]) -> str:
    replays = data.get("replays") or []
    archive = (data.get("numbers") or {}).get("archive") or {}
    files = f"{int(archive.get('files') or 0):,}"
    return f"""<section class="prose" id="built">
<h2>How this page is built</h2>
<p>Two Makefile targets and no network.
<code>make demo-data</code> reads the committed archive and writes one small
JSON per replay and one for the numbers; <code>make demo-site</code> renders
this page from those.  Neither the data nor the page is committed: the
archive is, and the page is rebuilt from it.  The archive itself is
{files} files and {_megabytes(archive.get("bytes"))}, counted when this page
was built, and
none of it is shipped to your browser; what is here is
{_word(len(replays))} sessions and the tables.</p>
<p>Three things the build refuses to do.  It will not write a page whose
two tables from ADR 0001 &sect; 9, the archived arms&rsquo; and the
control&rsquo;s, disagree with the ADR (<code>make demo-check</code> runs
that comparison alone, from the run reports and the ADR).  It will not write a page carrying an absolute path
from the machine the sweep ran on: every path here is anchored to
<code>&lt;repo&gt;</code>, <code>&lt;work&gt;</code> (the one directory a
session could see), or <code>&lt;nix&gt;</code>, and a path left pointing
into a home directory, a Nix store, or a per-user runtime directory fails the
build.  And it quotes no reasoning: the archived transcripts carry each
thinking block&rsquo;s signature and an empty string in place of its text, so
the replays mark where the model thought and say that the text is not
there.</p>
<p>The evidence for every claim on this page is in the following
files:</p>
<ul>
<li>{_blob(GUIDE, GUIDE)}: the reader&rsquo;s guide to every number here,
which says which instrument produced it and what it is evidence of.</li>
<li>{_blob("reports/agent-bench/README.md", "reports/agent-bench/README.md")}:
the protocol, the judge&rsquo;s gates, and what a run directory holds.</li>
<li>{_blob(ADR, ADR)} &sect; 9: the decision record both tables are checked
against.</li>
<li>{_blob("data/benchmarks/README.md", "data/benchmarks/README.md")}: the
{_word(_suite(data.get("numbers") or {}))} obligations, their gold solutions,
and the index row behind each panel&rsquo;s facts.</li>
<li>{_tree("scripts/python/demo", "scripts/python/demo/")}: the generator,
and {_tree("scripts/python/tests", "scripts/python/tests/")} its tests,
which run in CI.</li>
</ul>
<h3>The seam left open</h3>
<p>This page shows what Agda answered in 2026.  It cannot let you ask it
anything, because there is no Agda here: the page is static and makes no
request off its own origin.  Whether a real type-checker could join it, as
WebAssembly in the browser, is a separate question with its own measurement.
The seam is ready for the answer: each session panel above carries its
obligation&rsquo;s path and its final file&rsquo;s path as data attributes, and
both files&rsquo; text is already in the page, so a lane that re-checked them
in the browser would need no new data and no server.</p>
</section>"""


def _footer(data: Mapping[str, Any]) -> str:
    numbers = data.get("numbers") or {}
    return f"""<footer class="foot">
<p>Built by <code>make demo-site</code> from
{_tree("reports/agent-bench", "reports/agent-bench/")}.
The archived arms&rsquo; table and the control&rsquo;s are checked against
{_esc(numbers.get("checkedAgainst"))}.</p>
<p><a href="{REPO_URL}">{REPO_URL.replace("https://", "")}</a></p>
</footer>"""


def page(data: Mapping[str, Any]) -> str:
    """The whole document, from the decoded data `make demo-data` wrote."""
    numbers = data.get("numbers") or {}
    replays = data.get("replays") or []
    return (
        HEAD.format(title=_esc(TITLE), tagline=_esc(tagline(replays)))
        + _hero(numbers, replays)
        + '<main>'
        + _intro(numbers, replays)
        + '<section class="prose" id="sessions">'
        + '<h2>The sessions</h2>'
        + f'<p>{_capital(_word(len(replays)))} of the '
          f'{_word(_suite(numbers))}, chosen because each is one half of a '
          'contrast the archive already holds.  A call types the way the '
          'model typed it; the answer under it appears whole, because the '
          'server answers in one response.  Every answer is here in full, '
          'behind the control that says how long it is, so nothing is '
          'abbreviated in a way that could hide a failure.</p>'
        + player(replays)
        + '</section>'
        + _restated(replays, numbers)
        + _numbers_section(numbers, replays)
        + _haystack(numbers)
        + _built(data)
        + '</main>'
        + _footer(data)
        + FOOT)
