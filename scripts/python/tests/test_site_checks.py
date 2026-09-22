"""
Tests for `scripts/python/site/check_site.py`.

File: scripts/python/tests/test_site_checks.py

Description
-----------
The two checks `make site-check` runs over the built site, exercised on
markup written for the purpose.  The off-origin check is the gate the Pages
workflow relies on, so the first thing tested is that it has teeth: a
fabricated Google Fonts link, which is exactly what a Material upgrade with
`font: false` lost would emit, is caught.  Then what it must let through
(Material's absolute canonical link) and what it must not (a `<link>` with
no `rel`, a protocol-relative script, a `srcset` candidate, a stylesheet
`url()`).

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_site_checks.py`
"""

from __future__ import annotations

from pathlib import Path

from scripts.python.site.check_site import (
    check_tree,
    css_off_origin,
    main,
    off_origin_fetches,
    resolve_target,
    unresolved_links,
)

GOOGLE = ('<link rel="stylesheet" href="https://fonts.googleapis.com/css?'
          'family=Roboto:300,400">')
PRECONNECT = '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
CANONICAL = '<link rel="canonical" href="https://example.org/agda-native-air/">'


# ------------------------------------------------------------- off-origin

def test_the_gate_has_teeth_on_a_google_fonts_link() -> None:
    found = off_origin_fetches(f"<html><head>{GOOGLE}{PRECONNECT}</head></html>")
    assert [f.value for f in found] == [
        "https://fonts.googleapis.com/css?family=Roboto:300,400",
        "https://fonts.gstatic.com",
    ]


def test_a_canonical_link_is_metadata_not_a_fetch() -> None:
    assert off_origin_fetches(f"<head>{CANONICAL}</head>") == ()
    prev_next = ('<link rel="prev" href="https://x.org/a/">'
                 '<link rel="next" href="https://x.org/b/">')
    assert off_origin_fetches(prev_next) == ()


def test_a_link_without_rel_is_read_as_a_fetch() -> None:
    assert len(off_origin_fetches('<link href="https://x.org/a.css">')) == 1


def test_a_mixed_rel_is_a_fetch_if_any_token_fetches() -> None:
    assert len(off_origin_fetches(
        '<link rel="alternate stylesheet" href="https://x.org/a.css">')) == 1


def test_scripts_images_frames_and_srcset_are_covered() -> None:
    html = ('<script src="//cdn.example.org/x.js"></script>'
            '<img src="https://x.org/a.png">'
            '<iframe src="https://x.org/f"></iframe>'
            '<img srcset="assets/a.png 1x, https://x.org/a@2x.png 2x">'
            '<object data="HTTPS://x.org/o"></object>')
    found = off_origin_fetches(html)
    assert [(f.tag, f.value) for f in found] == [
        ("script", "//cdn.example.org/x.js"),
        ("img", "https://x.org/a.png"),
        ("iframe", "https://x.org/f"),
        ("img", "https://x.org/a@2x.png"),
        ("object", "HTTPS://x.org/o"),
    ]


def test_same_origin_and_data_urls_pass() -> None:
    html = ('<link rel="stylesheet" href="assets/demo.css">'
            '<script src="assets/replay.js" defer></script>'
            '<img src="data:image/svg+xml,%3Csvg%3E">'
            '<link rel="icon" href="../assets/favicon.svg">'
            '<a href="https://github.com/formalverification">an anchor is not a fetch</a>')
    assert off_origin_fetches(html) == ()


def test_stylesheets_are_scanned_for_url_and_import() -> None:
    css = ("@import url('https://fonts.googleapis.com/css2?family=Inter');\n"
           '@import "//x.org/b.css";\n'
           "@font-face { src: url('inter-400.woff2') format('woff2'); }\n"
           "body { background: url( \"https://x.org/bg.png\" ) }\n")
    assert [f.value for f in css_off_origin(css)] == [
        "https://fonts.googleapis.com/css2?family=Inter",
        "https://x.org/bg.png",
        "//x.org/b.css",
    ]


# ------------------------------------------------------------------- links

def _tree(tmp_path: Path) -> Path:
    root = tmp_path / "public"
    (root / "a").mkdir(parents=True)
    (root / "b").mkdir()
    (root / "assets").mkdir()
    (root / "index.html").write_text("<a href='a/'>a</a>", encoding="utf-8")
    (root / "a" / "index.html").write_text("", encoding="utf-8")
    (root / "b" / "index.html").write_text("", encoding="utf-8")
    (root / "assets" / "x.css").write_text("", encoding="utf-8")
    return root


def test_relative_links_resolve_against_the_page(tmp_path: Path) -> None:
    root = _tree(tmp_path)
    page = root / "a" / "index.html"
    html = ('<a href="../b/">ok</a><a href="..">up</a><a href=".">here</a>'
            '<link rel="stylesheet" href="../assets/x.css">'
            '<a href="../b/#frag">frag</a><a href="../b/?q=1">query</a>'
            '<a href="#top">anchor only</a><a href="mailto:x@y.z">mail</a>'
            '<a href="https://github.com/">external</a>')
    assert unresolved_links(html, page, root) == ()


def test_a_missing_target_is_reported_with_its_page(tmp_path: Path) -> None:
    root = _tree(tmp_path)
    page = root / "a" / "index.html"
    found = unresolved_links('<a href="../c/">gone</a><img src="nope.png">', page, root)
    assert [(f.file, f.tag, f.value) for f in found] == [
        ("a/index.html", "a", "../c/"), ("a/index.html", "img", "nope.png")]


def test_root_absolute_links_need_the_site_prefix(tmp_path: Path) -> None:
    root = _tree(tmp_path)
    page = root / "a" / "index.html"
    html = '<a href="/agda-native-air/b/">b</a>'
    assert unresolved_links(html, page, root, "/agda-native-air/") == ()
    # Served under a different prefix, the same link leads off the site.
    assert len(unresolved_links(html, page, root, "/")) == 1
    outside = resolve_target("/elsewhere/", page, root, "/agda-native-air/")
    assert outside is not None and not outside.exists()


def test_check_tree_refuses_an_empty_tree(tmp_path: Path) -> None:
    outcome = check_tree(tmp_path, "/")
    assert outcome.is_err
    assert "nothing to check" in str(outcome.unwrap_err())


def test_main_reports_every_problem_and_exits_nonzero(tmp_path: Path, capsys) -> None:
    root = _tree(tmp_path)
    assert main([str(root)]) == 0
    (root / "b" / "index.html").write_text(GOOGLE + '<a href="../zzz/">x</a>', encoding="utf-8")
    assert main([str(root), "--site-prefix", "/agda-native-air"]) == 1
    err = capsys.readouterr().err
    assert "fonts.googleapis.com" in err and "../zzz/" in err
