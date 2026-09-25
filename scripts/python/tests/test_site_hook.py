"""
Tests for `scripts/python/site/demo_hook.py` and the site's committed assets.

File: scripts/python/tests/test_site_hook.py

Description
-----------
The pure half of the hook that carries the demo page into the site: the
plan it makes from a built demo directory, its refusal when there is no
built demo, and how it finds that directory from the configuration.  Then
the two facts about the committed assets that nothing else would catch: the
site's favicon is a byte-for-byte copy of the demo's, so the two pages share
a tab icon, and every self-hosted face declared in fonts.css is a committed
file, with no committed file left undeclared.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_site_hook.py`
"""

from __future__ import annotations

import re
from pathlib import Path

from scripts.python.site.demo_hook import (
    DEFAULT_DEMO_DIR,
    Placement,
    demo_dir_of,
    demo_files,
    demo_link_url,
)

REPO = Path(__file__).resolve().parents[3]


def _demo(tmp_path: Path) -> Path:
    demo = tmp_path / "demo-out"
    (demo / "assets").mkdir(parents=True)
    (demo / "index.html").write_text("<html></html>", encoding="utf-8")
    (demo / "assets" / "demo.css").write_text(":root{}", encoding="utf-8")
    (demo / "assets" / "replay.js").write_text("", encoding="utf-8")
    return demo


def test_every_file_of_the_built_demo_is_placed_under_demo(tmp_path: Path) -> None:
    demo = _demo(tmp_path)
    plan = demo_files(demo)
    assert plan.is_ok, str(plan.unwrap_err())
    assert plan.unwrap() == (
        Placement("demo/assets/demo.css", demo / "assets" / "demo.css"),
        Placement("demo/assets/replay.js", demo / "assets" / "replay.js"),
        Placement("demo/index.html", demo / "index.html"),
    )


def test_a_missing_demo_is_refused_and_names_the_fix(tmp_path: Path) -> None:
    plan = demo_files(tmp_path / "nowhere")
    assert plan.is_err
    assert "make demo" in str(plan.unwrap_err())
    # A directory with assets but no page is not a built demo either.
    half = tmp_path / "half"
    (half / "assets").mkdir(parents=True)
    (half / "assets" / "demo.css").write_text("", encoding="utf-8")
    assert demo_files(half).is_err


def test_the_demo_directory_is_read_from_the_configuration(tmp_path: Path) -> None:
    config = tmp_path / "mkdocs.yml"
    assert demo_dir_of(str(config), {"demo_dir": "build/demo"}) == (tmp_path / "build" / "demo").resolve()
    assert demo_dir_of(str(config), None) == (tmp_path / DEFAULT_DEMO_DIR).resolve()
    assert demo_dir_of(str(config), {"demo_dir": str(tmp_path / "abs")}) == (tmp_path / "abs").resolve()


def test_the_default_demo_directory_is_the_makefiles() -> None:
    makefile = (REPO / "Makefile").read_text(encoding="utf-8")
    assert re.search(rf"^DEMO_SITE_DIR\s*\?=\s*{DEFAULT_DEMO_DIR}\s*$", makefile, re.M), \
        "demo_hook.DEFAULT_DEMO_DIR and the Makefile's DEMO_SITE_DIR disagree"


def test_the_nav_link_is_the_directory_url() -> None:
    assert demo_link_url() == "demo/"


# ------------------------------------------------------ the committed assets

def test_the_site_favicon_is_the_demos() -> None:
    site = (REPO / "docs" / "assets" / "favicon.svg").read_bytes()
    demo = (REPO / "web" / "assets" / "favicon.svg").read_bytes()
    assert site == demo, "docs/assets/favicon.svg has drifted from web/assets/favicon.svg"


def test_every_declared_face_is_committed_and_every_face_is_declared() -> None:
    fonts = REPO / "docs" / "assets" / "fonts"
    css = (fonts / "fonts.css").read_text(encoding="utf-8")
    declared = set(re.findall(r"url\('([^']+\.woff2)'\)", css))
    committed = {path.name for path in fonts.glob("*.woff2")}
    assert declared, "fonts.css declares no faces"
    assert declared == committed, (sorted(declared ^ committed))
    # Every family has its license beside it.
    families = set(re.findall(r"font-family:\s*'([^']+)'", css))
    licenses = {path.name for path in fonts.glob("OFL-*.txt")}
    assert licenses == {f"OFL-{family.replace(' ', '')}.txt" for family in families}
