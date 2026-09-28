#!/usr/bin/env python3
"""
File: scripts/python/site/figures_hook.py

Description: The MkDocs hook that reads a page's figures from the archived
  run reports, so that no figure on the site is typed by hand where it could
  be read (Issue #171).

  The demo page's PR description drifted from the record three times
  (#166), and a landing page that quotes solve counts would drift the same
  way.  So a page does not type a figure; it names one, and this hook
  substitutes the value at build time from the committed report that holds
  it, or fails the build.  A marker is written as follows:

      @fig(agent-opus5-1 /totals/solved)

  The first word is a run id, the directory of the run under
  `reports/agent-bench/`; the second is either a JSON pointer (RFC 6901)
  into that run's `report.json`, or the name of a derived figure below.  A
  pointer spells a `/` inside a key as `~1`, so the solved count of the
  `agda-algebras/using` stratum is `/perStratum/agda-algebras~1using/solved`.
  The run id stays in the page's source, so the source cites its figures.

  A figure that is not one field of a report is computed by one named
  function in `DERIVED`, with a test, and never in the page.  The hard tier
  is why: its archived reports count 8, 14, and 8 solved, because the
  isolation gate refuses a shell command that leaves the protocol, while
  what every arm achieved is a final file that type-checks with its
  statement kept, 14 of 14, which is an outcome-level count that no field
  of the report holds.

  The marker was chosen so that it cannot occur where a page has other
  business: `@fig` is not an Agda attribute, so it is a parse error in Agda
  source, and `{{ }}`, the obvious template syntax, is how Agda writes
  instance arguments.  The hook also looks only at prose (`prose.py`), and
  only on a page that opts in with `figures: true` in its front matter; a
  marker on a page that has not opted in is itself a build failure, because
  it would otherwise be published as the literal marker.

  The hook fails the build, naming every problem on the page, when a marker
  is malformed, names a run with no report, names a field the report does
  not have, or resolves to anything but a count.

Design Principles:
  +  Pure core.  `substitute_figures` takes the page text, whether it opted
     in, and a report loader, and returns the new text or every problem;
     `on_page_markdown` only supplies the loader and turns the problems
     into a `PluginError`.
  +  Counts only.  A figure is an integer, never a float or a string, so a
     page cannot quote a cost with an accidental twelve digits or a field
     that happens to be a label; a new kind of figure is a new function in
     `DERIVED`, with its own test.
"""

from __future__ import annotations

import re
import sys
from dataclasses import replace
from functools import reduce
from pathlib import Path
from typing import Any, Callable, Dict, FrozenSet, List, Mapping, Optional, Tuple

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
from scripts.python.utils.file_ops import load_json  # noqa: E402
from scripts.python.utils.pipeline_types import (  # noqa: E402
    PipelineError,
    Result,
)

#: Where the runs are, relative to the configuration file.
RUNS_DIR = Path("reports") / "agent-bench"

#: The front-matter key a page sets to `true` to have its markers read.
OPT_IN = "figures"

#: A whole marker, and the start of one, which is how a malformed marker is
#: found: every start must begin a whole marker.
MARKER = re.compile(r"(?P<marker>@fig\((?P<body>[^()\n]*)\))")
MARKER_START = re.compile(r"(?P<start>@fig\()")

#: A marker's body: a run id, then a selector.  The run id is a directory
#: name and nothing else, so a marker cannot reach outside `RUNS_DIR`.
BODY = re.compile(r"\s*(?P<run>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?P<selector>\S+)\s*")

#: The server's knowledge tools, the ones that answer a question and give no
#: verdict (docs/reading-the-results.md § 3).  The verdict tools are
#: check_file, fill_hole, get_diagnostics, and check_project.
KNOWLEDGE_TOOLS: FrozenSet[str] = frozenset({
    "get_goal", "type_of", "normalize", "resolve_name", "definition_of",
    "exports_of", "search_by_name", "search_by_type", "get_dependencies",
    "search_in_scope",
})

#: How the harness names a server tool in `perTool`.
SERVER_TOOL_PREFIX = "mcp__agda__"

Report = Mapping[str, Any]
Outcomes = List[Mapping[str, Any]]
Loader = Callable[[str], Result[Report, PipelineError]]


# ------------------------------------------------------------ JSON pointers

def _unescape(token: str) -> str:
    """One reference token of a JSON pointer, unescaped (RFC 6901 § 4)."""
    return token.replace("~1", "/").replace("~0", "~")


