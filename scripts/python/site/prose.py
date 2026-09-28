#!/usr/bin/env python3
"""
File: scripts/python/site/prose.py

Description: Which characters of a Markdown page are prose, for the site's
  two source-rewriting hooks (Issue #171).

  `figures_hook.py` substitutes figure markers and `links_hook.py` rewrites
  relative links, both in a page's Markdown before MkDocs renders it.
  Neither may touch code: a benchmark page quotes Agda, whose instance
  arguments are written `{{ }}`, and a documentation page quotes Markdown
  and shell whose link syntax is the example, not a link.  So both hooks
  look for their pattern in a masked copy of the page, in which every
  character inside code or an HTML comment is replaced by `MASK` and every
  newline is kept, and then edit the original at the positions they found.
  The copy has the original's length, so a position in one is a position in
  the other.

  What is masked, as follows:

    fenced code blocks   A line opening with three or more backticks or
                         tildes, at any indentation (a fence inside a list
                         item is indented), through the line that closes it
                         with the same character, at least as many times;
                         an unclosed fence runs to the end of the page, as
                         in CommonMark.
    code spans           A run of n backticks through the next run of
                         exactly n, within one inline context: not across a
                         blank line, not into a line that starts a list
                         item, a heading, or a table row, and not out of a
                         heading or a table row, which are one line long.
                         Python-Markdown parses inline markup block by
                         block, so a backtick in one list item does not
                         pair with one in the next.  A fenced block is not
                         a break: SuperFences stashes it inside the
                         surrounding paragraph, so a backtick before it
                         pairs with one after it, in Markdown and here.  A
                         backslash before the opening run escapes it.
    HTML comments        `<!--` through `-->`, which is where this
                         repository's documents keep their `File:` headers.

  Code spans and comments are found by one left-to-right scan, so a
  backtick inside a comment opens nothing and a `<!--` inside a code span
  opens nothing.

  Not masked: indented code blocks.  Telling one from a list item's
  continuation needs the whole block structure, and this repository's
  documents fence their code; a page that indents a code block containing a
  link or a marker would have it rewritten.  The site's link check
  (`check_site.py`) still reads every link in the built pages.

Design Principles:
  +  Pure.  Text in, text or occurrences out; nothing here reads a file.
  +  One canonical notion of prose for both hooks, so a code sample that is
     safe from one is safe from the other.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from functools import reduce
from typing import Optional, Sequence, Tuple

#: What a masked character becomes.  NUL occurs in no document, matches no
#: pattern a hook looks for, and is not whitespace.
MASK = "\x00"

#: A fence's opening line: three or more backticks or tildes, then an info
#: string.  A backtick fence's info string may not contain a backtick.
FENCE_OPEN = re.compile(r"^[ \t]*(?P<fence>`{3,}|~{3,})(?P<info>[^\n]*)$")

#: What a newline that ends an inline context becomes while code spans are
#: scanned, a character no span may contain; it is a newline again after.
BREAK = "\x01"

#: A line that starts a block of its own, so no code span continues into
#: it: a list item, a heading, or a table row.
BLOCK_START = re.compile(r"[ \t]*(?:[+*-][ \t]|\d+[.)][ \t]|#|\|)")

#: A block that is one line long, so no code span continues out of it.
ONE_LINE_BLOCK = re.compile(r"[ \t]*(?:#|\|)")

#: A code span or an HTML comment, whichever begins first.  A comment may
#: cross a `BREAK`; a code span may not.
SPAN_OR_COMMENT = re.compile(
    r"(?P<comment><!--.*?-->)"
    r"|(?<![`\\])(?P<ticks>`+)(?!`)[^\x01]+?(?<!`)(?P=ticks)(?!`)",
    re.DOTALL)

#: A front-matter block at the top of a page, as MkDocs recognizes it
#: (mkdocs.utils.meta.YAML_RE).  MkDocs hands a hook the page without it.
FRONT_MATTER = re.compile(r"^-{3}[ \t]*\n(.*?\n)(?:\.{3}|-{3})[ \t]*\n", re.DOTALL)

#: An open fence: its character and its length.
Fence = Tuple[str, int]


@dataclass(frozen=True)
class Occurrence:
    """One match of a pattern's group in prose, with where it is."""

    start: int
    end: int
    text: str
    line: int
    """1-based, for messages."""


