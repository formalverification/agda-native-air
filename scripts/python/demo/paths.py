#!/usr/bin/env python3
"""
File: scripts/python/demo/paths.py

Description: Turn the absolute paths an archived session recorded into
  anchored relative ones, for the demo site (Issue #85).

  Every record in `reports/agent-bench/**/transcript.jsonl` was written on the
  machine that ran the sweep, so it is full of paths under that machine's home
  directory, its Nix store, and its per-user runtime directory.  A published
  page must not carry them: they are unreadable to anyone else, and a home
  path is not something to publish.  This module is the one place that
  rewrites them, so no caller has to sprinkle `replace` calls.

  The result is not a bare relative path but an *anchored* one, prefixed by a
  marker naming what it is relative to.  A reader then knows that
  `<work>/Kernels-ker-con.agda` is the one file the subject could see and that
  `<repo>/agda-dojang/agda` is a directory of this repository, which a bare
  `Kernels-ker-con.agda` would not say.  It also makes the postcondition
  mechanical: after normalization no `/home/`, `/nix/store/`, or `/run/user/`
  remains, and a test asserts exactly that over every generated file.

Design Principles:
  +  The anchors come from the archive, never from a guess.  `PathMap.of`
     reads the repository root out of the subject's own `mcp.json` (the
     server launcher's `--cwd`) and the work directory out of the transcript's
     own `init` record (`cwd`, the client's working directory).
  +  Order is part of the contract.  The work directory sits inside the
     repository root, so its rule has to fire first or the longer path would
     be rewritten by the shorter prefix and lose its anchor.  `rules()`
     returns them in the order they must be applied and the tests pin it.
  +  Rewrite the text, not the tree.  A transcript's tool answers are JSON
     encoded inside a string, and an Agda command line embeds paths inside a
     larger sentence, so a structural walk would miss most of them.  The
     substitution is textual and applies wherever a path appears.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Dict, List, Pattern, Sequence, Tuple

from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
)

#: The anchor a path of the repository checkout is rewritten to.
REPO_ANCHOR = "<repo>"

#: The anchor a path inside the subject's staged work directory is rewritten
#: to.  The work directory held exactly one file: the obligation.
WORK_ANCHOR = "<work>"

#: `/nix/store/<32-char hash>-<name>` becomes `<nix>/<name>`.  The hash is an
#: artifact of one machine's store and says nothing to a reader; the name is
#: the package, which is the part worth keeping (`standard-library-2.3`).
NIX_STORE = re.compile(r"/nix/store/[a-z0-9]{32}-([^/\"\s]+)")

#: Any remaining absolute path under a home directory.  This is the backstop
#: for paths no anchor covers, such as the client's own spill file for an
#: over-long tool result (`/home/<user>/.claude/projects/...`).
HOME_DIR = re.compile(r"/home/[A-Za-z0-9_.-]+")

#: The per-user runtime directory, which carries a numeric uid.
RUNTIME_DIR = re.compile(r"/run/user/[0-9]+")

#: Substitutions that hold on every archive, applied after the per-subject
#: anchors.  Each is (compiled pattern, replacement).
GENERIC_RULES: Tuple[Tuple[Pattern[str], str], ...] = (
    (NIX_STORE, r"<nix>/\1"),
    (RUNTIME_DIR, "<runtime>"),
    (HOME_DIR, "~"),
)

#: Prefixes that must not survive normalization.  `check_clean` reports the
#: first one it finds, which is what the tests and the build assert on.
FORBIDDEN: Tuple[str, ...] = ("/home/", "/nix/store/", "/run/user/")


@dataclass(frozen=True)
class PathMap:
    """The absolute prefixes one archived subject's records may carry.

    `repo_root` is the checkout the sweep ran in; `work_dir` is the staged
    directory holding the single obligation file, which lies inside it.
    """

    repo_root: str
    work_dir: str

    def rules(self) -> Tuple[Tuple[Pattern[str], str], ...]:
        """Every substitution, in the order it must be applied.

        The work directory first, because it is a child of the repository
        root: rewriting the root first would leave `<repo>/data/.../work/...`
        and lose the fact that the file was the only one in the subject's
        world.  Within each anchor the slash-suffixed form comes first so the
        bare directory rule cannot eat the separator of a longer path.
        """
        anchored: List[Tuple[Pattern[str], str]] = []
        for prefix, anchor in ((self.work_dir, WORK_ANCHOR),
                               (self.repo_root, REPO_ANCHOR)):
            if not prefix:
                continue
            trimmed = prefix.rstrip("/")
            anchored.append((re.compile(re.escape(trimmed) + "/"),
                             anchor + "/"))
            anchored.append((re.compile(re.escape(trimmed)), anchor))
            # The client names its own per-session directory after the working
            # directory with every separator turned into a dash, and that
            # mangled form carries the same home path through a tool result
            # that spilled to disk.  It is derived here rather than matched by
            # hand so it can never drift from the anchor above.
            slug = trimmed.replace("/", "-")
            anchored.append((re.compile(re.escape(slug)), anchor + "-slug"))
        return tuple(anchored) + GENERIC_RULES

    @staticmethod
    def of(mcp_config: Dict[str, Any],
           init_record: Dict[str, Any]) -> Result[PathMap, PipelineError]:
        """Read the anchors out of a subject's own archived configuration.

        `mcp_config` is the subject's `mcp.json`, whose server entry carries
        the launcher's `--cwd`; `init_record` is the transcript's
        `system`/`init` line, whose `cwd` is the client's working directory
        and so the staged work directory.
        """
        servers = mcp_config.get("mcpServers")
        if not isinstance(servers, dict) or "agda" not in servers:
            return Result.err(PipelineError(
                ErrorType.PARSING_ERROR,
                "mcp.json has no `mcpServers.agda` entry to read --cwd from"))
        args = servers["agda"].get("args")
        if not isinstance(args, list):
            return Result.err(PipelineError(
                ErrorType.PARSING_ERROR,
                "mcp.json's agda server entry has no `args` list"))
        repo_root = _flag_value(args, "--cwd")
        if repo_root is None:
            return Result.err(PipelineError(
                ErrorType.PARSING_ERROR,
                "mcp.json's agda server entry passes no --cwd"))
        work_dir = init_record.get("cwd")
        if not isinstance(work_dir, str) or not work_dir:
            return Result.err(PipelineError(
                ErrorType.PARSING_ERROR,
                "the transcript's init record carries no `cwd`"))
        return Result.ok(PathMap(repo_root=repo_root, work_dir=work_dir))


def _flag_value(args: Sequence[Any], flag: str) -> Any:
    """The argument following `flag` in a command line, or None."""
    for i, arg in enumerate(args):
        if arg == flag and i + 1 < len(args):
            return args[i + 1]
    return None


def normalize_text(text: str, pmap: PathMap) -> str:
    """Rewrite every absolute path in one string, by `pmap`'s rules."""
    out = text
    for pattern, replacement in pmap.rules():
        out = pattern.sub(replacement, out)
    return out


def normalize_value(value: Any, pmap: PathMap) -> Any:
    """`normalize_text` over every string inside a parsed JSON value.

    Dictionary keys are normalized too: a key is as capable of carrying a path
    as a value is, and leaving one behind would defeat `check_clean`.
    """
    if isinstance(value, str):
        return normalize_text(value, pmap)
    if isinstance(value, list):
        return [normalize_value(v, pmap) for v in value]
    if isinstance(value, dict):
        return {normalize_text(k, pmap) if isinstance(k, str) else k:
                normalize_value(v, pmap) for k, v in value.items()}
    return value


def check_clean(text: str) -> Result[str, PipelineError]:
    """Fail if any machine-specific absolute prefix survived.

    This is the postcondition the whole module exists for, stated once so the
    build and the tests can assert the same thing.
    """
    for prefix in FORBIDDEN:
        at = text.find(prefix)
        if at != -1:
            return Result.err(PipelineError(
                ErrorType.VALIDATION_ERROR,
                f"an absolute path survived normalization: "
                f"{text[at:at + 80]!r}"))
    return Result.ok(text)
