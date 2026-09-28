"""
Tests for `scripts/python/site/prose.py`: what the site's rewriting hooks
may touch.

File: scripts/python/tests/test_site_prose.py

Description
-----------
The masked copy of a page that `figures_hook.py` and `links_hook.py` search
instead of the page itself: it has the page's length and newlines, and every
character of code or of an HTML comment is masked.  Each kind of code the
module claims to recognize has a case here, and so does each thing that
looks like code and is not (an escaped backtick, a fence inside a list
item, a span that would cross a paragraph).  Then the two helpers the hooks
share: finding a pattern's group in prose, and splicing replacements back.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_site_prose.py`
"""

from __future__ import annotations

import re

from scripts.python.site.prose import (
    MASK,
    code_mask,
    front_matter_lines,
    prose_occurrences,
    splice,
)

LINK = re.compile(r"\]\((?P<dest>[^\s)]+)\)")


def _visible(text: str) -> str:
    return code_mask(text).replace(MASK, "")


def test_the_mask_keeps_length_and_newlines() -> None:
    page = "a `b`\n```\nc\n```\n<!-- d\n\n+  e -->\n+  `f\ng`\n"
    masked = code_mask(page)
    assert len(masked) == len(page)
    assert [i for i, ch in enumerate(masked) if ch == "\n"] == \
        [i for i, ch in enumerate(page) if ch == "\n"]


def test_fenced_blocks_are_masked_with_backticks_or_tildes() -> None:
    page = "keep\n```agda\nf {{ i }} = [x](y.md)\n```\nkeep too\n~~~~\n[z](w.md)\n~~~~\nend\n"
    assert _visible(page) == "keep\n\n\n\nkeep too\n\n\n\nend\n"


def test_a_fence_inside_a_list_item_is_masked() -> None:
    page = "+  item\n\n   ```sh\n   make [a](b.md)\n   ```\n\n   after\n"
    assert "[a](b.md)" not in _visible(page)
    assert "after" in _visible(page)


def test_a_fence_closes_only_on_its_own_character_and_length() -> None:
    page = "````\n```\n[a](b.md)\n~~~~\n````\n[c](d.md)\n"
    visible = _visible(page)
    assert "[a](b.md)" not in visible and "[c](d.md)" in visible


def test_an_unclosed_fence_runs_to_the_end() -> None:
    assert _visible("x\n```\n[a](b.md)\n") == "x\n\n\n"


def test_code_spans_of_one_and_two_backticks_are_masked() -> None:
    page = "a `[b](c.md)` d ``e ` [f](g.md)`` h"
    assert _visible(page) == "a  d  h"


def test_an_escaped_backtick_opens_no_span() -> None:
    page = r"a \`[b](c.md) d"
    assert "[b](c.md)" in _visible(page)


def test_a_code_span_does_not_cross_a_blank_line() -> None:
    page = "a `b\n\n[c](d.md) e`"
    assert "[c](d.md)" in _visible(page)


def test_a_code_span_stays_inside_its_inline_context() -> None:
    # Python-Markdown parses inline markup block by block: a backtick in one
    # list item, table row, or heading does not pair with one in the next.
    for page in ("+  see `a\n+  [c](d.md) and `e\n",
                 "1. a `b\n2. [c](d.md) e`\n",
                 "| a `b | c |\n|---|---|\n| [c](d.md) ` | e |\n",
                 "# a `b [c](d.md)\ne`\n"):
        assert "[c](d.md)" in _visible(page), page
    # A list item's continuation line and a blockquote's next line are the
    # same inline context, so a span does cross them.
    assert "[c](d.md)" not in _visible("+  see `a\n   [c](d.md) b`\n")
    assert "[c](d.md)" not in _visible("> a `b\n> [c](d.md) e`\n")


def test_html_comments_are_masked_and_a_backtick_in_one_opens_nothing() -> None:
    page = "<!-- File: `x` [a](b.md) -->\n[c](d.md) `e`"
    assert _visible(page) == "\n[c](d.md) "


def test_occurrences_are_found_in_prose_only_with_their_lines() -> None:
    page = "[a](one.md)\n`[b](two.md)`\n\n```\n[c](three.md)\n```\n[d](four.md)\n"
    found = prose_occurrences(page, LINK, "dest")
    assert [(o.text, o.line) for o in found] == [("one.md", 1), ("four.md", 7)]
    assert all(page[o.start:o.end] == o.text for o in found)


def test_a_label_in_code_does_not_hide_the_link() -> None:
    # The results guide's reference definitions have code-span labels.
    page = "[`agda-mcp/README.md`](../agda-mcp/README.md)"
    assert [o.text for o in prose_occurrences(page, LINK, "dest")] == \
        ["../agda-mcp/README.md"]


def test_splice_replaces_each_span_and_keeps_the_rest() -> None:
    page = "[a](one.md) and [b](two.md)."
    found = prose_occurrences(page, LINK, "dest")
    assert splice(page, [(o, o.text.upper()) for o in found]) == \
        "[a](ONE.MD) and [b](TWO.MD)."
    assert splice(page, []) == page
    # The order the edits are given in does not matter.
    assert splice(page, [(found[1], "2"), (found[0], "1")]) == "[a](1) and [b](2)."


def test_front_matter_lines_count_the_block_mkdocs_strips() -> None:
    assert front_matter_lines("---\ntitle: x\nfigures: true\n---\n# Page\n") == 4
    assert front_matter_lines("---\n# a comment\n...\nbody\n") == 3
    # A rule later in the page is not front matter.
    assert front_matter_lines("# No front matter\n\n---\n\ntext\n") == 0
