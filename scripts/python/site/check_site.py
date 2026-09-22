#!/usr/bin/env python3
"""
File: scripts/python/site/check_site.py

Description: `make site-check`.  Two checks over a built site (Issue #169):
  that no page fetches anything from off its own origin at load, and that
  every relative link and asset reference resolves to a file in the tree.

  The first is the demo page's rule (web/README.md), extended to the whole
  site now that there is one.  Default Material emits a preconnect to
  fonts.gstatic.com and a stylesheet from fonts.googleapis.com; `font:
  false` in mkdocs.yml removes them today, and a theme upgrade could put
  them back without anyone noticing, so the check reads what was built
  rather than what was configured.  It replaces the `grep` the Pages
  workflow ran over the demo page alone, and differs from it in two ways:
  it scans stylesheets for `url()` and `@import` as well, and it lets a
  `<link>` through whose `rel` names only relations a browser never fetches
  (`canonical`, `alternate`, `prev`, `next`), which Material emits with an
  absolute URL by design.  A `<link>` with no `rel` counts as a fetch: the
  conservative reading is the one that fails.

  The second is what `mkdocs build --strict` cannot see.  MkDocs validates
  the links inside Markdown, not the theme's own markup and not the demo's,
  and neither of those has any other check.  A root-absolute link (one
  beginning with `/`) is resolved from the site root after stripping the
  site's path prefix, which the caller passes because it is a fact about
  where the site is served (`site_url` in mkdocs.yml), not about the tree.

Usage:

    PYTHONPATH=. python3 -m scripts.python.site.check_site public \\
        --site-prefix /agda-native-air/

Design Principles:
  +  Pure scanning.  `off_origin_fetches`, `css_off_origin`, and
     `unresolved_links` take text and paths and return tuples of findings;
     only `main` reads the tree and prints.
  +  A check that finds nothing to check has not passed.  Zero HTML files is
     an error, so an empty or misnamed directory cannot come back green.
  +  Findings are values, all of them at once, so one run names every
     problem rather than the first.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple
from urllib.parse import urlsplit

from scripts.python.utils.file_ops import read_text
from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
    sequence_results,
)

#: Attributes whose value the browser fetches at load, by element.  `link`
#: is handled apart, because whether its `href` is fetched depends on `rel`.
FETCHING: Dict[str, Tuple[str, ...]] = {
    "script": ("src",),
    "img": ("src", "srcset"),
    "iframe": ("src",),
    "source": ("src", "srcset"),
    "video": ("src", "poster"),
    "audio": ("src",),
    "embed": ("src",),
    "object": ("data",),
    "track": ("src",),
    "input": ("src",),
}

#: `rel` tokens of a `<link>` the browser does not fetch.  Anything else,
#: and a `<link>` with no `rel` at all, is treated as a fetch.
NON_FETCHING_RELS = frozenset({
    "canonical", "alternate", "prev", "next", "license", "author", "help",
    "search", "bookmark", "tag", "nofollow", "noopener", "noreferrer", "me",
    "external", "pingback",
})

#: A URL on another origin: absolute with an http scheme, or
#: protocol-relative.
OFF_ORIGIN = re.compile(r"^\s*(?:https?:)?//", re.IGNORECASE)

#: Schemes a link check has nothing to say about.
SKIPPED_SCHEMES = frozenset({"mailto", "tel", "javascript", "data"})

#: `url(...)` and `@import` in a stylesheet, with the URL captured.
CSS_URL = re.compile(r"""url\(\s*['"]?\s*([^'")\s]+)""", re.IGNORECASE)
CSS_IMPORT = re.compile(r"""@import\s+(?!url\()['"]([^'"]+)['"]""",
                        re.IGNORECASE)


@dataclass(frozen=True)
class Finding:
    """One thing a check objects to, with enough to find it in the tree."""

    file: str
    tag: str
    attr: str
    value: str

    def __str__(self) -> str:
        return f"{self.file}: <{self.tag} {self.attr}=\"{self.value}\">"


class _Refs(HTMLParser):
    """Every fetched reference and every link of one page, in order."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.fetched: List[Tuple[str, str, str]] = []
        self.linked: List[Tuple[str, str, str]] = []

    def handle_starttag(self, tag, attrs) -> None:  # type: ignore[override]
        found = dict(attrs)
        for attr in FETCHING.get(tag, ()):
            value = found.get(attr)
            if value is not None:
                self.fetched.extend((tag, attr, url) for url in _candidates(attr, value))
        if tag == "link" and found.get("href") is not None and _link_fetches(found.get("rel")):
            self.fetched.append((tag, "href", found["href"] or ""))
        for attr in ("href", "src", "data", "poster"):
            value = found.get(attr)
            if value is not None and (tag, attr) != ("a", "src"):
                self.linked.append((tag, attr, value))


def _candidates(attr: str, value: str) -> Tuple[str, ...]:
    """The URLs an attribute names: one, or one per `srcset` candidate."""
    if attr != "srcset":
        return (value,)
    return tuple(part.strip().split()[0]
                 for part in value.split(",") if part.strip())


def _link_fetches(rel: Optional[str]) -> bool:
    """Whether a `<link>` with this `rel` makes the browser fetch its href."""
    if rel is None:
        return True
    tokens = rel.lower().split()
    return not tokens or any(token not in NON_FETCHING_RELS for token in tokens)


def _refs(html: str) -> _Refs:
    parser = _Refs()
    parser.feed(html)
    parser.close()
    return parser


def off_origin_fetches(html: str, file: str = "") -> Tuple[Finding, ...]:
    """Every element of a page that fetches from another origin at load."""
    return tuple(Finding(file, tag, attr, value)
                 for tag, attr, value in _refs(html).fetched
                 if OFF_ORIGIN.match(value))


def css_off_origin(css: str, file: str = "") -> Tuple[Finding, ...]:
    """Every `url()` or `@import` of a stylesheet that reaches another origin."""
    urls = [("url", m.group(1)) for m in CSS_URL.finditer(css)]
    urls += [("@import", m.group(1)) for m in CSS_IMPORT.finditer(css)]
    return tuple(Finding(file, "style", kind, url)
                 for kind, url in urls if OFF_ORIGIN.match(url))


def resolve_target(reference: str, page: Path, root: Path,
                   site_prefix: str) -> Optional[Path]:
    """The file a link should name, or None when the check does not apply.

    Query and fragment are dropped; a root-absolute path is taken from the
    site root once the prefix the site is served under is stripped; a path
    ending in a slash, or naming a directory, means that directory's
    `index.html`, which is what the host serves for it.
    """
    parts = urlsplit(reference)
    if parts.scheme or parts.netloc or parts.scheme in SKIPPED_SCHEMES:
        return None
    path = parts.path
    if not path:
        return None
    if path.startswith("/"):
        if not path.startswith(site_prefix):
            return root / "<outside the site prefix>" / path.lstrip("/")
        path = path[len(site_prefix):]
        base = root
    else:
        base = page.parent
    target = (base / path) if path else base
    if path.endswith("/") or target.is_dir():
        target = target / "index.html"
    return target


def unresolved_links(html: str, page: Path, root: Path,
                     site_prefix: str = "/") -> Tuple[Finding, ...]:
    """Every link or reference of a page that names no file in the tree."""
    findings = []
    for tag, attr, value in _refs(html).linked:
        target = resolve_target(value, page, root, site_prefix)
        if target is not None and not target.is_file():
            findings.append(Finding(str(page.relative_to(root)), tag, attr, value))
    return tuple(findings)


# ------------------------------------------------------------------ the tree

def _read_all(paths: Sequence[Path]) -> Result[Tuple[Tuple[Path, str], ...], PipelineError]:
    return sequence_results([read_text(path).map(lambda text, p=path: (p, text))
                             for path in paths]).map(tuple)


def check_tree(root: Path, site_prefix: str) -> Result[Tuple[Finding, ...], PipelineError]:
    """Both checks over every page and stylesheet under `root`.

    An empty tree is an error rather than a pass: nothing was checked.
    """
    pages = sorted(root.rglob("*.html"))
    sheets = sorted(root.rglob("*.css"))
    if not pages:
        return Result.err(PipelineError(
            ErrorType.VALIDATION_ERROR,
            f"no HTML under {root}: nothing to check, so nothing passed"))

    def scan(loaded: Tuple[Tuple[Path, str], ...]) -> Tuple[Finding, ...]:
        found: List[Finding] = []
        for path, text in loaded:
            rel = str(path.relative_to(root))
            if path.suffix == ".css":
                found.extend(css_off_origin(text, rel))
            else:
                found.extend(off_origin_fetches(text, rel))
                found.extend(unresolved_links(text, path, root, site_prefix))
        return tuple(found)

    return _read_all(pages + sheets).map(scan)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check a built site: nothing fetched off-origin, every "
                    "link resolving.")
    parser.add_argument("root", type=Path, help="the built site's directory")
    parser.add_argument("--site-prefix", default="/",
                        help="the path the site is served under, for "
                             "root-absolute links (default: /)")
    args = parser.parse_args(argv)
    prefix = args.site_prefix if args.site_prefix.endswith("/") else args.site_prefix + "/"

    outcome = check_tree(args.root, prefix)
    if outcome.is_err:
        print(f"site-check: {outcome.unwrap_err()}", file=sys.stderr)
        return 1
    findings = outcome.unwrap()
    if findings:
        print(f"site-check: {len(findings)} problem(s) in {args.root}:",
              file=sys.stderr)
        for finding in findings:
            print(f"  {finding}", file=sys.stderr)
        return 1
    pages = len(list(args.root.rglob("*.html")))
    print(f"site-check: {pages} page(s) under {args.root} fetch nothing "
          f"off-origin and every link resolves")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
