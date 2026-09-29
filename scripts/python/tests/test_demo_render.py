"""
Tests for `scripts/python/demo/render.py` and the page it builds.

File: scripts/python/tests/test_demo_render.py

Description
-----------
`web/assets/replay.js` is written against a markup contract that this
renderer is the other half of, and the contract has no compiler.  If a class
name moves, the replay does not throw: it finds nothing, leaves the panel at
rest, and the page still looks right to anyone not watching for the
animation.  So the contract is asserted here instead, against the page the
real build produces, together with the three properties the page is
published on.

+  It is complete without JavaScript.  Every panel is in the document, every
   tab and replay control ships `hidden`, and every session's text is in the
   HTML rather than fetched.
+  It abbreviates nothing silently.  Every answer body from the data appears
   in the page in full, character for character.
+  It carries no absolute path from the machine the sweep ran on.

Issue #215 added the rules the page's framing is held to: the header
carries no solve count and no loop count; no count from the archived arms
stands in a section without the control's beside it; the restated section
states the rule's limit and reads each replayed session's `original` block;
every link into the guide and ADR 0001 names a heading that exists; and the
few qualitative sentences that rest on the record have their premises
pinned here, so a re-judge that moves one fails this suite before it
publishes a sentence the record no longer supports.

The page is built into a temporary directory, so running this suite never
disturbs a working tree.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_demo_render.py`
"""

from __future__ import annotations

import json
import re
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

import pytest

from scripts.python.demo import render
from scripts.python.demo.build_data import run as build_data
from scripts.python.demo.build_site import build as build_site, read_data
from scripts.python.demo.numbers import (
    ARCHIVE,
    BOTH_RUN,
    HINTED_RUN,
    MCP_RUN,
    OPUS_RUN,
    SHELL_RUN,
    SONNET_RUN,
)
from scripts.python.demo.numbers import COMPOSITION_RUNS
from scripts.python.demo.paths import check_clean
from scripts.python.demo.replays import COMPOSITION, ROSTER

REPO = Path(__file__).resolve().parents[3]

#: HTML elements that never have a closing tag.
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr"}


class Element:
    """The little of a DOM the assertions below need."""

    def __init__(self, tag: str, attrs: Dict[str, Optional[str]]) -> None:
        self.tag = tag
        self.attrs = attrs
        self.children: List["Element"] = []
        self.parent: Optional["Element"] = None
        self.data: List[str] = []

    @property
    def classes(self) -> List[str]:
        return (self.attrs.get("class") or "").split()

    def walk(self):
        yield self
        for child in self.children:
            yield from child.walk()

    def by_class(self, name: str) -> List["Element"]:
        return [el for el in self.walk() if name in el.classes]

    def ancestors(self):
        node = self.parent
        while node is not None:
            yield node
            node = node.parent

    @property
    def text(self) -> str:
        """Everything this element and its descendants say, in order."""
        return "".join(part for el in self.walk() for part in el.data).strip()


class Tree(HTMLParser):
    """Parse the page, and refuse it if any element is left unclosed."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.root = Element("#document", {})
        self.stack = [self.root]
        self.problems: List[str] = []

    def handle_starttag(self, tag, attrs):
        el = Element(tag, dict(attrs))
        el.parent = self.stack[-1]
        self.stack[-1].children.append(el)
        if tag not in VOID:
            self.stack.append(el)

    def handle_data(self, data):
        self.stack[-1].data.append(data)

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if len(self.stack) < 2:
            self.problems.append(f"</{tag}> at {self.getpos()} closes nothing")
            return
        top = self.stack.pop()
        if top.tag != tag:
            self.problems.append(
                f"</{tag}> at {self.getpos()} closes <{top.tag}>")


@pytest.fixture(scope="module")
def built(tmp_path_factory) -> Dict[str, Any]:
    """The page and its data, from the real build, in a temporary tree."""
    base = tmp_path_factory.mktemp("demo")
    data, out = base / "data", base / "site"
    made = build_data(REPO, data)
    assert made.is_ok, str(made.unwrap_err())
    page = build_site(REPO, data, out)
    assert page.is_ok, str(page.unwrap_err())
    html = (out / "index.html").read_text(encoding="utf-8")
    tree = Tree()
    tree.feed(html)
    assert not tree.problems, tree.problems[:5]
    assert len(tree.stack) == 1, [el.tag for el in tree.stack[1:]]
    loaded = read_data(data)
    assert loaded.is_ok, str(loaded.unwrap_err())
    return {"html": html, "root": tree.root, "out": out,
            "data": loaded.unwrap()}


# ---------------------------------------------------- the markup contract

def _players(built) -> List[Element]:
    """The page's two players: the mined suite's, then the composition
    tier's (Issue #224)."""
    players = built["root"].by_class("replay")
    assert len(players) == 2
    return players


def test_each_player_is_there_with_one_panel_per_replay(built) -> None:
    for player, roster in zip(_players(built), (ROSTER, COMPOSITION)):
        panels = player.by_class("replay-panel")
        assert len(panels) == len(roster)
        assert [el.attrs.get("data-index") for el in panels] == \
            [str(i) for i in range(len(roster))]
    # The composition player sits in its own section.
    assert any(a.attrs.get("id") == "composition"
               for a in _players(built)[1].ancestors())


def test_the_tablists_and_every_replay_control_ship_hidden(built) -> None:
    # A control that switches nothing should not exist on a page with no
    # script, so the script is what reveals these.
    tablists = built["root"].by_class("replay-tabs")
    assert len(tablists) == 2 and all("hidden" in t.attrs for t in tablists)
    buttons = built["root"].by_class("replay-again")
    assert len(buttons) == len(ROSTER) + len(COMPOSITION)
    assert all("hidden" in el.attrs for el in buttons)


def test_the_tabs_are_wired_to_their_panels(built) -> None:
    for player in _players(built):
        tabs = player.by_class("replay-tab")
        panels = player.by_class("replay-panel")
        assert len(tabs) == len(panels)
        for index, (tab, panel) in enumerate(zip(tabs, panels)):
            assert tab.attrs.get("role") == "tab"
            assert panel.attrs.get("role") == "tabpanel"
            assert tab.attrs["aria-controls"] == panel.attrs["id"]
            assert panel.attrs["aria-labelledby"] == tab.attrs["id"]
            assert tab.attrs["aria-selected"] == \
                ("true" if index == 0 else "false")
            assert ("tabindex" in tab.attrs) == (index != 0)


