#!/usr/bin/env python3
"""
File: scripts/python/demo/render.py

Description: Render the demo site's page from the data `make demo-data`
  wrote (Issue #85).

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
    +  `.replay-again`, a replay control, shipped `hidden` for the same
       reason as the tablist.

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
  +  Say where a number came from.  Every figure on the page names its file,
     and the table names ADR 0001 § 9 as what it was checked against.
"""

from __future__ import annotations

from html import escape
from typing import Any, Dict, Iterable, List, Mapping, Sequence

#: The repository this page belongs to, for the links back to the evidence.
REPO_URL = "https://github.com/formalverification/agda-native-air"

#: The page's own title and one-line description.
TITLE = "agda-native-air: an agent, Agda, and thirteen tools"
TAGLINE = ("Five real sessions from the committed archive, replayed, and the "
           "55-row measurement they belong to.")


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


def _plural(n: Any, one: str, many: str) -> str:
    return f"{n} {one}" if n == 1 else f"{n} {many}"


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


# ----------------------------------------------------------------- table

def table(numbers: Mapping[str, Any]) -> str:
    """The 55-row table, regenerated and checked against ADR 0001 § 9."""
    head = ("stratum", "n", "loop, fixed space", "loop, retrieval",
            "Sonnet 5 solved", "Sonnet 5 restated",
            "Opus 5 solved", "Opus 5 restated")
    rows = []
    for row in numbers.get("rows") or []:
        total = row.get("stratum") == "total"
        cells = (row.get("stratum"), row.get("n"), row.get("loopFixed"),
                 row.get("loopRetrieval"), row.get("sonnetSolved"),
                 row.get("sonnetRestated"), row.get("opusSolved"),
                 row.get("opusRestated"))
        tag = "th" if total else "td"
        body = "".join(
            f'<{tag} class="{"name" if at == 0 else "num"}">{_esc(cell)}</{tag}>'
            for at, cell in enumerate(cells))
        rows.append(f'<tr{" class=total" if total else ""}>{body}</tr>')
    header = "".join(f'<th scope="col">{_esc(name)}</th>' for name in head)
    return (f'<div class="table-wrap"><table class="numbers">'
            f'<caption>Solved and restated per stratum, beside the '
            f'proof-search loop on the same suite and the same verifier.'
            f'</caption>'
            f'<thead><tr>{header}</tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div>')


def tiers(numbers: Mapping[str, Any]) -> str:
    rows = "".join(
        f'<tr><th scope="row">{_esc(row.get("tier"))}</th>'
        f'<td class="num">{_esc(row.get("n"))}</td>'
        f'<td class="num">{_esc(row.get("sonnetSolved"))}</td>'
        f'<td class="num">{_esc(row.get("opusSolved"))}</td></tr>'
        for row in numbers.get("perTier") or [])
    return (f'<div class="table-wrap"><table class="numbers small">'
            f'<caption>By difficulty tier.</caption>'
            f'<thead><tr><th scope="col">tier</th><th scope="col">n</th>'
            f'<th scope="col">Sonnet 5 solved</th>'
            f'<th scope="col">Opus 5 solved</th></tr></thead>'
            f'<tbody>{rows}</tbody></table></div>')


