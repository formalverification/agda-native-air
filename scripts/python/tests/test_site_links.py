"""
Tests for `scripts/python/site/links_hook.py`: a published page's links to
files the site does not publish.

File: scripts/python/tests/test_site_links.py

Description
-----------
The pure half of the hook.  One fixture page carries every case the hook
distinguishes: a link to a published page, which stays; to an unpublished
page beside it, a file elsewhere in the repository, and a directory, which
go to GitHub with their anchors; the same links inside a code span, a
fenced block, and a comment, which stay as written; a reference definition,
the form the ADRs cite files in; and a link whose target the repository
does not track, which fails, alone and alongside the others, naming the
line.  Then the repository view itself: what counts as tracked is git's
index, not the disk, so a gitignored file is a link to nowhere.

The build-level failure (a link to nowhere stopping `mkdocs build
--strict`) is in test_site_build.py, which needs MkDocs.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_site_links.py`
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

from scripts.python.site.links_hook import (
    INLINE,
    REFERENCE,
    Page,
    Repository,
    repository,
    resolve,
    rewrite_links,
)
from scripts.python.site.prose import prose_occurrences

ROOT = Path(__file__).resolve().parents[3]

WEB = "https://github.com/owner/repo"

REPO = Repository.of(frozenset({
    "README.md",
    "docs/index.md",
    "docs/guide.md",
    "docs/internal.md",
    "docs/adr/0001.md",
    "reports/runs/README.md",
    "reports/runs/r1/report.json",
    "tools/src/Main.hs",
}), WEB)

PUBLISHED = frozenset({"index.md", "guide.md", "adr/0001.md"})

GUIDE = Page("guide.md", "docs")
ADR = Page("adr/0001.md", "docs")


def _rewrite(page_text: str, page: Page = GUIDE):
    return rewrite_links(page_text, page, PUBLISHED, REPO)


# ------------------------------------------------------------- one link

def test_links_the_site_publishes_or_does_not_resolve_are_left_alone() -> None:
    for dest in ("adr/0001.md", "adr/0001.md#decision-1", "index.md",
                 "#local-anchor", "?q=1", "https://example.org/x.md",
                 "mailto:a@b.c", "/absolute/path"):
        assert resolve(dest, GUIDE, PUBLISHED, REPO).unwrap() == dest, dest


def test_a_file_goes_to_blob_and_a_directory_to_tree_with_the_suffix_kept() -> None:
    def url(dest: str, page: Page = GUIDE) -> str:
        return resolve(dest, page, PUBLISHED, REPO).unwrap()
    assert url("internal.md") == f"{WEB}/blob/main/docs/internal.md"
    assert url("internal.md#two--spaces") == f"{WEB}/blob/main/docs/internal.md#two--spaces"
    assert url("../README.md?plain=1") == f"{WEB}/blob/main/README.md?plain=1"
    assert url("../reports/runs/") == f"{WEB}/tree/main/reports/runs"
    assert url("../../tools/src", ADR) == f"{WEB}/tree/main/tools/src"
    assert url("<../reports/runs/README.md>") == f"{WEB}/blob/main/reports/runs/README.md"


def test_a_link_to_the_repository_root_goes_to_its_tree() -> None:
    for page, dest, suffix in ((GUIDE, "../", ""), (GUIDE, "..", ""),
                               (ADR, "../../", ""), (GUIDE, "../#readme", "#readme")):
        assert resolve(dest, page, PUBLISHED, REPO).unwrap() == f"{WEB}/tree/main{suffix}", dest


def test_a_destination_is_read_whole_through_nested_parentheses() -> None:
    repo = Repository.of(frozenset({"docs/a(b(c)).md", "docs/a)b.md"}), WEB)
    out = rewrite_links("[x](a(b(c)).md) and [y](a\\)b.md)\n", GUIDE, PUBLISHED, repo)
    assert out.unwrap() == (f"[x]({WEB}/blob/main/docs/a%28b%28c%29%29.md) and "
                            f"[y]({WEB}/blob/main/docs/a%29b.md)\n")


def test_what_is_not_a_link_or_is_nested_too_deep_is_left_to_mkdocs() -> None:
    # `[x](a(b.md)` is no link at all; nesting past PAREN_DEPTH is not read,
    # rather than read short, so MkDocs validates it as written.
    for page in ("[x](a(b.md)\n", "[x](a(b(c(d(e)))).md)\n"):
        assert _rewrite(page).unwrap() == page


def test_a_target_the_repository_does_not_track_is_an_error() -> None:
    why = resolve("../reports/runs/r2/report.json", GUIDE, PUBLISHED, REPO).unwrap_err()
    assert "reports/runs/r2/report.json" in why and "neither published nor tracked" in why
    assert "outside the repository" in resolve("../../x.md", GUIDE, PUBLISHED, REPO).unwrap_err()


# ------------------------------------------------------------- one page

FIXTURE = """\
<!-- File: docs/guide.md, see [the old guide](old.md) -->
# Guide

