#!/usr/bin/env python3
"""
File: scripts/python/site/check_site.py

Description: `make site-check`.  Two checks over a built site (Issue #169):
  that no page or stylesheet fetches anything from off its own origin at
  load, and that every relative link and asset reference resolves to a file
  inside the published tree.

  The first is the demo page's rule (web/README.md), extended to the whole
  site now that there is one.  Default Material emits a preconnect to
  fonts.gstatic.com and a stylesheet from fonts.googleapis.com; `font:
  false` in mkdocs.yml removes them today, and a theme upgrade could put
  them back without anyone noticing, so the check reads what was built
  rather than what was configured.  It replaces the `grep` the Pages
  workflow ran over the demo page alone, and differs from it in three ways:
  it scans CSS as well as markup, wherever CSS occurs (standalone
  stylesheets, `<style>` elements, and `style` attributes, since the 404
  page carries its styles inline); it lets a `<link>` through whose `rel`
  names only relations a browser never fetches (`canonical`, `alternate`,
  `prev`, `next`), which Material emits with an absolute URL by design; and
  a `<link>` with no `rel` counts as a fetch, because the conservative
  reading is the one that fails.

  The second is what `mkdocs build --strict` cannot see.  MkDocs validates
  the links inside Markdown, not the theme's own markup, not the demo's,
  and not a stylesheet's `url()`, and none of those has any other check.  A
  reference resolves only if it names a file inside the published root: a
  path that climbs out of the tree (`../../README.md`) may exist on the
  build machine and still be absent from what is deployed, so it is a
  finding of its own.  A root-absolute link (one beginning with `/`) is
  resolved from the site root after stripping the site's path prefix,
  which the caller passes because it is a fact about where the site is
  served (`site_url` in mkdocs.yml), not about the tree.

Usage:

    PYTHONPATH=. python3 -m scripts.python.site.check_site public \\
        --site-prefix /agda-native-air/

Design Principles:
  +  Pure scanning.  `off_origin_fetches`, `css_off_origin`,
     `unresolved_links`, and `unresolved_css_links` take text and paths and
     return tuples of findings; only `main` reads the tree and prints.
  +  A check that finds nothing to check has not passed.  Zero HTML files is
     an error, so an empty or misnamed directory cannot come back green.
  +  Findings are values, all of them at once, so one run names every
     problem rather than the first, and each says why it is one.
"""

from __future__ import annotations

import argparse
import os
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

#: `url(...)` and `@import` in CSS, with the URL captured.
CSS_URL = re.compile(r"""url\(\s*['"]?\s*([^'")\s]+)""", re.IGNORECASE)
CSS_IMPORT = re.compile(r"""@import\s+(?!url\()['"]([^'"]+)['"]""",
                        re.IGNORECASE)

#: How a reference reached the page: the `<style>` element and the `style`
#: attribute are reported under these tags, so a finding says where to look.
STYLE_ELEMENT = "style"
STYLE_ATTRIBUTE = "style-attribute"


@dataclass(frozen=True)
class Finding:
    """One thing a check objects to, with enough to find it in the tree."""

    file: str
    tag: str
    attr: str
    value: str
    reason: str = "not found"

    def __str__(self) -> str:
        return f"{self.file}: <{self.tag} {self.attr}=\"{self.value}\"> {self.reason}"


@dataclass(frozen=True)
class Resolution:
    """Where a same-origin reference points, and whether that is inside."""

    target: Path
    inside: bool


