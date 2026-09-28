#!/usr/bin/env python3
"""
File: scripts/python/site/links_hook.py

Description: The MkDocs hook that sends a published page's links to
  unpublished files to GitHub (Issue #171).

  The site publishes a curated part of docs/ (`exclude_docs` in mkdocs.yml),
  and the pages it publishes were written for a reader on GitHub: they link
  relatively into the rest of the repository (`../reports/agent-bench/`,
  `../../agda-mcp/README.md`, the contributors' files beside them).  On
  GitHub those links work; on the site they would be 404s, and under
  `--strict` a link to an excluded page fails the build.  The sources stay
  as they are, which is right for their GitHub readers; this hook rewrites
  each such link at build time, before MkDocs validates links, as follows:

    +  A relative link whose target is a file the site publishes is left
       alone, and MkDocs validates it (anchors included) as usual.
    +  A relative link whose target is anything else in the repository is
       rewritten to that file or directory on GitHub, on `main`, the branch
       the site is deployed from: `blob/main/<path>` for a file,
       `tree/main/<path>` for a directory, with its anchor and query kept.
       An anchor into an unpublished page is GitHub's own slug, which is
       what the source was written against.
    +  A relative link whose target is not in the repository fails the
       build, naming the page, the line, the link, and where it resolved.

  "In the repository" means tracked by git (`git ls-files`), not present on
  disk: a gitignored file, such as the demo's generated `data/demo/`, exists
  on the machine that builds the site and not on GitHub.  A link to a
  directory is in the repository when a tracked file is under it.

  Only prose is read (`prose.py`): a link inside a code span, a fenced code
  block, or an HTML comment is an example or a note and is left as written.
  Both link forms are rewritten: the inline `[text](target)` and `![alt]
  (target)`, and the reference definition `[label]: target`, which is how
  the ADRs and the results guide cite files.  Raw HTML links are not; no
  published page has one, and `make site-check` reads every link in the
  built tree whatever wrote it.

Design Principles:
  +  Pure core.  `rewrite_links` takes the page text, where the page is,
     what the site publishes, and what the repository tracks, and returns
     the new text or every problem; the MkDocs edge gathers those inputs.
  +  One read of the repository per build.  `repository` is memoized on
     the repository root and cleared by `on_pre_build`, so `mkdocs serve` sees
     a file added between rebuilds.
"""

from __future__ import annotations

import posixpath
import re
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import AbstractSet, Any, FrozenSet, Tuple
from urllib.parse import quote, unquote, urlsplit

# MkDocs imports a hook by file path, not as a module of a package; see
# demo_hook.py, which does the same.
REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.python.site.prose import (  # noqa: E402
    Occurrence,
    front_matter_lines,
    prose_occurrences,
    splice,
)
from scripts.python.utils.command_runner import run_command  # noqa: E402
from scripts.python.utils.pipeline_types import (  # noqa: E402
    ErrorType,
    PipelineError,
    Result,
)

#: The branch a rewritten link points into: the one the site deploys from,
#: so a reader who follows a link sees the tree the page was built from.
BRANCH = "main"

#: An inline link's or image's destination: after `](`, either `<...>` or a
#: run without spaces whose parentheses balance one level deep.
INLINE = re.compile(
    r"(?<!\\)\]\(\s*(?P<dest><[^<>\n]*>|[^\s()<>]+(?:\([^\s()<>]*\)[^\s()<>]*)*)")

#: A reference definition's destination, at the start of a line.
REFERENCE = re.compile(
    r"^[ \t]*\[[^\]\n]+\]:[ \t]*(?P<dest><[^<>\n]*>|\S+)", re.MULTILINE)


@dataclass(frozen=True)
class Repository:
    """What GitHub shows: the tracked files and the directories above them,
    as paths from the repository root, and where to link them."""

    files: FrozenSet[str]
    directories: FrozenSet[str]
    web_root: str
    """`https://github.com/<owner>/<repo>`, without a trailing slash."""

    @staticmethod
    def of(files: AbstractSet[str], web_root: str) -> "Repository":
        """The view of a listing: every proper ancestor of a tracked file is
        a directory GitHub shows."""
        return Repository(
            frozenset(files),
            frozenset("/".join(parts[:n]) for path in files
                      for parts in [path.split("/")]
                      for n in range(1, len(parts))),
            web_root.rstrip("/"))

    def url(self, path: str, kind: str, suffix: str) -> str:
        return f"{self.web_root}/{kind}/{BRANCH}/{quote(path)}{suffix}"


@dataclass(frozen=True)
class Page:
    """Where a page is: its path under the docs directory, and the docs
    directory's path from the repository root."""

    src_uri: str
    docs_dir: str


