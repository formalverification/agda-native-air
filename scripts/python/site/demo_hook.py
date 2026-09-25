#!/usr/bin/env python3
"""
File: scripts/python/site/demo_hook.py

Description: The MkDocs hook that carries the demo page into the site
  (Issue #169).

  The demo page (Issue #85) is a standalone HTML document with its own
  stylesheet and script, rendered by `make demo` into its own directory and
  pinned by 74 tests against the file that generator writes.  It is not a
  Markdown page and must not be re-rendered as one: a second rendering path
  would be a second thing to keep true, and its replay script listens for
  `DOMContentLoaded`, which Material's instant navigation never fires again
  after the first page.  So the site carries the built page in verbatim,
  under `demo/`, and links to it as a document of its own.

  Two events:

    on_files   Registers every file of the built demo with MkDocs as a
               generated file under `demo/`, backed by the file the demo
               build wrote.  MkDocs then copies each one into the site byte
               for byte, and a Markdown link to `demo/index.html` is
               validated like any other.  Nothing is generated into `docs/`,
               so nothing generated is committed.
    on_nav     Appends the Demo link to the navigation.  Written in `nav:`,
               a relative link is a `--strict` failure, because MkDocs
               cannot find it among the documentation files; added here,
               after that validation has run, it is rendered relative to
               each page like every other entry.  Material's instant
               navigation leaves it alone: the bundle fetches the sitemap
               and intercepts only the URLs it lists, and the demo is not a
               page, so a click is the full page load the demo's script
               needs.

  The hook refuses to build a site whose demo is missing.  `make site` runs
  `make demo` first; running `mkdocs build` by hand without it fails here,
  naming the fix, rather than publishing a Demo link that leads nowhere.

Design Principles:
  +  Pure planning, effectful edge.  `demo_files` decides what is copied
     where and returns a `Result`; the two `on_*` functions only hand that
     plan to MkDocs, and turn an error into a `PluginError`, which is how a
     hook fails a build.
  +  The demo directory comes from the configuration (`extra.demo_dir`,
     which mkdocs.yml reads from `AIR_DEMO_DIR` with `site` as the default),
     resolved against the configuration file, so the tests can point a
     build at a temporary demo without touching the working tree.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Optional, Tuple

# MkDocs imports a hook by file path, not as a module of a package, so the
# repository root is on sys.path only if the caller put it there.  The utils
# package is imported through the root, so the root is added here, from this
# file's own location, before anything else is imported.
REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.python.utils.pipeline_types import (  # noqa: E402
    ErrorType,
    PipelineError,
    Result,
)

#: Where the demo lands in the published tree, and what the nav calls it.
DEMO_PREFIX = "demo"
DEMO_TITLE = "Demo"

#: The file the demo build always writes; its absence means no build ran.
DEMO_INDEX = "index.html"

#: The demo directory when the configuration names none.  It matches the
#: Makefile's DEMO_SITE_DIR and build_site.py's DEFAULT_OUT.
DEFAULT_DEMO_DIR = "site"


@dataclass(frozen=True)
class Placement:
    """One file of the built demo and where it goes in the site."""

    src_uri: str
    """The path under the site, `demo/assets/demo.css` for instance."""

    source: Path
    """The file the demo build wrote, copied verbatim."""


def demo_files(demo_dir: Path) -> Result[Tuple[Placement, ...], PipelineError]:
    """Every file of the built demo, and where each one is published.

    The page itself has to be there; everything else in the directory rides
    along, so an asset the demo build adds later is carried in without a
    change here.
    """
    if not (demo_dir / DEMO_INDEX).is_file():
        return Result.err(PipelineError(
            ErrorType.FILE_NOT_FOUND,
            f"no built demo at {demo_dir / DEMO_INDEX}; run `make demo` "
            f"first.  The site carries the demo page in verbatim and will "
            f"not publish a Demo link that leads nowhere."))
    files = sorted(path for path in demo_dir.rglob("*") if path.is_file())
    return Result.ok(tuple(
        Placement(f"{DEMO_PREFIX}/{path.relative_to(demo_dir).as_posix()}",
                  path)
        for path in files))


def demo_dir_of(config_file: str, extra: Optional[Mapping[str, Any]]) -> Path:
    """The demo directory the configuration names, resolved against it."""
    named = str((extra or {}).get("demo_dir") or DEFAULT_DEMO_DIR)
    return (Path(config_file).resolve().parent / named).resolve()


def demo_link_url() -> str:
    """The nav entry's URL, relative to the site root.

    A trailing slash rather than `index.html`: the host serves the
    directory, and the shorter form is the one a reader sees and repeats.
    """
    return f"{DEMO_PREFIX}/"


# ------------------------------------------------------------ the MkDocs edge

def on_files(files: Any, config: Any) -> Any:
    """Register the built demo's files with MkDocs, or fail the build."""
    from mkdocs.exceptions import PluginError
    from mkdocs.structure.files import File, InclusionLevel

    plan = demo_files(demo_dir_of(config.config_file_path, config.get("extra")))
    if plan.is_err:
        raise PluginError(str(plan.unwrap_err()))
    for placement in plan.unwrap():
        files.append(File.generated(
            config, placement.src_uri,
            abs_src_path=str(placement.source),
            inclusion=InclusionLevel.INCLUDED))
    return files


def on_nav(nav: Any, config: Any, files: Any) -> Any:
    """Append the Demo link after MkDocs has validated the configured nav."""
    from mkdocs.structure.nav import Link

    nav.items.append(Link(DEMO_TITLE, demo_link_url()))
    return nav
