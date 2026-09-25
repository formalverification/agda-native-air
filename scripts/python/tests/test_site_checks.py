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
`url()`).  The Copilot review of PR #181 found three gaps, each pinned
below: CSS inside a page (`<style>` and `style=""`) was not scanned; a link
that climbs out of the published root passed when the file existed on the
build machine; and a stylesheet's same-origin `url()` targets were never
checked to exist.

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
    unresolved_css_links,
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


def test_inline_css_is_scanned_too() -> None:
    # Review finding on PR #181: the 404 page carries its styles inline, and
    # a <style> element or a style attribute reaching another origin passed.
    html = ('<head><style>@import url("https://fonts.googleapis.com/css?family=Roboto");'
            ' .x { background: url(https://x.org/bg.png) }</style></head>'
            '<body><div style="background:url(https://x.org/a.png)">a</div>'
            '<div style="background:url(assets/local.png)">b</div></body>')
    found = off_origin_fetches(html)
    assert [(f.tag, f.attr, f.value) for f in found] == [
        ("style", "url", "https://fonts.googleapis.com/css?family=Roboto"),
        ("style", "url", "https://x.org/bg.png"),
        ("style-attribute", "url", "https://x.org/a.png"),
    ]


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
    assert outside is not None and not outside.inside


def test_a_link_that_climbs_out_of_the_root_is_a_finding_even_if_the_file_exists(tmp_path: Path) -> None:
    # Review finding on PR #181: `../README.md` from public/index.html named
    # the repository's README, which exists on the build machine and is
    # absent from the deployed tree, and the check passed.
    root = _tree(tmp_path)
    (tmp_path / "README.md").write_text("outside", encoding="utf-8")
    page = root / "index.html"
    found = unresolved_links('<a href="../README.md">up</a><a href="a/../../README.md">around</a>', page, root)
    assert [(f.value, f.reason) for f in found] == [
        ("../README.md", "escapes the published root"),
        ("a/../../README.md", "escapes the published root"),
    ]
    # Climbing and coming back is fine, and so is the root itself.
    assert unresolved_links('<a href="a/../b/">b</a><a href="a/..">root</a>', page, root) == ()


def test_inline_css_targets_are_resolved_against_the_page(tmp_path: Path) -> None:
    root = _tree(tmp_path)
    (root / "assets" / "bg.png").write_bytes(b"png")
    page = root / "a" / "index.html"
    html = ('<style>.x { background: url(../assets/bg.png) } .y { background: url(../assets/nope.png) }'
            ' .z { background: url("data:image/png;base64,AAAA") }</style>'
            '<div style="background:url(../assets/bg.png)"></div>')
    found = unresolved_links(html, page, root)
    assert [(f.tag, f.value, f.reason) for f in found] == [("style", "../assets/nope.png", "not found")]


def test_a_stylesheets_same_origin_targets_must_exist(tmp_path: Path) -> None:
    # Review finding on PR #181: fonts.css names seven WOFF2 files, and a
    # missing one passed because only off-origin URLs were looked at.
    root = _tree(tmp_path)
    fonts = root / "assets" / "fonts"
    fonts.mkdir()
    (fonts / "inter-400.woff2").write_bytes(b"woff2")
    sheet = fonts / "fonts.css"
    css = ("@font-face { src: url('inter-400.woff2') format('woff2'); }\n"
           "@font-face { src: url('inter-600.woff2?v=1') format('woff2'); }\n"
           "@import 'base.css';\n"
           "@import url(https://x.org/off.css);\n"
           ".a { background: url(data:image/png;base64,AAAA) }\n"
           ".b { background: url(/agda-native-air/assets/x.css) }\n")
    sheet.write_text(css, encoding="utf-8")
    found = unresolved_css_links(css, sheet, root, "/agda-native-air/")
    assert [(f.attr, f.value, f.reason) for f in found] == [
        ("url", "inter-600.woff2?v=1", "not found"),
        ("@import", "base.css", "not found"),
    ]
    # The off-origin import is the other check's, and it still catches it.
    assert [f.value for f in css_off_origin(css)] == ["https://x.org/off.css"]


def test_check_tree_refuses_an_empty_tree(tmp_path: Path) -> None:
    outcome = check_tree(tmp_path, "/")
    assert outcome.is_err
    assert "nothing to check" in str(outcome.unwrap_err())


def test_main_reports_every_problem_and_exits_nonzero(tmp_path: Path, capsys) -> None:
    root = _tree(tmp_path)
    assert main([str(root)]) == 0
    (root / "b" / "index.html").write_text(GOOGLE + '<a href="../zzz/">x</a>', encoding="utf-8")
    (root / "assets" / "x.css").write_text("@font-face { src: url(missing.woff2) }", encoding="utf-8")
    assert main([str(root), "--site-prefix", "/agda-native-air"]) == 1
    err = capsys.readouterr().err
    assert "fonts.googleapis.com" in err and "../zzz/" in err and "missing.woff2" in err