def test_no_id_repeats_across_the_two_players(built) -> None:
    ids = [el.attrs["id"] for el in built["root"].walk() if "id" in el.attrs]
    assert len(ids) == len(set(ids)), [i for i in ids if ids.count(i) > 1][:5]


def test_every_tab_says_how_many_turns_its_session_took(built) -> None:
    replays = built["data"]["replays"] + built["data"]["composition"]
    tabs = built["root"].by_class("replay-tab")
    assert len(tabs) == len(replays)
    for tab, replay in zip(tabs, replays):
        turns = replay["verdict"]["turns"]
        assert tab.by_class("tab-model")[0].text == \
            f"{replay['modelLabel']}, {turns} turns"


def test_every_panel_holds_a_stream_of_steps(built) -> None:
    for panel in built["root"].by_class("replay-panel"):
        streams = panel.by_class("replay-stream")
        assert len(streams) == 1
        steps = panel.by_class("step")
        assert steps
        for step in steps:
            assert step.attrs.get("data-kind") in {"text", "thinking", "call"}
            assert step.tag == "li"
            assert streams[0] in list(step.ancestors())


def test_the_typed_and_the_appearing_parts_are_marked_and_disjoint(built) -> None:
    # The split the replay is built on: the agent typed its words and its
    # calls; the server answered in one response.  Nothing may be both.
    typed = [el for el in built["root"].walk() if "data-type-text" in el.attrs]
    after = [el for el in built["root"].walk() if "data-after" in el.attrs]
    assert typed and after
    for el in typed:
        assert "data-after" not in el.attrs
        assert any("step" in a.classes for a in el.ancestors())
    for el in after:
        assert "data-type-text" not in el.attrs
        assert not any("data-type-text" in a.attrs for a in el.ancestors())
        assert any("step" in a.classes for a in el.ancestors())


def test_every_answer_appears_rather_than_types(built) -> None:
    for answer in built["root"].by_class("answer"):
        assert "data-after" in answer.attrs


def test_every_call_step_has_a_call_line_and_an_answer(built) -> None:
    for panel in built["root"].by_class("replay-panel"):
        for step in panel.by_class("step"):
            if step.attrs.get("data-kind") != "call":
                continue
            assert len(step.by_class("call")) == 1
            assert len(step.by_class("answer")) == 1


# -------------------------------------------- what the page is published on

def test_nothing_is_fetched_from_off_the_origin_at_load(built) -> None:
    loaded = []
    for el in built["root"].walk():
        for name in ("src", "href"):
            value = el.attrs.get(name)
            if value is None:
                continue
            if el.tag in ("script", "img", "iframe") or \
                    (el.tag == "link" and name == "href"):
                loaded.append(value)
    assert loaded, "no assets at all is a rendering failure, not a pass"
    for value in loaded:
        assert not value.startswith(("http://", "https://", "//")), value


def test_no_absolute_path_from_the_sweep_machine_reaches_the_page(built) -> None:
    problem = check_clean(built["html"])
    assert problem.is_ok, str(problem.unwrap_err())


def test_every_answer_body_is_in_the_page_in_full(built) -> None:
    # The page abbreviates in its headlines and never in its record: an
    # abbreviation that hid a type_error or a failed verdict would be a lie.
    bodies = 0
    for replay in built["data"]["replays"]:
        for step in replay["session"]["steps"]:
            answer = step.get("answer") if step["kind"] == "call" else None
            if not answer:
                continue
            bodies += 1
            assert render._esc(answer["body"]) in built["html"], (
                f"{replay['id']}: {step['display']}'s answer is not in the "
                "page in full")
    assert bodies > 30


def test_every_final_file_and_obligation_is_in_the_page(built) -> None:
    for replay in built["data"]["replays"]:
        assert render._esc(replay["obligation"]["goal"]) in built["html"]
        for mark, text in replay["final"]["marked"]:
            if text:
                assert render._esc(text) in built["html"]


def _table(built, name: str) -> Element:
    found = [el for el in built["root"].walk()
             if el.tag == "table" and name in el.classes]
    assert len(found) == 1, f"the page has {len(found)} tables of class {name}"
    return found[0]


def _total_row(table: Element) -> List[str]:
    rows = [el for el in table.walk()
            if el.tag == "tr" and "total" in el.classes]
    assert rows, "the table has no total row"
    return [c.text for c in rows[0].children if c.tag in ("td", "th")]


def test_the_page_carries_the_table_it_was_checked_against(built) -> None:
    # The agents' columns first; the loop's two last, set apart (Issue #215
    # moved them: a column to the left of the agents' reads as a baseline).
    total = built["data"]["numbers"]["rows"][-1]
    printed = _total_row(_table(built, "agents"))
    assert printed == ["total", "55", "44", "9", "55", "0", "8", "14"]
    assert str(total["opusSolved"]) == printed[4]


def test_the_page_is_marked_up_for_a_reader_and_a_crawler(built) -> None:
    html = built["html"]
    assert html.startswith("<!doctype html>")
    assert '<html lang="en">' in html
    assert '<meta name="viewport"' in html
    assert f"<title>{render._esc(render.TITLE)}</title>" in html
    assert '<meta name="description"' in html
    assert 'name="color-scheme"' in html


#: Classes whose contents are quoted from the archive rather than written
#: here: the model's words, a tool answer, a goal display, an index row, a
#: judge's field, and the final file.  House style governs the page's own
#: prose; it cannot govern evidence, and rewriting a quotation to obey it
#: would be the worse fault.
QUOTED = ("said", "goal", "facts", "listing", "v-value")


def test_the_page_keeps_house_style_in_its_own_prose(built) -> None:
    for el in built["root"].walk():
        if any(name in a.classes for a in [el, *el.ancestors()]
               for name in QUOTED):
            continue
        said = "".join(el.data)
        assert "\u2014" not in said, f"an em-dash in <{el.tag}>: {said[:80]!r}"