def _is_relative(dest: str) -> bool:
    """A link MkDocs would resolve against the page: no scheme, no host, not
    root-absolute, and not only an anchor or a query."""
    parts = urlsplit(dest)
    return not (parts.scheme or parts.netloc or dest.startswith(("/", "\\"))
                or not parts.path)


def _suffix(dest: str) -> str:
    """The query and anchor of a destination, as written."""
    parts = urlsplit(dest)
    return (f"?{parts.query}" if parts.query else "") + \
        (f"#{parts.fragment}" if parts.fragment else "")


def resolve(dest: str, page: Page, published: AbstractSet[str],
            repo: Repository) -> Result[str, str]:
    """What one destination becomes: itself when MkDocs should have it (not
    relative, or published), a GitHub URL, or why it can be neither."""
    bare = dest[1:-1] if dest.startswith("<") and dest.endswith(">") else dest
    if not _is_relative(bare):
        return Result.ok(dest)
    path = unquote(urlsplit(bare).path)
    in_docs = posixpath.normpath(posixpath.join(posixpath.dirname(page.src_uri), path))
    if in_docs in published:
        return Result.ok(dest)
    in_repo = posixpath.normpath(posixpath.join(page.docs_dir, in_docs))
    if in_repo == ".." or in_repo.startswith("../"):
        return Result.err(f"resolves to {in_repo}, outside the repository")
    if in_repo in repo.files:
        return Result.ok(repo.url(in_repo, "blob", _suffix(bare)))
    if in_repo in repo.directories:
        return Result.ok(repo.url(in_repo, "tree", _suffix(bare)))
    return Result.err(f"resolves to {in_repo}, which is neither published "
                      f"nor tracked in the repository")


def rewrite_links(markdown: str, page: Page, published: AbstractSet[str],
                  repo: Repository, first_line: int = 1) -> Result[str, Tuple[str, ...]]:
    """The page with every relative link to an unpublished target rewritten
    to GitHub, or every link that resolves to nothing.

    `first_line` is the file's line number of the text's first line, since
    MkDocs strips the front matter before a hook sees the page.
    """
    found = prose_occurrences(markdown, INLINE, "dest") + \
        prose_occurrences(markdown, REFERENCE, "dest")
    resolved = [(occurrence, resolve(occurrence.text, page, published, repo))
                for occurrence in found]
    problems = tuple(f"{page.src_uri}:{occurrence.line + first_line - 1}: {occurrence.text} "
                     f"{result.unwrap_err()}"
                     for occurrence, result in resolved if result.is_err)
    if problems:
        return Result.err(problems)
    edits: Tuple[Tuple[Occurrence, str], ...] = tuple(
        (occurrence, result.unwrap()) for occurrence, result in resolved
        if result.unwrap() != occurrence.text)
    return Result.ok(splice(markdown, edits))


# ---------------------------------------------------------- the repository

def _paths(listing: str) -> FrozenSet[str]:
    """The paths of a `git ls-files -z` listing."""
    return frozenset(path for path in listing.split("\0") if path)


@lru_cache(maxsize=4)
def repository(root: Path, web_root: str) -> Result[Repository, PipelineError]:
    """The files git tracks under `root`, and the directories above them."""
    return (run_command(["git", "ls-files", "-z"], cwd=root,
                        capture_output=True, text=True)
            .map(lambda process: Repository.of(_paths(process.stdout), web_root))
            .map_err(lambda e: PipelineError(
                ErrorType.COMMAND_FAILED,
                f"cannot list the repository's files under {root} with git; "
                f"the site's links to unpublished files are resolved against "
                f"what git tracks ({e.message})")))


# ------------------------------------------------------------ the MkDocs edge

def on_pre_build(config: Any) -> None:
    """Forget the last build's listing, for `mkdocs serve`."""
    repository.cache_clear()


def on_page_markdown(markdown: str, page: Any, config: Any, files: Any) -> str:
    """Rewrite the page's links to unpublished files, or fail the build."""
    from mkdocs.exceptions import PluginError

    if not config.repo_url:
        raise PluginError("links: mkdocs.yml sets no repo_url to link unpublished files to")
    root = Path(config.config_file_path).resolve().parent
    repo = repository(root, config.repo_url)
    if repo.is_err:
        raise PluginError(str(repo.unwrap_err()))
    published = frozenset(f.src_uri for f in files
                          if not f.inclusion.is_excluded())
    docs_dir = Path(config.docs_dir).resolve().relative_to(root).as_posix()
    result = rewrite_links(markdown, Page(page.file.src_uri, docs_dir),
                           published, repo.unwrap(),
                           front_matter_lines(page.file.content_string) + 1)
    if result.is_err:
        raise PluginError("links to nowhere:\n  " + "\n  ".join(result.unwrap_err()))
    return result.unwrap()