class _Refs(HTMLParser):
    """Every fetched reference, every link, and every piece of CSS of one page."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.fetched: List[Tuple[str, str, str]] = []
        self.linked: List[Tuple[str, str, str]] = []
        self.css: List[Tuple[str, str]] = []
        self._in_style = False

    def handle_starttag(self, tag, attrs) -> None:  # type: ignore[override]
        found = dict(attrs)
        for attr in FETCHING.get(tag, ()):
            value = found.get(attr)
            if value is not None:
                self.fetched.extend((tag, attr, url) for url in _candidates(attr, value))
        if tag == "link" and found.get("href") is not None and _link_fetches(found.get("rel")):
            self.fetched.append((tag, "href", found["href"] or ""))
        # Every reference a page makes, for resolution: the four plain
        # attributes, and each candidate of a `srcset`, which names one
        # asset per density and has to resolve one by one.
        for attr in ("href", "src", "data", "poster", "srcset"):
            value = found.get(attr)
            if value is not None and (tag, attr) != ("a", "src"):
                self.linked.extend((tag, attr, url) for url in _candidates(attr, value))
        if found.get("style"):
            self.css.append((STYLE_ATTRIBUTE, found["style"] or ""))
        if tag == "style":
            self._in_style = True

    def handle_endtag(self, tag) -> None:  # type: ignore[override]
        if tag == "style":
            self._in_style = False

    def handle_data(self, data) -> None:  # type: ignore[override]
        if self._in_style and data.strip():
            self.css.append((STYLE_ELEMENT, data))


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


def css_urls(css: str) -> Tuple[Tuple[str, str], ...]:
    """Every URL a piece of CSS names, as (how, url): `url` or `@import`."""
    return tuple([("url", m.group(1)) for m in CSS_URL.finditer(css)]
                 + [("@import", m.group(1)) for m in CSS_IMPORT.finditer(css)])


# -------------------------------------------------------------- off-origin

def off_origin_fetches(html: str, file: str = "") -> Tuple[Finding, ...]:
    """Every fetch a page makes from another origin at load.

    Markup and CSS alike: the elements that fetch, and every `url()` or
    `@import` inside a `<style>` element or a `style` attribute.
    """
    refs = _refs(html)
    found = [Finding(file, tag, attr, value, "off-origin")
             for tag, attr, value in refs.fetched if OFF_ORIGIN.match(value)]
    for where, css in refs.css:
        found.extend(Finding(file, where, how, url, "off-origin")
                     for how, url in css_urls(css) if OFF_ORIGIN.match(url))
    return tuple(found)


def css_off_origin(css: str, file: str = "") -> Tuple[Finding, ...]:
    """Every `url()` or `@import` of a stylesheet that reaches another origin."""
    return tuple(Finding(file, STYLE_ELEMENT, how, url, "off-origin")
                 for how, url in css_urls(css) if OFF_ORIGIN.match(url))


# ------------------------------------------------------------------- links

def resolve_target(reference: str, base_file: Path, root: Path,
                   site_prefix: str) -> Optional[Resolution]:
    """The file a same-origin reference should name, or None when the check
    does not apply (another origin, a scheme with no file behind it, a bare
    fragment).

    Query and fragment are dropped; a root-absolute path is taken from the
    site root once the prefix the site is served under is stripped, and one
    under a different prefix leads off the site; a path ending in a slash,
    or naming a directory, means that directory's `index.html`, which is
    what the host serves for it.  The target is normalized, so `..` is
    followed, and `inside` says whether it stayed under `root`.
    """
    parts = urlsplit(reference)
    if parts.scheme or parts.netloc or parts.scheme in SKIPPED_SCHEMES:
        return None
    path = parts.path
    if not path:
        return None
    if path.startswith("/"):
        if not path.startswith(site_prefix):
            return Resolution(root / path.lstrip("/"), inside=False)
        path = path[len(site_prefix):]
        base = root
    else:
        base = base_file.parent
    target = Path(os.path.normpath(base / path)) if path else base
    inside = _within(target, root)
    if inside and (path.endswith("/") or target.is_dir()):
        target = target / "index.html"
    return Resolution(target, inside)


def _within(target: Path, root: Path) -> bool:
    """Whether `target` is `root` or below it, by path, not by symlink."""
    try:
        return os.path.commonpath([os.path.normpath(root), target]) == os.path.normpath(root)
    except ValueError:  # different drives, on a platform that has them
        return False


def _problem(resolution: Optional[Resolution]) -> Optional[str]:
    """Why a resolved reference is a finding, or None if it resolves."""
    if resolution is None:
        return None
    if not resolution.inside:
        return "escapes the published root"
    if not resolution.target.is_file():
        return "not found"
    return None


def unresolved_links(html: str, page: Path, root: Path,
                     site_prefix: str = "/") -> Tuple[Finding, ...]:
    """Every link or reference of a page that names no file in the tree.

    Markup and inline CSS alike: the elements' `href`, `src`, `data`, and
    `poster`, each candidate of a `srcset`, and every same-origin `url()` or
    `@import` in a `<style>` element or a `style` attribute, resolved
    against the page.
    """
    refs = _refs(html)
    rel = str(page.relative_to(root))
    findings = []
    for tag, attr, value in refs.linked:
        why = _problem(resolve_target(value, page, root, site_prefix))
        if why:
            findings.append(Finding(rel, tag, attr, value, why))
    for where, css in refs.css:
        for how, url in css_urls(css):
            why = _problem(resolve_target(url, page, root, site_prefix))
            if why:
                findings.append(Finding(rel, where, how, url, why))
    return tuple(findings)


def unresolved_css_links(css: str, sheet: Path, root: Path,
                         site_prefix: str = "/") -> Tuple[Finding, ...]:
    """Every same-origin `url()` or `@import` of a stylesheet that names no
    file in the tree, resolved against the stylesheet's own directory, which
    is how a browser resolves them."""
    rel = str(sheet.relative_to(root))
    findings = []
    for how, url in css_urls(css):
        why = _problem(resolve_target(url, sheet, root, site_prefix))
        if why:
            findings.append(Finding(rel, STYLE_ELEMENT, how, url, why))
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
                found.extend(unresolved_css_links(text, path, root, site_prefix))
            else:
                found.extend(off_origin_fetches(text, rel))
                found.extend(unresolved_links(text, path, root, site_prefix))
        return tuple(found)

    return _read_all(pages + sheets).map(scan)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check a built site: nothing fetched off-origin, every "
                    "link and asset reference resolving inside the tree.")
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
    sheets = len(list(args.root.rglob("*.css")))
    print(f"site-check: {pages} page(s) and {sheets} stylesheet(s) under "
          f"{args.root} fetch nothing off-origin, and every reference "
          f"resolves inside the tree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