def test_the_sources_that_write_that_prose_keep_it_too() -> None:
    # The blurbs and the verdict sentences are prose too, and they are
    # written in Python rather than in the page, so the page check above
    # cannot see them until they are rendered into a quoted region.
    for path in sorted((REPO / "scripts" / "python" / "demo").glob("*.py")):
        assert "\u2014" not in path.read_text(encoding="utf-8"), path
    for path in sorted((REPO / "web" / "assets").iterdir()):
        assert "\u2014" not in path.read_text(encoding="utf-8"), path


def test_the_page_quotes_an_em_dash_it_did_not_write(built) -> None:
    # Two archived answers carry one, and they are on the page verbatim.
    # If this ever fails, a quotation has been silently edited.
    assert "\u2014" in built["html"]


def test_the_seam_for_a_live_type_checker_is_left_open(built) -> None:
    # Issue #85 ships without an in-browser Agda and leaves the attachment
    # point named; a panel that lost these would close it silently.
    for panel in built["root"].by_class("replay-panel"):
        assert panel.attrs.get("data-obligation-path", "").startswith(
            "data/benchmarks/")
        assert panel.attrs.get("data-final-path", "").startswith(
            "reports/agent-bench/")


def test_the_assets_land_beside_the_page(built) -> None:
    assets = built["out"] / "assets"
    names = sorted(path.name for path in assets.iterdir())
    assert names == ["demo.css", "favicon.svg", "replay.js"]
    css = (assets / "demo.css").read_text(encoding="utf-8")
    # replay.js reads every duration off these, so the stylesheet is where
    # the rhythm is decided and they have to be there to be read.
    for token in ("--motion-type", "--motion-call", "--motion-beat",
                  "--motion-answer", "--motion-thought", "--motion-enter"):
        assert token in css, token


def test_a_broken_data_directory_is_refused(tmp_path) -> None:
    empty = tmp_path / "data"
    empty.mkdir()
    (empty / "manifest.json").write_text('{"replays": []}', encoding="utf-8")
    outcome = build_site(REPO, empty, tmp_path / "site")
    assert outcome.is_err
    assert "no replays" in str(outcome.unwrap_err())


# ------------------------------------------------ accessibility (PR #166)