A published page: [ADR 0001](adr/0001.md#evidence).
An unpublished one: [internal](internal.md), and a file outside docs:
[the archive](../reports/runs/README.md#runs), and a directory:
[the runs](../reports/runs/), and an image ![plot](../reports/runs/r1/report.json).

In a code span: `[not a link](missing.md)`.

```md
[also not a link](missing-too.md)
```

[`README.md`]: ../README.md
[ADR]: adr/0001.md
"""


def test_the_fixture_page_is_rewritten_link_by_link() -> None:
    out = _rewrite(FIXTURE).unwrap()
    assert "[ADR 0001](adr/0001.md#evidence)" in out
    assert f"[internal]({WEB}/blob/main/docs/internal.md)" in out
    assert f"[the archive]({WEB}/blob/main/reports/runs/README.md#runs)" in out
    assert f"[the runs]({WEB}/tree/main/reports/runs)" in out
    assert f"![plot]({WEB}/blob/main/reports/runs/r1/report.json)" in out
    assert f"[`README.md`]: {WEB}/blob/main/README.md" in out
    assert "[ADR]: adr/0001.md" in out
    # Code and comments are as written, broken links and all.
    assert "`[not a link](missing.md)`" in out
    assert "[also not a link](missing-too.md)" in out
    assert "see [the old guide](old.md) -->" in out


def test_a_link_to_nowhere_fails_the_page_naming_its_line() -> None:
    broken = FIXTURE + "\nAnd [a run that was never archived](../reports/runs/r9/).\n"
    problems = _rewrite(broken).unwrap_err()
    assert len(problems) == 1
    assert problems[0].startswith("guide.md:18: ../reports/runs/r9/ resolves to reports/runs/r9")


def test_every_link_to_nowhere_on_a_page_is_named() -> None:
    problems = _rewrite("[a](gone.md)\n\n[b]: ../also/gone.md\n").unwrap_err()
    assert [p.split(":")[1] for p in problems] == ["1", "3"]


def test_a_page_with_nothing_to_rewrite_is_returned_as_is() -> None:
    page = "Only [a published page](index.md) and <https://example.org>.\n"
    assert _rewrite(page).unwrap() == page


# ------------------------------------------------------- the repository

def _git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


@pytest.fixture()
def repo_dir(tmp_path: Path) -> Path:
    _git(tmp_path, "init", "-q")
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "page.md").write_text("x", encoding="utf-8")
    (tmp_path / "data" / "made").mkdir(parents=True)
    (tmp_path / "data" / "made" / "out.json").write_text("{}", encoding="utf-8")
    (tmp_path / ".gitignore").write_text("data/made/\n", encoding="utf-8")
    _git(tmp_path, "add", "docs", ".gitignore")
    return tmp_path


def test_the_repository_is_what_git_tracks_not_what_is_on_disk(repo_dir: Path) -> None:
    repository.cache_clear()
    repo = repository(repo_dir, WEB + "/").unwrap()
    assert repo.web_root == WEB
    assert "docs/page.md" in repo.files and "docs" in repo.directories
    # On disk, and gitignored: a link to it would 404 on GitHub.
    assert (repo_dir / "data" / "made" / "out.json").is_file()
    assert "data/made/out.json" not in repo.files
    assert "neither published nor tracked" in resolve(
        "../data/made/out.json", Page("page.md", "docs"), frozenset(), repo).unwrap_err()


def test_a_directory_that_is_not_a_repository_is_an_error(tmp_path: Path) -> None:
    repository.cache_clear()
    listing = repository(tmp_path / "nowhere", WEB)
    assert listing.is_err and "with git" in str(listing.unwrap_err())


# ------------------------------------------ against Python-Markdown itself

#: Pages on which the hook must find exactly the relative links the site's
#: own Markdown renders, no more (a link in code) and no fewer (a link a
#: stray backtick seemed to hide).
DIFFERENTIAL = {
    "parentheses, one level": "[x](a(b).md)\n",
    "parentheses, three levels": "[x](a(b(c(d))).md)\n",
    "an unbalanced parenthesis": "[x](a(b.md)\n",
    "a title with parentheses": '[x](y.md "t (a)")\n',
    "an escaped parenthesis": "[x](a\\)b.md)\n",
    "an image": "![x](y.png)\n",
    "a span across a paragraph's lines": "see `a\nb` and [x](y.md)\n",
    "a span across two list items": "+  see `a\n+  [x](y.md) and `b\n",
    "a span across numbered items": "1. a `b\n2. [x](y.md) c`\n",
    "a span across a list continuation": "+  see `a\n   [x](y.md) b`\n",
    "a span leaving a heading": "# a `b [x](y.md)\nc`\n",
    "a span across a blockquote's lines": "> a `b\n> [x](y.md) c`\n",
    "a span across table rows": "| a `b | c |\n|---|---|\n| [x](y.md) ` | d |\n",
    "an unclosed backtick": "a `b [x](y.md)\n",
    "double backticks across lines": "``a\n` [x](y.md) b``\n",
    "a fence inside a list item": "+  a\n\n   ```\n   [x](y.md)\n   ```\n",
    "a reference definition": "[t][lbl]\n\n[lbl]: y.md\n",
    "an indented code block": pytest.param(
        "para\n\n    [x](y.md)\n\nafter\n",
        marks=pytest.mark.xfail(strict=True, reason="indented code blocks are "
                                "not masked (prose.py says why)")),
}


@pytest.mark.parametrize("page", list(DIFFERENTIAL.values()), ids=list(DIFFERENTIAL))
def test_the_hook_reads_the_links_the_sites_markdown_makes(page: str) -> None:
    markdown = pytest.importorskip("markdown")
    config = pytest.importorskip("mkdocs.config").load_config(str(ROOT / "mkdocs.yml"))
    html = markdown.Markdown(extensions=config["markdown_extensions"],
                             extension_configs=config["mdx_configs"]).convert(page)
    rendered = sorted(url for url in re.findall(r'<(?:a|img) [^>]*(?:href|src)="([^"]*)"', html)
                      if not url.startswith("#"))
    found = sorted(re.sub(r"\\(.)", r"\1", o.text)
                   for o in prose_occurrences(page, INLINE, "dest")
                   + prose_occurrences(page, REFERENCE, "dest"))
    assert found == rendered
