"""
Tests for the built site: `mkdocs build --strict` around the demo.

File: scripts/python/tests/test_site_build.py

Description
-----------
The whole-site build, run the way `make site` runs it, into a temporary
tree, and then the properties the site is published on:

+  The demo page is carried in verbatim: every file `make demo-site` wrote
   is under `demo/`, byte for byte, and nothing else is.
+  Nothing published is fetched from off the origin, and every link and
   asset reference resolves, over every page and stylesheet.
+  The allowlist holds: the only pages are the landing page, the 404, and
   the demo; nothing internal from `docs/` is published.
+  The Demo link is in the nav, the demo is not in the sitemap (so
   Material's instant navigation does not intercept the link), the site
   opens dark, and the repository chip carries no API fetch.

The build needs `mkdocs` on `PATH`, which `nix develop .#site` and the pip
fallback both provide; the module is skipped where it is absent, and the
Pages workflow runs it where it is not.  The demo is built through its own
Python API into the same temporary tree, so the suite never touches the
working tree's `site/` or `public/`.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_site_build.py`
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List

import pytest

from scripts.python.demo.build_data import run as build_data
from scripts.python.demo.build_site import build as build_demo
from scripts.python.site.check_site import (
    css_off_origin,
    off_origin_fetches,
    unresolved_links,
)

REPO = Path(__file__).resolve().parents[3]

MKDOCS = shutil.which("mkdocs")
pytestmark = pytest.mark.skipif(
    MKDOCS is None, reason="mkdocs is not on PATH; `nix develop .#site` provides it")


def _site_url_path() -> str:
    """The path component of mkdocs.yml's site_url, for root-absolute links."""
    text = (REPO / "mkdocs.yml").read_text(encoding="utf-8")
    match = re.search(r"^site_url:\s*(\S+)", text, re.M)
    assert match, "mkdocs.yml sets no site_url"
    return "/" + match.group(1).split("/", 3)[3]


@pytest.fixture(scope="module")
def built(tmp_path_factory) -> Dict[str, Any]:
    base = tmp_path_factory.mktemp("site")
    data, demo, public = base / "data", base / "demo", base / "public"
    made = build_data(REPO, data)
    assert made.is_ok, str(made.unwrap_err())
    page = build_demo(REPO, data, demo)
    assert page.is_ok, str(page.unwrap_err())
    env = {**os.environ, "AIR_DEMO_DIR": str(demo)}
    run = subprocess.run(
        [str(MKDOCS), "build", "--strict", "--quiet",
         "-f", str(REPO / "mkdocs.yml"), "-d", str(public)],
        cwd=REPO, env=env, capture_output=True, text=True)
    assert run.returncode == 0, run.stderr
    return {"demo": demo, "public": public,
            "index": (public / "index.html").read_text(encoding="utf-8"),
            "prefix": _site_url_path()}


def _pages(public: Path) -> List[Path]:
    return sorted(public.rglob("*.html"))


# -------------------------------------------------------- the demo, verbatim

def test_the_demo_is_carried_in_byte_for_byte(built) -> None:
    demo, public = built["demo"], built["public"]
    written = sorted(p.relative_to(demo) for p in demo.rglob("*") if p.is_file())
    carried = sorted(p.relative_to(public / "demo")
                     for p in (public / "demo").rglob("*") if p.is_file())
    assert written == carried
    for rel in written:
        assert (public / "demo" / rel).read_bytes() == (demo / rel).read_bytes(), rel


def test_nothing_generated_lands_in_the_source_tree(built) -> None:
    # The hook registers the demo's files from where the demo build wrote
    # them; MkDocs must not have needed a copy under docs/.
    assert not (REPO / "docs" / "demo").exists()


# ---------------------------------------------------- what it is published on

def test_no_page_or_stylesheet_fetches_off_origin(built) -> None:
    public = built["public"]
    problems = []
    for page in _pages(public):
        problems += off_origin_fetches(page.read_text(encoding="utf-8"),
                                       str(page.relative_to(public)))
    for sheet in sorted(public.rglob("*.css")):
        problems += css_off_origin(sheet.read_text(encoding="utf-8"),
                                   str(sheet.relative_to(public)))
    assert not problems, [str(p) for p in problems]
    assert _pages(public), "no pages were built"


#: A reference to Google's font hosts that a browser would follow: an
#: attribute value or a CSS `url()`.  Prose that names the host, such as the
#: comment at the top of fonts.css saying why it is not used, is not one.
GOOGLE_FONTS_REF = re.compile(
    rb"""(?:(?:href|src)\s*=\s*["']?|url\(\s*["']?)(?:https?:)?//fonts\.(?:googleapis|gstatic)\.com""")


def test_no_google_fonts_reference_anywhere_in_the_tree(built) -> None:
    hits = [p for p in built["public"].rglob("*")
            if p.is_file() and p.suffix in {".html", ".css", ".js"}
            and GOOGLE_FONTS_REF.search(p.read_bytes())]
    assert not hits, hits
    # The pattern has teeth: what default Material emits is caught.
    assert GOOGLE_FONTS_REF.search(
        b'<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Roboto">')
    assert GOOGLE_FONTS_REF.search(b"@import url(https://fonts.googleapis.com/css2?family=Inter);")
    assert not GOOGLE_FONTS_REF.search(b"/* no <link> to fonts.googleapis.com here */")


def test_every_link_and_asset_reference_resolves(built) -> None:
    public = built["public"]
    problems = []
    for page in _pages(public):
        problems += unresolved_links(page.read_text(encoding="utf-8"), page,
                                     public, built["prefix"])
    assert not problems, [str(p) for p in problems]


# ------------------------------------------------------------- the allowlist

def test_only_the_landing_page_the_404_and_the_demo_are_published(built) -> None:
    public = built["public"]
    pages = {str(p.relative_to(public)) for p in _pages(public)}
    assert pages == {"index.html", "404.html", "demo/index.html"}, pages
    for internal in ("GITHUB_PROJECT", "PLAN", "WORKFLOW", "README", "feedback", "notes"):
        assert not (public / internal).exists(), internal


# ------------------------------------------------------- the nav and the look

def test_the_demo_is_in_the_nav_and_out_of_the_sitemap(built) -> None:
    hrefs = re.findall(r'<a\s+href="([^"]+)"\s+class="md-nav__link"', built["index"])
    assert "demo/" in hrefs, hrefs
    sitemap = (built["public"] / "sitemap.xml").read_text(encoding="utf-8")
    assert "<loc>" in sitemap and "/demo/" not in sitemap
    assert "agda-native-air/</loc>" in sitemap


def test_the_site_opens_dark(built) -> None:
    assert 'data-md-color-scheme="slate"' in built["index"]


def test_the_repository_chip_is_a_link_and_not_a_fetch(built) -> None:
    index = built["index"]
    assert 'class="md-source"' in index
    assert 'data-md-component="source"' not in index
    assert "api.github.com" not in index


def test_the_404_is_an_open_goal_that_points_home_and_at_the_demo(built) -> None:
    page = (built["public"] / "404.html").read_text(encoding="utf-8")
    assert "{! !}" in page
    prefix = built["prefix"]
    assert f'href="{prefix}"' in page and f'href="{prefix}demo/"' in page


def test_the_self_hosted_faces_are_what_the_pages_load(built) -> None:
    index = built["index"]
    assert "assets/fonts/fonts.css" in index
    assert "stylesheets/tokens.css" in index and "stylesheets/extra.css" in index
    for face in ("inter-400.woff2", "juliamono-text.woff2", "spacegrotesk-600.woff2"):
        assert (built["public"] / "assets" / "fonts" / face).is_file(), face
