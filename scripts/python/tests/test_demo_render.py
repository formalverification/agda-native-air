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

The page is built into a temporary directory, so running this suite never
disturbs a working tree.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_demo_render.py`
"""

from __future__ import annotations

import re
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Dict, List, Optional

import pytest

from scripts.python.demo import render
from scripts.python.demo.build_data import run as build_data
from scripts.python.demo.build_site import build as build_site, read_data
from scripts.python.demo.paths import check_clean
from scripts.python.demo.replays import ROSTER

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

def test_the_player_is_there_with_one_panel_per_replay(built) -> None:
    players = built["root"].by_class("replay")
    assert len(players) == 1
    panels = players[0].by_class("replay-panel")
    assert len(panels) == len(ROSTER)
    assert [el.attrs.get("data-index") for el in panels] == \
        [str(i) for i in range(len(ROSTER))]


def test_the_tablist_and_every_replay_control_ship_hidden(built) -> None:
    # A control that switches nothing should not exist on a page with no
    # script, so the script is what reveals these.
    tablist = built["root"].by_class("replay-tabs")
    assert len(tablist) == 1 and "hidden" in tablist[0].attrs
    buttons = built["root"].by_class("replay-again")
    assert len(buttons) == len(ROSTER)
    assert all("hidden" in el.attrs for el in buttons)


def test_the_tabs_are_wired_to_their_panels(built) -> None:
    tabs = built["root"].by_class("replay-tab")
    panels = built["root"].by_class("replay-panel")
    assert len(tabs) == len(panels)
    for index, (tab, panel) in enumerate(zip(tabs, panels)):
        assert tab.attrs.get("role") == "tab"
        assert panel.attrs.get("role") == "tabpanel"
        assert tab.attrs["aria-controls"] == panel.attrs["id"]
        assert panel.attrs["aria-labelledby"] == tab.attrs["id"]
        assert tab.attrs["aria-selected"] == ("true" if index == 0 else "false")
        assert ("tabindex" in tab.attrs) == (index != 0)


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


def test_the_page_carries_the_table_it_was_checked_against(built) -> None:
    total = built["data"]["numbers"]["rows"][-1]
    rows = [el for el in built["root"].walk()
            if el.tag == "tr" and "total" in el.classes]
    assert rows, "the table has no total row"
    cells = [c for c in rows[0].children if c.tag in ("td", "th")]
    printed = [c.text for c in cells]
    assert printed == ["total", "55", "8", "14", "46", "8", "54", "1"]
    assert str(total["opusSolved"]) == printed[6]


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
    tabs = built["root"].by_class("replay-tab")
    verdicts = [next(p for p in tab.by_class("pip")).classes for tab in tabs]
    gate = [i for i, cs in enumerate(verdicts) if "pip-gate" in cs]
    assert len(gate) == 1, "the page's sentence assumes exactly one refusal"
    assert f"the {render._ordinal(gate[0])} tab above" in built["html"], (
        f"the refused session is tab {gate[0] + 1}; the page says otherwise")

    panels = built["root"].by_class("replay-panel")
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
    assert len(buttons) == len(ROSTER)
    assert all("hidden" in b.attrs for b in buttons)