def _arm(arm: Mapping[str, Any]) -> str:
    gates = arm.get("gates") or {}
    refused = "; ".join(
        f"{count} refused at the {name} gate" for name, count in gates.items())
    return (
        f'<div class="arm">'
        f'<h3><code>{_esc(arm.get("model"))}</code></h3>'
        f'<p class="arm-run">run {_tree("reports/agent-bench/" + str(arm.get("runId")), str(arm.get("runId")))}'
        f', Claude Code {_esc(arm.get("clientVersion"))}</p>'
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


def tools_table(numbers: Mapping[str, Any]) -> str:
    """Per-tool call counts, the two arms side by side."""
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
    return (f'<div class="table-wrap"><table class="numbers small">'
            f'<caption>Every tool call of both arms, by tool.  '
            f'<code>get_diagnostics</code> and <code>check_project</code> '
            f'were presented and never called.</caption>'
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


def _hero(numbers: Mapping[str, Any]) -> str:
    arms = numbers.get("arms") or {}
    opus = arms.get("opus") or {}
    sonnet = arms.get("sonnet") or {}
    return f"""<header class="hero">
<p class="eyebrow">formalverification / agda-native-air</p>
<h1>An agent, Agda, and thirteen tools</h1>
<p class="lede">{_esc(TAGLINE)}</p>
<ul class="hero-figures">
<li><strong>{_esc(opus.get("total"))}</strong> obligations</li>
<li><strong>{_esc(opus.get("solved"))}</strong> solved by
<code>{_esc(opus.get("model"))}</code></li>
<li><strong>{_esc(sonnet.get("solved"))}</strong> solved by
<code>{_esc(sonnet.get("model"))}</code></li>
<li><strong>{_esc((numbers.get("rows") or [{{}}])[-1].get("loopRetrieval"))}</strong>
by the search loop on the same suite</li>
</ul>
<nav class="jump" aria-label="Sections">
<a href="#sessions">the sessions</a>
<a href="#restated">what restated means</a>
<a href="#numbers">the numbers</a>
<a href="#haystack">one tier that measures nothing about the model</a>
<a href="#built">how this page is built</a>
</nav>
</header>"""


def _intro() -> str:
    return """<section class="prose" id="what">
<h2>What this is</h2>
<p><code>agda-native-air</code> gives a coding agent a way to ask Agda
questions.  Thirteen tools over MCP load a file, report a hole&rsquo;s goal and
context, infer the type of an expression, resolve a name, list a
module&rsquo;s exports, search a corpus, probe a candidate term into a hole, and
type-check the result.  To find out whether that helps, 55 proof obligations
were each handed to one fresh, non-interactive Claude Code session with those
thirteen tools, Read and Edit on a single staged file, and nothing else: no
shell, no settings, no project instructions, no memory.  Each session ran
under a 30-turn cap, a 900-second cap, and a USD 3.00 cap.</p>
<p>Every fact about the file a session left behind is Agda&rsquo;s own answer,
asked through the same server and the same <code>agda</code> invocation the
benchmark&rsquo;s gold solutions are verified with.  Nothing below is a reading
of the source text.</p>
<p>The five sessions on this page are replayed out of the transcripts
committed in this repository, under
<a class="src" href="%(repo)s/tree/main/reports/agent-bench">reports/agent-bench/</a>.
The replay types what the model typed and shows what the server answered; it
invents nothing, and the page is complete and readable with JavaScript
switched off.</p>
</section>""" % {"repo": REPO_URL}


def _restated() -> str:
    return """<section class="prose" id="restated">
<h2>What <em>restated</em> means</h2>
<p class="callout">A file that type-checks, keeps the statement it was given,
and proves it by calling the library&rsquo;s own lemma for that statement is not
counted as a solve.  It goes in a column of its own.</p>
<p>The benchmark&rsquo;s obligations were mined from two Agda libraries, so for
most of them the library already contains a proof.  An agent that finds that
proof and calls it has done something useful and has not done the thing being
measured, which is whether the tools help a model build a proof.  So the judge
separates the two mechanically: it reads the references in the finished
definition off Agda&rsquo;s internal terms, through the
<code>agda-strux</code> extractor, and compares them with the original the
obligation was mined from, which each row of the benchmark index names in a
<code>restates:</code> tag.  A match is a restatement, whatever else the file
earned.</p>
<p>The first two tabs above are one obligation, given to two models with the
same tools.  Both files type-check.  One is a solve and one is a
restatement, and nothing in the difference is a matter of opinion.</p>
</section>"""


def _numbers_section(numbers: Mapping[str, Any]) -> str:
    arms = numbers.get("arms") or {}
    return f"""<section class="prose" id="numbers">
<h2>The numbers</h2>
<p>Both arms ran on 2026-09-15, one subject per obligation, three at a time.
The <em>loop</em> columns are a different instrument on the same suite and the
same verifier: <code>agda-native-air</code>&rsquo;s own proof-search loop,
first over a fixed space of candidate terms and then with corpus retrieval
composed around it.  They come from ADR 0001 &sect; 9, which is their record;
every other column on this page is regenerated from the runs&rsquo; own
<code>report.json</code> at build time and compared with that ADR cell by
cell, so a number that drifts fails the build.</p>
{table(numbers)}
<div class="arms">{_arm(arms.get("sonnet") or {{}})}{_arm(arms.get("opus") or {{}})}</div>
{tiers(numbers)}
<p>Turns and tool calls are the comparable columns.  Subjects ran three at a
time, so the wall clocks are indicative only, and the costs are the
client&rsquo;s own list-price accounting.  Neither arm produced an anomaly, and
no subject reached a cap: every session stopped because the model stopped.</p>
{tools_table(numbers)}
<p>Two readings the table does not show on its own.  Sonnet&rsquo;s eight
restatements are all <code>agda-algebras</code> rows, six of them from the
stratum whose fixtures import whole modules and name nothing useful.  And the
one row that is neither solved nor restated is the last tab above: a file
Agda accepts, refused because the session reached for <code>trans</code> by
editing the fixture&rsquo;s own import line instead of adding one.  The gate is
the protocol&rsquo;s, the file is fine, and the row stays unsolved.</p>
</section>"""


def _haystack() -> str:
    return """<section class="prose" id="haystack">
<h2>One tier that measures nothing about the model</h2>
<p>Twelve of the 55 obligations are a tier built to defeat retrieval by
construction: each gold applies one standard-library lemma that the fixture
imports but does not name in its <code>using</code> list, so the needle is
never handed over in the answer key.  The search loop&rsquo;s fixed space solves
none of the twelve; with corpus retrieval it solves six, its first solves
under target exclusion anywhere in the project.</p>
<p>Both model arms solve all twelve.  Sonnet 5 solves eleven of them in four
turns with no Agda query at all (read the file, edit it, check it), naming the
needle qualified from memory; the twelfth takes one <code>type_of</code> on
<code>Data.Nat.Properties.+-&#8760;-assoc</code>.  These are standard-library
lemmas, and they are in every frontier model&rsquo;s training data.</p>
<p class="callout">The tier measures a ranker.  It does not measure a model,
and a page that reported its twelve solves as a result about the agent would
be reporting a result about the corpus the tier was designed to stress.</p>
</section>"""


def _built(data: Mapping[str, Any]) -> str:
    replays = data.get("replays") or []
    return f"""<section class="prose" id="built">
<h2>How this page is built</h2>
<p>Two Makefile targets and no network.
<code>make demo-data</code> reads the committed archive and writes one small
JSON per replay and one for the table; <code>make demo-site</code> renders
this page from those.  Neither the data nor the page is committed: the
archive is, and the page is rebuilt from it.  The archive itself is 1,051
files and 14&nbsp;MB, and none of it is shipped to your browser; what is here
is {_esc(len(replays))} sessions and a table.</p>
<p>Three things the build refuses to do.  It will not write a page whose
table disagrees with ADR 0001 &sect; 9.  It will not write a page carrying an
absolute path from the machine the sweep ran on: every path here is anchored
to <code>&lt;repo&gt;</code>, <code>&lt;work&gt;</code> (the one directory a
session could see), or <code>&lt;nix&gt;</code>, and a path left pointing
into a home directory, a Nix store, or a per-user runtime directory fails the
build.  And it quotes no reasoning: the
archived transcripts carry each thinking block&rsquo;s signature and an empty
string in place of its text, so the replays mark where the model thought and
say that the text is not there.</p>
<p>The evidence for every claim on this page is a file you can open:</p>
<ul>
<li>{_blob("reports/agent-bench/README.md", "reports/agent-bench/README.md")}:
the protocol, the judge&rsquo;s gates, and what a run directory holds.</li>
<li>{_blob("docs/adr/0001-proof-search-on-agda-mcp.md", "docs/adr/0001-proof-search-on-agda-mcp.md")}
&sect; 9: the decision record this table is checked against.</li>
<li>{_blob("data/benchmarks/README.md", "data/benchmarks/README.md")}: the 55
obligations, their gold solutions, and the index row behind each
panel&rsquo;s facts.</li>
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
The table is checked against {_esc(numbers.get("checkedAgainst"))}.</p>
<p><a href="{REPO_URL}">{REPO_URL.replace("https://", "")}</a></p>
</footer>"""


def page(data: Mapping[str, Any]) -> str:
    """The whole document, from the decoded data `make demo-data` wrote."""
    numbers = data.get("numbers") or {}
    replays = data.get("replays") or []
    return (
        HEAD.format(title=_esc(TITLE), tagline=_esc(TAGLINE))
        + _hero(numbers)
        + '<main>'
        + _intro()
        + '<section class="prose" id="sessions">'
        + '<h2>The sessions</h2>'
        + '<p>Five of the 55, chosen because each is one half of a contrast '
          'the archive already holds.  A call types the way the model typed '
          'it; the answer under it appears whole, because the server answers '
          'in one response.  Every answer is here in full, behind the control '
          'that says how long it is, so nothing is abbreviated in a way that '
          'could hide a failure.</p>'
        + player(replays)
        + '</section>'
        + _restated()
        + _numbers_section(numbers)
        + _haystack()
        + _built(data)
        + '</main>'
        + _footer(data)
        + FOOT)