def _relative_luminance(hexcolor: str) -> float:
    def channel(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hexcolor[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def _contrast(a: str, b: str) -> float:
    la, lb = _relative_luminance(a), _relative_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def _palette(css: str, theme: str) -> Dict[str, str]:
    """One theme's colour tokens, read out of the stylesheet itself."""
    if theme == "light":
        block = re.search(r"^:root \{(.*?)^\}", css, re.S | re.M)
    else:
        block = re.search(
            r"@media \(prefers-color-scheme: dark\) \{\s*:root \{(.*?)\}",
            css, re.S)
    assert block, f"the {theme} palette is not where this test looks"
    found = dict(re.findall(r"(--[a-z-]+):\s*(#[0-9a-fA-F]{6})", block.group(1)))
    assert found, f"the {theme} palette parsed empty"
    return found


#: Tokens the stylesheet uses for text a reader has to be able to read, and
#: the three surfaces any of them can land on.  `--ink-faint` is the tight
#: one: the page uses it at 0.66rem, so the 3:1 allowance for large text
#: never applies.
_TEXT_TOKENS = ("--ink", "--ink-soft", "--ink-faint", "--accent",
                "--good", "--warn", "--bad")
_SURFACES = ("--page", "--surface", "--surface-sunk")
_ON_TINTS = (("--good", "--good-soft"), ("--warn", "--warn-soft"),
             ("--bad", "--bad-soft"), ("--accent", "--accent-soft"))

#: WCAG 2.1 AA for normal-size text.
_AA = 4.5


def test_every_text_colour_meets_wcag_aa(built) -> None:
    # Copilot found `--ink-faint` at 3.30:1 in the light palette on PR #166.
    # The measurement was wider than the report: the dark one failed on two
    # of its three surfaces too.  Recomputing the whole grid is what keeps a
    # later "just a touch lighter" from reintroducing it.
    css = (built["out"] / "assets" / "demo.css").read_text(encoding="utf-8")
    problems = []
    for theme in ("light", "dark"):
        palette = _palette(css, theme)
        for token in _TEXT_TOKENS:
            for surface in _SURFACES:
                ratio = _contrast(palette[token], palette[surface])
                if ratio < _AA:
                    problems.append(
                        f"{theme}: {token} ({palette[token]}) on {surface} "
                        f"({palette[surface]}) is {ratio:.2f}:1, below {_AA}")
        for token, tint in _ON_TINTS:
            ratio = _contrast(palette[token], palette[tint])
            if ratio < _AA:
                problems.append(
                    f"{theme}: {token} on {tint} is {ratio:.2f}:1, "
                    f"below {_AA}")
    assert not problems, "\n".join(problems)


def test_the_prose_points_at_the_tab_it_means(built) -> None:
    # Copilot found the page calling the refused session "the last tab",
    # which the roster had made false.  The sentence is generated from the
    # roster now; this reads the rendered tab strip and checks the two
    # positional claims the page makes against it.
    mined = _players(built)[0]
    tabs = mined.by_class("replay-tab")
    verdicts = [next(p for p in tab.by_class("pip")).classes for tab in tabs]
    gate = [i for i, cs in enumerate(verdicts) if "pip-gate" in cs]
    assert len(gate) == 1, "the page's sentence assumes exactly one refusal"
    assert f"the {render._ordinal(gate[0])} tab above" in built["html"], (
        f"the refused session is tab {gate[0] + 1}; the page says otherwise")

    panels = mined.by_class("replay-panel")
    subjects = [p.attrs["data-obligation-path"] for p in panels]
    pair = next(i for i in range(len(subjects) - 1)
                if subjects[i] == subjects[i + 1])
    assert (f"The {render._ordinal(pair)} and {render._ordinal(pair + 1)} "
            "tabs above") in built["html"]


def test_the_replay_can_be_stopped(built) -> None:
    # WCAG 2.2.2: the first session starts on its own and the five run 6 to
    # 25 seconds, so a stop has to exist.  The behaviour is the script's, and
    # this pins the wiring it depends on: one control per panel, which both
    # starts a replay and settles a running one.
    script = (built["out"] / "assets" / "replay.js").read_text(encoding="utf-8")
    assert "if (p.playing) settle(p); else play(p);" in script
    assert "setControl(p, true);" in script       # play claims the control
    assert "setControl(p, false);" in script      # settle releases it
    assert script.count("STOP_LABEL") >= 2
    buttons = built["root"].by_class("replay-again")
    assert len(buttons) == len(ROSTER) + len(COMPOSITION)
    assert all("hidden" in b.attrs for b in buttons)
    # Each player is armed on its own, so the second one works too.
    assert 'document.querySelectorAll(".replay").forEach(arm);' in script


# ------------------------------------------- the framing (Issue #215)

def _regions(built) -> List[Element]:
    """The page's top-level regions: the header and each section of main."""
    hero = built["root"].by_class("hero")
    mains = [el for el in built["root"].walk() if el.tag == "main"]
    assert len(hero) == 1 and len(mains) == 1
    return hero + [el for el in mains[0].children if el.tag == "section"]


def _runs_in(region: Element) -> Set[str]:
    return {run for el in region.walk()
            for run in (el.attrs.get("data-runs") or "").split()}


def test_the_header_carries_no_solve_count_and_no_loop_count(built) -> None:
    hero = built["root"].by_class("hero")[0]
    assert _runs_in(hero) == set(), "an arm's figure is back in the header"
    assert "loop" not in hero.text.lower()
    assert "solved" not in hero.text.lower()


def test_the_header_says_what_the_page_is(built) -> None:
    # Every session on the page, their calls, and the two suites they come
    # from (the mined 55 and the composition tier's 12), all counted from
    # the data rather than typed.
    replays = built["data"]["replays"] + built["data"]["composition"]
    calls = sum(1 for replay in replays
                for step in replay["session"]["steps"]
                if step["kind"] == "call")
    hero = built["root"].by_class("hero")[0]
    figures = [el.text for el in hero.walk() if el.tag == "strong"]
    assert figures == [str(len(replays)), str(calls), "67"]
    assert render.tagline(replays) in built["html"]
    assert "eight real sessions" in render.tagline(replays)


def test_the_title_names_no_tool_count(built) -> None:
    # The server has had thirteen tools and fourteen (PR #161) across the
    # runs this page has replayed; the title says neither.
    for said in (render.TITLE, render.HEADLINE):
        assert not re.search(r"\d|thirteen|fourteen", said.lower()), said


def test_the_control_stands_wherever_the_archived_arms_counts_do(built) -> None:
    # Every element that prints an arm's figure names the arm's run in
    # `data-runs`; a region showing the archived arms' counts must show the
    # control's shell and mcp arms too.
    archived, control = {SONNET_RUN, OPUS_RUN}, {SHELL_RUN, MCP_RUN}
    marked = 0
    for region in _regions(built):
        runs = _runs_in(region)
        if runs & archived:
            marked += 1
            assert control <= runs, (
                f"<{region.tag} id={region.attrs.get('id')}> prints the "
                f"archived arms' counts without the control's")
    assert marked >= 2, "the numbers and the haystack sections carry counts"


def test_the_control_table_is_the_adrs(built) -> None:
    table = _table(built, "control")
    assert set((table.attrs.get("data-runs") or "").split()) == \
        {SONNET_RUN, SHELL_RUN, MCP_RUN, BOTH_RUN}
    # The header-free control (Issue #219): shell, mcp, both.
    assert _total_row(table) == ["total", "55", "47", "4", "44", "9",
                                 "48", "5"]
    assert "attribution table" in table.text


def test_the_intro_says_what_the_sessions_are_evidence_of(built) -> None:
    intro = next(r for r in _regions(built) if r.attrs.get("id") == "what")
    said = " ".join(intro.text.split())
    assert "They are evidence of what a frontier model does with the tools" \
        in said
    assert "They are not evidence that the tools help." in said
    links = [el.attrs.get("href") or "" for el in intro.walk() if el.tag == "a"]
    assert "#control" in links
    assert any(link.endswith("#" + render.anchor(render.GUIDE_SECTIONS["4.3"]))
               for link in links)


def test_the_intros_figures_are_the_archives(built) -> None:
    sonnet = built["data"]["numbers"]["arms"]["sonnet"]
    opus = built["data"]["numbers"]["arms"]["opus"]
    assert sonnet["toolCount"] == opus["toolCount"] == 14
    intro = next(r for r in _regions(built) if r.attrs.get("id") == "what")
    said = " ".join(intro.text.split())
    assert f"server’s {render._word(sonnet['toolCount'])} tools" in said
    assert f"as re-run on {sonnet['startedOn']}" in said
    assert sonnet["startedOn"] == opus["startedOn"] == "2026-09-29"
    assert (f"caps of {sonnet['turnCap']} turns, {sonnet['wallCapSec']} "
            f"seconds, and USD {sonnet['budgetCapUsd']:.2f}") in said


def test_the_intros_reading_of_the_control_still_holds(built) -> None:
    # The intro says the server did not come out ahead on the count, and
    # that every arm could read the library's proofs, some of them in view.
    # Those are readings of the record; if a re-judge moves one, this fails,
    # and the sentence has to be rewritten rather than republished.
    arms = {arm["runId"]: arm
            for arm in built["data"]["numbers"]["control"]["arms"]}
    assert arms[SHELL_RUN]["solved"] >= arms[MCP_RUN]["solved"]
    assert arms[SHELL_RUN]["restated"] <= arms[MCP_RUN]["restated"]
    intro = next(r for r in _regions(built) if r.attrs.get("id") == "what")
    assert "the server did not come out ahead on the count" in \
        " ".join(intro.text.split())
    for run in (SHELL_RUN, MCP_RUN, BOTH_RUN):
        assert arms[run]["withOriginal"]["refusedReads"] == 0
        assert arms[run]["withOriginal"]["inView"] > 0
    for arm in built["data"]["numbers"]["arms"].values():
        assert arm["withOriginal"]["refusedReads"] == 0
    # And "given both, the subject took every verdict from the server".
    both = arms[BOTH_RUN]
    assert both["verdictVia"] == {"mcp": both["total"]}
    assert not any(kind.startswith("agda") for kind in both["perShell"])


def test_the_restated_section_states_its_limit(built) -> None:
    section = next(r for r in _regions(built)
                   if r.attrs.get("id") == "restated")
    said = " ".join(section.text.split())
    assert "What the rule cannot see" in said
    assert "not one that transcribes the lemma’s own proof" in said
    assert "a transcription passes as a solve" in said
    assert "nothing in the difference is a matter of opinion" not in said


def test_every_replayed_sessions_original_is_read_onto_the_page(built) -> None:
    # The judge's reading of each session, from its own `original` block:
    # the three agda-algebras sessions each get a line, the standard-library
    # pair gets the sentence for a row with no original, and no block's
    # store path is printed.
    section = next(r for r in _regions(built)
                   if r.attrs.get("id") == "restated")
    items = [el for el in section.walk() if el.tag == "li"]
    replays = built["data"]["replays"]
    held = [r for r in replays if r["verdict"]["original"] is not None]
    assert len(held) == 3 and len(items) == len(held)
    for replay, item in zip(held, items):
        original = replay["verdict"]["original"]
        line = " ".join(item.text.split())
        assert replay["obligation"]["restates"] in line
        assert re.sub(r"<[^>]+>", "", render.reading(original)
                      .replace("&rsquo;", "’")) in line
        assert original["inView"] is False
    said = " ".join(section.text.split())
    assert "sessions are on one row whose index entry names no original" \
        in said
    assert "None of the three sessions on a row with an original had its " \
        "proof in view" in said
    assert ".lagda" not in said and "<nix>" not in said
    assert check_clean(built["html"]).is_ok


def test_no_replayed_session_was_refused_a_read(built) -> None:
    # The first roster's sessions could not read the libraries, and one of
    # them was refused the original's file on the page.  The header-free
    # arms could read them (Issue #219), so no session on the page was
    # refused one, and the page does not say it was.
    for replay in built["data"]["replays"]:
        original = replay["verdict"]["original"] or {}
        assert original.get("refusedReads", 0) == 0
    section = next(r for r in _regions(built)
                   if r.attrs.get("id") == "restated")
    assert "the client refused" not in " ".join(section.text.split())


def _headings(path: Path) -> Set[str]:
    return {re.sub(r"^#+\s+", "", line.rstrip("\n"))
            for line in path.read_text(encoding="utf-8").splitlines()
            if re.match(r"^#{1,6}\s", line)}


def test_every_guide_and_adr_link_names_a_heading(built) -> None:
    # Sections are linked by their headings' anchors; a renamed or removed
    # heading must fail here, not on a reader's click.
    targets = {render.GUIDE: _headings(REPO / render.GUIDE),
               render.ADR: _headings(REPO / render.ADR)}
    for heading in render.GUIDE_SECTIONS.values():
        assert heading in targets[render.GUIDE], heading
    for heading in render.ADR_SECTIONS.values():
        assert heading in targets[render.ADR], heading
    checked = 0
    for el in built["root"].walk():
        href = el.attrs.get("href") or ""
        for path, headings in targets.items():
            prefix = f"{render.REPO_URL}/blob/main/{path}#"
            if href.startswith(prefix):
                checked += 1
                assert href[len(prefix):] in {render.anchor(h)
                                              for h in headings}, href
    assert checked >= 8


def test_the_anchor_rule_is_githubs() -> None:
    # Pairs read off the anchors GitHub rendered for the guide and ADR 0001
    # when Issue #215 was written.
    assert render.anchor("4.3  The control, and the comparison") == \
        "43--the-control-and-the-comparison"
    assert render.anchor("1.2  The agent with the server: the `mcp` arm") \
        == "12--the-agent-with-the-server-the-mcp-arm"
    assert render.anchor("1.5  One judge for the three arms, and the "
                         "loop's own") == \
        "15--one-judge-for-the-three-arms-and-the-loops-own"
    assert render.anchor("The attribution arms: what the server is worth") \
        == "the-attribution-arms-what-the-server-is-worth"


def test_the_later_findings_are_linked_not_restated(built) -> None:
    paragraph = next(el for el in built["root"].walk() if el.tag == "p"
                     and el.text.startswith("The measurements before these"))
    links = [el.attrs.get("href") or "" for el in paragraph.walk()
             if el.tag == "a"]
    for issue in (162, 184, 191, 189):
        assert f"{render.REPO_URL}/issues/{issue}" in links
    for section in ("4.3", "4.5", "4.6"):
        assert any(link.endswith(render.anchor(render.GUIDE_SECTIONS[section]))
                   for link in links)
    # No figure: the digits left once the issue numbers, the section
    # numbers, and the model's name are taken out are the ones to look for.
    bare = re.sub(r"#\d+|§ [\d.]+|(Opus|Sonnet)\s5", "", paragraph.text)
    assert not re.search(r"\d", bare), bare


def test_the_haystack_reading_still_holds(built) -> None:
    # Issue #219: with each header naming its needle, the Sonnet arm solved
    # most of the tier asking nothing before its final check; without it, it
    # asked first on most rows, and what it asked with was the search tools.
    # The section says so from the data, and these are its premises.
    numbers = built["data"]["numbers"]
    now = numbers["arms"]["sonnet"]["haystack"]
    was = numbers["hinted"]["haystack"]
    assert numbers["hinted"]["runId"] == HINTED_RUN
    assert now["rows"] == was["rows"] == 12
    assert now["solved"] == was["solved"] == 12
    assert was["quiet"] > was["rows"] / 2 > now["quiet"]
    searched = {tool: n for tool, n in now["queries"].items()
                if tool.startswith("search_") or tool == "exports_of"}
    assert sum(searched.values()) > sum(now["queries"].values()) / 2
    section = next(r for r in _regions(built)
                   if r.attrs.get("id") == "haystack")
    said = " ".join(section.text.split())
    assert "On most rows it was the header." in said
    # And Opus's route: probes of lemmas it named, and no search call.
    opus = numbers["arms"]["opus"]["haystack"]
    assert opus["solved"] == 12 and opus["quiet"] < opus["rows"] / 2
    assert set(opus["queries"]) <= {"fill_hole", "type_of"}
    assert "it searched for none" in said
    assert f"solved {render._word(was['quiet'])} of the twelve" in said
    assert "Needle:" in said


def test_the_archive_size_on_the_page_is_the_measured_one(built) -> None:
    archive = built["data"]["numbers"]["archive"]
    assert f"{archive['files']:,} files" in built["html"]
    assert "1,051" not in built["html"]


def test_the_protocol_the_page_names_is_the_archives(built) -> None:
    # Issue #219: the control section says its three arms share one protocol
    # with the Opus arm (the tools, readable sources, `--safe`, headers with
    # no hints), and that one difference is deliberate: the prompts of the
    # two arms with a shell name the library source directories.  Each is
    # read here from the runs' own records.
    numbers = built["data"]["numbers"]
    arms = {arm["runId"]: arm for arm in numbers["control"]["arms"]}
    opus = numbers["arms"]["opus"]
    assert set(arms[MCP_RUN]["agdaTools"]) == set(arms[BOTH_RUN]["agdaTools"]) \
        == set(opus["agdaTools"])
    assert "search_in_scope" in arms[MCP_RUN]["agdaTools"]
    configs = {run: json.loads((REPO / ARCHIVE / run / "report.json")
                               .read_text(encoding="utf-8"))["config"]
               for run in (SHELL_RUN, MCP_RUN, BOTH_RUN, OPUS_RUN)}
    for config in configs.values():
        assert config["subjectAgdaFlags"].split()[-1] == "--safe"
        assert config["claudeVersion"] == configs[MCP_RUN]["claudeVersion"]
        assert (config["maxTurns"], config["wallCapSec"],
                config["maxBudgetUsd"]) == (30, 900, 3.0)
    prompts = {run: (REPO / ARCHIVE / run / "prompts" / "system-prompt.md")
               .read_text(encoding="utf-8")
               for run in (SHELL_RUN, MCP_RUN, BOTH_RUN, OPUS_RUN)}
    assert "{{sources}}" in prompts[SHELL_RUN] and \
        "{{sources}}" in prompts[BOTH_RUN]
    assert "{{sources}}" not in prompts[MCP_RUN]
    assert prompts[MCP_RUN] == prompts[OPUS_RUN]
    html = " ".join(built["html"].split())
    assert "the prompts of the two arms with a shell name the directory " \
        "holding each library&rsquo;s sources" in html


# --------------------------------- Copilot's review of PR #217 (Issue #215)

def test_only_the_two_section_9_tables_are_said_to_be_compared(built) -> None:
    # `numbers.check` compares the archived arms' table and the control's
    # with ADR 0001 § 9; the tier and tool tables and the arm cards are
    # regenerated and have no ADR table.  The prose must not claim more.
    html = " ".join(built["html"].split())
    assert "Every figure in the tables below is regenerated" not in html
    assert ("the two tables ADR 0001 &sect; 9 states, this one and the "
            "control&rsquo;s, are also compared with the ADR cell by cell") \
        in html
    assert "Both tables are checked against" not in html
    assert ("The agents&rsquo; table, the control&rsquo;s, and the "
            "composition tier&rsquo;s are checked against") in html


def _block(built, opening: str) -> Element:
    found = [el for el in built["root"].walk() if el.tag in ("p", "ul")
             and " ".join(el.text.split()).startswith(opening)]
    assert len(found) == 1, f"{len(found)} blocks open with {opening!r}"
    return found[0]


def test_every_block_printing_an_archived_arms_results_is_marked(built) -> None:
    # The section check sees only what carries `data-runs`, so every element
    # the page has that prints an archived arm's results carries it: the
    # tables, the arm cards, and the three paragraphs and one list that
    # quote results in prose.
    marked = lambda el: set((el.attrs.get("data-runs") or "").split())
    composition = next(r for r in _regions(built)
                       if r.attrs.get("id") == "composition")
    inside = set(id(el) for el in composition.walk())
    tables = [el for el in built["root"].walk()
              if el.tag == "table" and "numbers" in el.classes
              and id(el) not in inside]
    assert len(tables) == 4
    assert all(marked(t) & {SONNET_RUN, OPUS_RUN} for t in tables)
    assert [marked(card) for card in built["root"].by_class("arm")] == \
        [{SONNET_RUN}, {OPUS_RUN}]
    assert marked(_block(built, "Two readings the table does not show")) \
        == {SONNET_RUN}
    assert marked(_block(built, "Turns and tool calls are the comparable")) \
        == {SONNET_RUN, OPUS_RUN}
    assert {SONNET_RUN, OPUS_RUN, SHELL_RUN, MCP_RUN} <= \
        marked(_block(built, "Both model arms solve all"))
    lists = [el for el in built["root"].walk()
             if el.tag == "ul" and marked(el) and id(el) not in inside]
    assert len(lists) == 1, "the control's reading is the one marked list"
    assert {SONNET_RUN, SHELL_RUN, MCP_RUN, BOTH_RUN} <= marked(lists[0])


def test_the_quiet_sessions_are_not_said_to_ask_agda_nothing(built) -> None:
    # The eleven sessions ran `check_file`, which asks Agda; what they did
    # not do is ask anything before it.
    html = " ".join(built["html"].split())
    assert "no Agda query at all" not in html
    assert "asking Agda nothing before its final check (read the file, " \
        "edit it, check it)" in html


def test_data_written_under_another_schema_is_refused(tmp_path) -> None:
    # Copilot's third review of PR #217: the renderer rendered whatever data
    # it was handed.  A numbers file in the shape written before Issue #215
    # (no control, no archive size) made a page that said "110 sessions
    # ended at a cap or a crash" and "0 files"; a file of another schema is
    # now refused, naming `make demo-data` as the remedy.
    data = tmp_path / "data"
    assert build_data(REPO, data).is_ok
    numbers_file = data / "numbers.json"
    numbers = json.loads(numbers_file.read_text(encoding="utf-8"))
    stale = {key: value for key, value in numbers.items()
             if key not in ("control", "archive")}
    numbers_file.write_text(
        json.dumps({**stale, "schema": "agda-native-air.demo.numbers.v0"}),
        encoding="utf-8")
    outcome = build_site(REPO, data, tmp_path / "site")
    assert outcome.is_err
    assert "numbers.json is schema 'agda-native-air.demo.numbers.v0'" in \
        str(outcome.unwrap_err())
    assert "make demo-data" in str(outcome.unwrap_err())

    numbers_file.write_text(json.dumps(numbers), encoding="utf-8")
    first = json.loads((data / "manifest.json")
                       .read_text(encoding="utf-8"))["replays"][0]["file"]
    replay = json.loads((data / first).read_text(encoding="utf-8"))
    (data / first).write_text(
        json.dumps({**replay, "schema": "agda-native-air.demo.replay.v0"}),
        encoding="utf-8")
    outcome = build_site(REPO, data, tmp_path / "site")
    assert outcome.is_err
    assert f"{first} is schema 'agda-native-air.demo.replay.v0'" in \
        str(outcome.unwrap_err())


# ------------------------------------- the composition tier (Issue #224)

def _composition(built) -> Element:
    return next(r for r in _regions(built)
                if r.attrs.get("id") == "composition")


def _plain(fragment: str) -> str:
    """A fragment of the page as a reader reads it, in document order: the
    tags dropped, the entities decoded, and the whitespace collapsed.
    `Element.text` gathers an element's own text before its children's,
    which is out of order around inline markup."""
    return " ".join(unescape(re.sub(r"<[^>]+>", "", fragment)).split())


def _said(built, region: Element) -> str:
    """What a region says, read from the page's own markup."""
    return _plain(_markup(built, region))


def _markup(built, region: Element) -> str:
    """The markup of an element with an id, cut out of the page."""
    html = built["html"]
    ident = region.attrs["id"]
    start = html.index(f'id="{ident}"')
    start = html.rindex("<", 0, start)
    tag = region.tag
    depth, at = 0, start
    pattern = re.compile(rf"<(/?){tag}\b[^>]*>")
    for match in pattern.finditer(html, start):
        depth += -1 if match.group(1) else 1
        if depth == 0:
            return html[start:match.end()]
    raise AssertionError(f"<{tag} id={ident}> is not closed")


def test_the_composition_table_is_the_adrs(built) -> None:
    comp = built["data"]["numbers"]["composition"]
    table = _table(built, "composition")
    assert set((table.attrs.get("data-runs") or "").split()) == \
        set(COMPOSITION_RUNS)
    rows = [el for el in table.walk() if el.tag == "tr"
            and any(c.tag == "th" and c.attrs.get("scope") == "row"
                    for c in el.children)]
    printed = [[c.text for c in row.children if c.tag in ("td", "th")]
               for row in rows]
    assert printed == [[r["name"], *r["cells"]] for r in comp["table"]]
    assert printed[0][0] == "run"
    assert [r[0] for r in printed[1:]] == [
        "final file checks, statement kept", "solved",
        "lost to the preservation gate", "lost to the isolation gate",
        "needles in the final files (of 33)",
        "rows on the gold's whole route", "turns", "USD (list)"]
    links = [el.attrs.get("href") or "" for el in table.walk()
             if el.tag == "a"]
    assert any(link.endswith("#" + render.anchor(
        render.ADR_SECTIONS["composition"])) for link in links)


def test_the_composition_region_prints_no_mined_arms_figures(built) -> None:
    # The control rule of Issue #215 is about the mined arms; this section
    # prints the six composition arms, all of them, and no mined arm.
    runs = _runs_in(_composition(built))
    assert runs == set(COMPOSITION_RUNS)
    assert not runs & {SONNET_RUN, OPUS_RUN, SHELL_RUN, MCP_RUN, BOTH_RUN}


def test_a_composition_panel_names_its_needles_and_no_original(built) -> None:
    panels = _players(built)[1].by_class("replay-panel")
    for panel, replay in zip(panels, built["data"]["composition"]):
        terms = [dt.text for dt in panel.walk() if dt.tag == "dt"]
        assert "the needles" in terms
        assert "the library original" not in terms
        facts = panel.by_class("facts")[0].text
        for needle in replay["obligation"]["needles"]:
            assert needle in facts
    # No sentence written for a row with an original lands here: `original`
    # is null on every composition row, and a template that printed "no call
    # named the file that holds it" would be lying.
    said = _said(built, _composition(built))
    for original in ({"inView": False, "reads": 0, "refusedReads": 0},
                     {"inView": True}, {"reads": 1}, {"refusedReads": 1}):
        sentence = re.sub(r"<[^>]+>", "", render.reading(original)
                          .replace("&rsquo;", "’"))
        assert sentence not in said
    assert "the file that holds it" not in said


def test_every_needle_line_links_the_answer_it_names(built) -> None:
    panels = _players(built)[1].by_class("replay-panel")
    checked = 0
    for panel, replay in zip(panels, built["data"]["composition"]):
        block = _markup(built, panel)
        needles_at = block.index('<div class="needles">')
        items = re.findall(r"<li>(.*?)</li>",
                           block[needles_at:block.index("</div>",
                                                        needles_at)])
        assert len(items) == len(replay["needles"])
        ids = {el.attrs.get("id") for el in panel.walk()}
        steps = replay["session"]["steps"]
        calls = [at for at, s in enumerate(steps) if s["kind"] == "call"]
        for item, found in zip(items, replay["needles"]):
            line = _plain(item)
            assert line.startswith(found["name"] + ":")
            links = re.findall(r'href="([^"]+)"', item)
            if found["origin"] == "never":
                assert not links and "never named in the session" in line
                continue
            at = calls[found["call"] - 1]
            assert links == [f"#answer-{panel.attrs['id'][13:]}-{at}"]
            assert links[0][1:] in ids
            assert steps[at]["display"] == found["label"]
            assert f"call {found['call']}" in line
            assert ("the final file uses it" in line) == found["used"]
            checked += 1
    assert checked == 5


def test_the_composition_findings_still_hold(built) -> None:
    # The premises of the section's qualitative sentences, read from the
    # data and the archive; if a re-judge moves one, the sentence has to be
    # rewritten rather than republished.
    comp = built["data"]["numbers"]["composition"]
    table = {r["key"]: dict(zip((c["column"] for c in comp["columns"]),
                                r["cells"])) for r in comp["table"]}
    rows = comp["rows"]
    assert all(int(n) == rows for n in table["checks"].values())
    lost = sum(int(n) for n in table["preservation"].values()) + \
        sum(int(n) for n in table["isolation"].values())
    assert lost == sum(rows - int(n) for n in table["solved"].values())
    assert all(table["preservation"][c] == "0"
               for c in ("opus shell", "opus mcp", "opus both"))
    # "each an edited using list": every preservation loss names an
    # `open … using` line of the fixture as the line that changed.
    for column, run in zip(table["run"], table["run"].values()):
        report = json.loads((REPO / ARCHIVE / run / "report.json")
                            .read_text(encoding="utf-8"))
        for o in report["outcomes"]:
            if o.get("gate") == "preservation":
                assert o["agdaExit"] == 0 and o["statement"]["equal"]
                assert re.search(r"open .* using \(", o["gateDetail"]), \
                    (run, o["benchmarkId"], o["gateDetail"])
    first = [e for arm in comp["arms"]
             for e in arm["provenance"]["subjectFirst"]]
    assert len(first) == 3 and {e["label"] for e in first} == \
        {"search_by_name"}
    assert all(s["solved"] == 0 for s in comp["loop"]["sweeps"])
    # "Sonnet stayed on the gold's route": its server arm's route is longer
    # than any Opus arm's.
    assert int(table["route"]["sonnet mcp"]) > max(
        int(table["route"][c])
        for c in ("opus shell", "opus mcp", "opus both"))
    said = _said(built, _composition(built))
    assert "The tier is at both models’ ceiling" in said
    assert "All 72 final files type-check" in said
    assert "No row is one that one configuration proves and another cannot" \
        in said
    assert "all but three of those first appear in a tool answer" in said
    assert "each handed straight to search_by_name" in said
    assert "The search loop solves none of the twelve in three sweeps" in said
    assert "it could not tell the tools apart" in said
    assert "The last session below is one of Sonnet’s nineteen" in said


def test_the_provenance_table_is_the_datas(built) -> None:
    comp = built["data"]["numbers"]["composition"]
    table = _table(built, "provenance")
    assert "the ADR has no table of it to be checked against" in table.text
    printed = {row.children[0].text: [c.text for c in row.children[1:]]
               for row in table.walk() if row.tag == "tr"
               and row.children and row.children[0].tag == "th"
               and row.children[0].attrs.get("scope") == "row"}
    labels = dict(comp["groups"])
    for name, label in labels.items():
        counts = [str(arm["provenance"]["byGroup"][name])
                  for arm in comp["arms"]]
        if any(c != "0" for c in counts):
            assert printed[label] == counts
        else:
            assert label not in printed
    assert printed["needles"] == ["33"] * 6


def test_the_intro_and_the_nav_point_to_the_composition_tier(built) -> None:
    intro = next(r for r in _regions(built) if r.attrs.get("id") == "what")
    links = [el.attrs.get("href") for el in intro.walk() if el.tag == "a"]
    assert "#composition" in links
    assert ("with no proof on disk to copy, every configuration of both "
            "models wrote a checking proof of every row") in \
        _said(built, intro)
    nav = built["root"].by_class("jump")[0]
    assert "#composition" in [el.attrs.get("href") for el in nav.walk()
                              if el.tag == "a"]


# ------------------------- the self-review of PR #226 (Issue #224)

def test_needle_line_says_each_origin_it_can_meet() -> None:
    # The three replays reach two origins (an answer, and never); the line
    # has four branches, and each is pinned here on a synthetic session.
    steps = [{"kind": "text", "text": "reading"},
             {"kind": "call", "display": "search_by_name",
              "args": [["query", "⨅-≤"]]},
             {"kind": "call", "display": "Read",
              "args": [["file_path", "<nix>/src/Congruences.lagda.md"]]}]
    subject = render.needle_line(
        {"name": "⨅-≤", "origin": "subject", "call": 1, "used": True},
        steps, "c9")
    assert _plain(subject) == (
        "⨅-≤: first named by the session itself, in call 1, search_by_name "
        "for ⨅-≤, before any answer had shown it; the final file uses it.")
    assert 'href="#answer-c9-1"' in subject
    read = render.needle_line(
        {"name": "normalOf-mono", "origin": "answer", "call": 2,
         "located": True, "used": False}, steps, "c9")
    assert _plain(read) == (
        "normalOf-mono: first shown by the answer to call 2, Read of "
        "Congruences.lagda.md, a file an earlier definition_of answer had "
        "named; the final file does not use it.")
    assert render.needle_line({"name": "x", "origin": "never",
                               "used": False}, steps, "c9") == \
        "<code>x</code>: never named in the session; the final file does " \
        "not use it."
    # A call number the session does not have is not linked to anything.
    stray = render.needle_line({"name": "y", "origin": "answer", "call": 7,
                                "used": True}, steps, "c9")
    assert "href" not in stray


def test_the_tiers_caps_are_every_arms(built) -> None:
    # The section prints the first arm's caps as the tier's.
    arms = built["data"]["numbers"]["composition"]["arms"]
    caps = {(a["turnCap"], a["wallCapSec"], a["budgetCapUsd"]) for a in arms}
    assert caps == {(60, 1800, 6.0)}
    said = _said(built, _composition(built))
    assert "at caps of 60 turns, 1,800 seconds, and USD 6.00" in said


def test_the_two_tablists_have_names_of_their_own(built) -> None:
    names = [t.attrs.get("aria-label")
             for t in built["root"].by_class("replay-tabs")]
    assert names == ["Sessions", "Composition-tier sessions"]
    groups = [p.attrs.get("aria-label") for p in _players(built)]
    assert len(set(groups)) == 2


def test_the_gate_sentence_is_withheld_when_the_gates_fall_short(
        built) -> None:
    # "Each of the 26 rows missing from a solved count lost a gate" is the
    # record's today; if the gates stopped accounting for every unsolved
    # row (an anomaly, a crash), the page must not print it.
    numbers = json.loads(json.dumps(built["data"]["numbers"]))
    row = next(r for r in numbers["composition"]["table"]
               if r["key"] == "isolation")
    row["cells"][0] = str(int(row["cells"][0]) - 1)
    said = _plain(render._composition(numbers,
                                      built["data"]["composition"]))
    assert "lost a gate with a file that checks" not in said
    assert "and 25 of the 26 rows missing from a solved count lost a gate" \
        in said
    assert "lost a gate with a file that checks" in \
        _said(built, _composition(built))


def test_the_provenance_caption_links_the_rule_in_this_repository(
        built) -> None:
    table = _table(built, "provenance")
    links = [el.attrs.get("href") for el in table.walk() if el.tag == "a"]
    assert f"{render.REPO_URL}/blob/main/{render.NEEDLES}" in links
    assert (REPO / render.NEEDLES).is_file()