def _step(value: Any, token: str) -> Result[Any, str]:
    """Descend one reference token."""
    if isinstance(value, Mapping):
        return (Result.ok(value[token]) if token in value
                else Result.err(f"no key {token!r}"))
    if isinstance(value, list) and re.fullmatch(r"0|[1-9][0-9]*", token):
        index = int(token)
        return (Result.ok(value[index]) if index < len(value)
                else Result.err(f"no index {index}"))
    return Result.err(f"cannot descend into a {type(value).__name__} with {token!r}")


def resolve_pointer(document: Any, pointer: str) -> Result[Any, str]:
    """The value a JSON pointer names in `document`, or why there is none.

    A value of `null` is a value here; `count` refuses it.
    """
    if pointer == "":
        return Result.ok(document)
    if not pointer.startswith("/"):
        return Result.err(f"a JSON pointer begins with '/': {pointer!r}")
    # A fold whose first failure is carried to the end: `and_then` passes an
    # error on untouched.
    return reduce(
        lambda acc, token: acc.and_then(lambda value: _step(value, token)),
        (_unescape(token) for token in pointer[1:].split("/")),
        Result.ok(document))


def count(value: Any) -> Result[int, str]:
    """`value` as a figure: an integer, and nothing else (not a boolean)."""
    if isinstance(value, int) and not isinstance(value, bool):
        return Result.ok(value)
    return Result.err(f"is {json_kind(value)}, not a count")


def json_kind(value: Any) -> str:
    """How a value reads in a message."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return f"the boolean {str(value).lower()}"
    if isinstance(value, (int, float)):
        return f"the number {value}"
    if isinstance(value, str):
        return f"the string {value!r}"
    return f"a {type(value).__name__}"


# ---------------------------------------------------------- derived figures

def _outcomes(report: Report) -> Result[Outcomes, str]:
    """The report's per-obligation outcomes."""
    outcomes = report.get("outcomes")
    if isinstance(outcomes, list) and all(isinstance(o, Mapping) for o in outcomes):
        return Result.ok(outcomes)
    return Result.err("the report has no outcomes list")


def _every(outcomes: Outcomes, key: str) -> Result[Outcomes, str]:
    """The outcomes, if every one of them carries `key`."""
    missing = [o.get("benchmarkId", "?") for o in outcomes if key not in o]
    return (Result.ok(outcomes) if not missing
            else Result.err(f"{len(missing)} outcome(s) have no {key!r}, "
                            f"first {missing[0]}"))


def final_checks_statement_kept(report: Report) -> Result[int, str]:
    """Rows whose final file type-checks under the judge with its statement
    kept: `agdaExit` 0 and the statement reading `equal`.

    This is the hard tier's headline (docs/reading-the-results.md § 4.5),
    which `solved` is not: a row can earn it and still fail the isolation
    gate, which judges the session and not the file.
    """
    def kept(outcome: Mapping[str, Any]) -> bool:
        statement = outcome.get("statement")
        return (outcome.get("agdaExit") == 0 and isinstance(statement, Mapping)
                and statement.get("equal") is True)
    return (_outcomes(report)
            .and_then(lambda os: _every(os, "agdaExit"))
            .and_then(lambda os: _every(os, "statement"))
            .map(lambda os: sum(1 for o in os if kept(o))))


def rows_with_original(report: Report) -> Result[int, str]:
    """Rows whose index entry names the library lemma they restate, which
    the judge marks with a non-null `original`."""
    return (_outcomes(report).and_then(lambda os: _every(os, "original"))
            .map(lambda os: sum(1 for o in os if o["original"] is not None)))


def rows_without_original(report: Report) -> Result[int, str]:
    """Rows with no original to find: the standard-library tiers on the
    mined suite, and every posed row."""
    return (_outcomes(report).and_then(lambda os: _every(os, "original"))
            .map(lambda os: sum(1 for o in os if o["original"] is None)))


def solved_with_original(report: Report) -> Result[int, str]:
    """Solves among the rows that have an original, the denominator of the
    report's `solvedOriginalInView`."""
    return (_outcomes(report).and_then(lambda os: _every(os, "original"))
            .and_then(lambda os: _every(os, "solved"))
            .map(lambda os: sum(1 for o in os
                                if o["original"] is not None and o["solved"] is True)))