def _blank(text: str) -> str:
    """`text` with every character but a line break replaced by `MASK`."""
    return re.sub(r"[^\n\x01]", MASK, text)


def _fence_step(state: Tuple[Optional[Fence], Tuple[bool, ...]],
                line: str) -> Tuple[Optional[Fence], Tuple[bool, ...]]:
    """One line of the fence scan: the fence open after it, and whether it
    is code (a fence line counts as code)."""
    fence, flags = state
    body = line.rstrip("\n")
    if fence is None:
        opened = FENCE_OPEN.match(body)
        if opened and not (opened["fence"][0] == "`" and "`" in opened["info"]):
            return (opened["fence"][0], len(opened["fence"])), flags + (True,)
        return None, flags + (False,)
    char, length = fence
    closes = re.fullmatch(rf"[ \t]*{re.escape(char)}{{{length},}}[ \t]*", body)
    return (None if closes else fence), flags + (True,)


def _mask_fences(markdown: str) -> str:
    """The page with its fenced code blocks masked."""
    lines = markdown.splitlines(keepends=True)
    _, flags = reduce(_fence_step, lines, (None, ()))
    return "".join(_blank(line) if code else line
                   for line, code in zip(lines, flags))


def _ends_inline(line: str, following: str) -> bool:
    """Whether the newline between two lines ends an inline context."""
    return (not line.strip() or not following.strip()
            or ONE_LINE_BLOCK.match(line) is not None
            or BLOCK_START.match(following) is not None)


def _mark_breaks(text: str) -> str:
    """`text` with each newline that ends an inline context replaced by
    `BREAK`, one character for one, so positions do not move."""
    lines = text.split("\n")
    return lines[0] + "".join(
        (BREAK if _ends_inline(line, following) else "\n") + following
        for line, following in zip(lines, lines[1:]))


def code_mask(markdown: str) -> str:
    """The page with every character of code and comments masked.

    Same length as the input, newlines where the input has them.
    """
    return SPAN_OR_COMMENT.sub(lambda match: _blank(match.group(0)),
                               _mark_breaks(_mask_fences(markdown))
                               ).replace(BREAK, "\n")


def prose_occurrences(markdown: str, pattern: "re.Pattern[str]",
                      group: str) -> Tuple[Occurrence, ...]:
    """Every match of `pattern` in the page's prose, as the span of `group`.

    The pattern is matched against the masked copy, so a match can never
    begin inside code; the group should be one that cannot extend into
    code either (a link's destination, not its label), and an occurrence
    whose group reaches into masked text is dropped rather than edited.
    """
    masked = code_mask(markdown)
    return tuple(
        Occurrence(match.start(group), match.end(group), match.group(group),
                   masked.count("\n", 0, match.start(group)) + 1)
        for match in pattern.finditer(masked)
        if match.group(group) is not None and MASK not in match.group(group))


def splice(markdown: str, edits: Sequence[Tuple[Occurrence, str]]) -> str:
    """The page with each occurrence's span replaced by its new text.

    The occurrences must not overlap, which `prose_occurrences` of one
    pattern guarantees.
    """
    ordered = sorted(edits, key=lambda edit: edit[0].start)
    bounds = [0] + [pos for occurrence, _ in ordered
                    for pos in (occurrence.start, occurrence.end)] + [len(markdown)]
    kept = [markdown[bounds[i]:bounds[i + 1]] for i in range(0, len(bounds), 2)]
    return "".join(piece for pair in zip(kept, [new for _, new in ordered] + [""])
                   for piece in pair)


def front_matter_lines(source: str) -> int:
    """How many lines of the page's file precede the Markdown MkDocs hands
    a hook, so that a problem can name the line in the file."""
    match = FRONT_MATTER.match(source)
    return source.count("\n", 0, match.end()) if match else 0