def knowledge_tool_calls(report: Report) -> Result[int, str]:
    """Calls to the server's knowledge tools (`KNOWLEDGE_TOOLS`) over the
    whole run, from `perTool`."""
    per_tool = report.get("perTool")
    if not isinstance(per_tool, Mapping):
        return Result.err("the report has no perTool object")
    return Result.ok(sum(
        calls for name, calls in per_tool.items()
        if name.startswith(SERVER_TOOL_PREFIX)
        and name[len(SERVER_TOOL_PREFIX):] in KNOWLEDGE_TOOLS))


#: The derived figures, by the name a marker uses.
DERIVED: Dict[str, Callable[[Report], Result[int, str]]] = {
    "final-checks-statement-kept": final_checks_statement_kept,
    "rows-with-original": rows_with_original,
    "rows-without-original": rows_without_original,
    "solved-with-original": solved_with_original,
    "knowledge-tool-calls": knowledge_tool_calls,
}


def figure(report: Report, selector: str) -> Result[int, str]:
    """The figure a selector names in one run's report."""
    if selector.startswith("/"):
        return resolve_pointer(report, selector).and_then(count)
    if selector in DERIVED:
        return DERIVED[selector](report)
    return Result.err(f"{selector!r} is neither a JSON pointer nor a derived "
                      f"figure ({', '.join(sorted(DERIVED))})")


# --------------------------------------------------------------- the page

def _problem(where: str, line: int, text: str, why: str) -> str:
    return f"{where}:{line}: {text}: {why}"


def substitute_figures(markdown: str, opted_in: bool, loader: Loader,
                       where: str = "page",
                       first_line: int = 1) -> Result[str, Tuple[str, ...]]:
    """The page with every marker replaced by its figure, or every problem.

    `where` names the page in the problems, and `first_line` is the file's
    line number of the text's first line (MkDocs strips the front matter).
    A page that has not opted in must carry no marker at all.
    """
    shift = first_line - 1
    starts = [replace(s, line=s.line + shift)
              for s in prose_occurrences(markdown, MARKER_START, "start")]
    markers = [replace(m, line=m.line + shift)
               for m in prose_occurrences(markdown, MARKER, "marker")]
    if not opted_in:
        return (Result.ok(markdown) if not starts else Result.err(tuple(
            _problem(where, s.line, "@fig(", f"a figure marker on a page that "
                     f"does not set `{OPT_IN}: true`") for s in starts)))
    whole = {m.start for m in markers}
    malformed = tuple(_problem(where, s.line, "@fig(", "not closed on its line")
                      for s in starts if s.start not in whole)
    bodies = [(marker, BODY.fullmatch(marker.text[len("@fig("):-1]))
              for marker in markers]
    # Each run's report is read once, however many figures the page takes
    # from it.
    reports: Dict[str, Result[Report, PipelineError]] = {
        run: loader(run) for run in {body["run"] for _, body in bodies if body}}

    def value(marker: Occurrence, body: Optional["re.Match[str]"]) -> Result[str, str]:
        if body is None:
            return Result.err(_problem(where, marker.line, marker.text,
                                       "expected @fig(<run-id> <pointer or name>)"))
        run, selector = body["run"], body["selector"]
        return (reports[run]
                .map_err(lambda e: f"no report for run {run!r} ({e.message})")
                .and_then(lambda report: figure(report, selector))
                .map(str)
                .map_err(lambda why: _problem(where, marker.line, marker.text, why)))

    values = [(marker, value(marker, body)) for marker, body in bodies]
    problems = malformed + tuple(v.unwrap_err() for _, v in values if v.is_err)
    if problems:
        return Result.err(problems)
    return Result.ok(splice(markdown, [(marker, v.unwrap()) for marker, v in values]))


def report_loader(root: Path) -> Loader:
    """Read a run's report from under `root`."""
    return lambda run: load_json(root / RUNS_DIR / run / "report.json")


# ------------------------------------------------------------ the MkDocs edge

def on_page_markdown(markdown: str, page: Any, config: Any, files: Any) -> str:
    """Substitute the page's figures, or fail the build naming every problem."""
    from mkdocs.exceptions import PluginError

    root = Path(config.config_file_path).resolve().parent
    result = substitute_figures(markdown, page.meta.get(OPT_IN) is True,
                                report_loader(root), page.file.src_uri,
                                front_matter_lines(page.file.content_string) + 1)
    if result.is_err:
        raise PluginError("figures:\n  " + "\n  ".join(result.unwrap_err()))
    return result.unwrap()
