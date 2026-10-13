"""
File: scripts/python/field_report.py

Description: Field reports, one file per session (issue #252).

  A session that used the agda-mcp server for real work writes its report as
  one new file under docs/field-reports/ and submits it as a pull request of
  that one file, so that every report is reviewed before it is public and no
  report waits uncommitted in a working tree.  This script is that whole path.
  The session that runs it is usually working in another repository, so it
  runs by absolute path from any directory with the system python3:

    field_report.py new <slug>      fetch origin; make a worktree on a new
                                    branch field-report-<date>-<slug> from
                                    origin/main; write the template there
                                    with the date filled in; print its path
    field_report.py submit <path>   check the report; commit it as the
                                    branch's one commit; push; open the pull
                                    request through `gh api`; remove the
                                    worktree; print the pull request's URL
    field_report.py index           print a table of every report's header

  docs/field-reports/README.md states the rules a report must meet for the
  people who write one; `report_problems` is their executable form, and the
  two are kept in step by tests/test_field_report.py, which also runs the
  checker over every committed report.

Design notes:
  +  Pure core, effectful shell.  The parser, the checks, the names, and the
     text of the commit and the pull request are pure functions; git and gh
     run only in the functions under "Effects", through
     utils.command_runner; only `main` prints or exits.
  +  `--repo` names the checkout whose `origin` receives the branch.  It
     defaults to the checkout this file lives in, so the main checkout's copy
     works from anywhere, and a test points it at a scratch clone.  The
     worktree goes where every worktree of this repository goes,
     `<container>/worktrees/<branch>`, `<container>` being the directory that
     holds the main checkout.
  +  The privacy checks fail closed: a repository whose visibility gh cannot
     confirm is treated as private.
  +  gh runs with GH_TOKEN removed from its environment, as William's shells
     run it (`env -u GH_TOKEN gh`), so that it uses its own login.
  +  The index is not a file (README, "The index"): a report's pull request
     adds its own file and nothing else, so two of them open at once cannot
     conflict.
"""

from __future__ import annotations

import argparse
import datetime
import re
import sys
from functools import reduce
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

# Run by absolute path (the usual case, from another repository), the
# `scripts.python` package is not importable until this checkout's root is on
# the path; `PYTHONPATH=.` does the same for the tests and the Makefile.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.python.utils.command_runner import run_command  # noqa: E402
from scripts.python.utils.file_ops import ls_dir, read_text, write_text  # noqa: E402
from scripts.python.utils.pipeline_types import (  # noqa: E402
    ErrorType,
    PipelineError,
    Result,
)

# =============================================================================
# The rules
# =============================================================================

REPORTS_DIR: str = "docs/field-reports"
TEMPLATE_NAME: str = "TEMPLATE.md"
BRANCH_PREFIX: str = "field-report-"
BASE_BRANCH: str = "main"
DEFAULT_REPO: Path = Path(__file__).resolve().parents[2]

SLUG: str = r"[a-z0-9]+(?:-[a-z0-9]+)*"
SLUG_PATTERN: re.Pattern[str] = re.compile(SLUG)
# Long enough for a repository and an issue, short enough for a branch name.
MAX_SLUG_LENGTH: int = 60
FILE_PATTERN: re.Pattern[str] = re.compile(
    rf"(?P<date>\d{{4}}-\d{{2}}-\d{{2}})-(?P<slug>{SLUG})\.md")

# The header fields, in the order a report must give them.
HEADER_FIELDS: Tuple[str, ...] = (
    "Date", "Harness", "Model", "Effort", "Repository",
    "Issue or pull request", "Tools called",
)
PRIVATE: str = "a private repository"
NOT_NAMED: str = "not named"
NONE: str = "none"
OWNER_NAME: re.Pattern[str] = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+")
WORK_ITEM: re.Pattern[str] = re.compile(r"(?P<kind>issue|pull request) (?P<number>[1-9][0-9]*)")

PLACEHOLDER: re.Pattern[str] = re.compile(r"\bFILL\b")
EM_DASH: str = "—"
# A `#N` in a title: GitHub links it to this repository's item N when the
# title becomes a pull request's, whatever repository the report is about.
ISSUE_REFERENCE: re.Pattern[str] = re.compile(r"#[0-9]")
# A path under a home directory: `~/` or `~user/`, `$HOME` or `${HOME}`, and
# an absolute `/home/`, `/Users/` or `/root/`.  The lookbehinds keep a
# relative path that merely contains `home/` from matching.
HOME_PATH: re.Pattern[str] = re.compile(
    r"(?<![\w.~/-])~[\w.-]*/|\$\{?HOME\b|(?<![\w.-])/(?:home|Users|root)/")
HEADER_ITEM: re.Pattern[str] = re.compile(r"\*\*(?P<label>[^*]+)\*\*:\s*(?P<value>.*)")
HTML_COMMENT: re.Pattern[str] = re.compile(r"<!--.*?-->", re.DOTALL)


@dataclass(frozen=True)
class Names:
    """Everything named after one report's date and slug."""

    date: str
    slug: str

    @property
    def file_name(self) -> str:
        return f"{self.date}-{self.slug}.md"

    @property
    def relative_path(self) -> str:
        return f"{REPORTS_DIR}/{self.file_name}"

    @property
    def branch(self) -> str:
        return f"{BRANCH_PREFIX}{self.date}-{self.slug}"


@dataclass(frozen=True)
class Report:
    """A report as parsed: its title, its header items in file order, its body.

    A header item whose bullet is not `**Field**: value` has the label ""."""

    title: str
    header: Tuple[Tuple[str, str], ...]
    body: str

    def field(self, label: str) -> str:
        """The value of a header field, or "" when the header lacks it."""
        return next((value for name, value in self.header if name == label), "")

    @property
    def labels(self) -> Tuple[str, ...]:
        return tuple(name for name, _ in self.header)


def problem(message: str, problems: Sequence[str]) -> PipelineError:
    """A refusal that carries each reason, for `main` to print one per line."""
    return PipelineError(ErrorType.VALIDATION_ERROR, message,
                         context={"problems": tuple(problems)})


# =============================================================================
# Names
# =============================================================================

def valid_date(text: str) -> bool:
    """True when text is a real calendar date written YYYY-MM-DD."""
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        return False
    try:
        datetime.date.fromisoformat(text)
        return True
    except ValueError:
        return False


def names_for(date: str, slug: str) -> Result[Names, PipelineError]:
    """The names of a new report, or the reasons the date or slug is refused."""
    problems = (
        ([] if valid_date(date) else [f"{date!r} is not a date written YYYY-MM-DD"])
        + ([] if SLUG_PATTERN.fullmatch(slug) else
           [f"{slug!r} is not a slug: lowercase letters and digits, words joined by single hyphens"])
        + ([] if len(slug) <= MAX_SLUG_LENGTH else
           [f"the slug is {len(slug)} characters; at most {MAX_SLUG_LENGTH}"])
    )
    return (Result.ok(Names(date, slug)) if not problems
            else Result.err(problem("the report's name is refused", problems)))


def names_of_file(file_name: str) -> Optional[Names]:
    """The names a report file's own name implies, or None if it is not one."""
    match = FILE_PATTERN.fullmatch(file_name)
    return Names(match["date"], match["slug"]) if match else None


def fill_template(template: str, names: Names) -> str:
    """The template with the report's file name and date written in."""
    return (template
            .replace("YYYY-MM-DD-slug.md", names.file_name)
            .replace("YYYY-MM-DD", names.date))


# =============================================================================
# Parsing
# =============================================================================

def header_items(lines: Sequence[str]) -> Tuple[Tuple[str, str], ...]:
    """The bullet items of a header block, each with its continuation lines
    joined, as (label, value) with the value's final period dropped."""
    def joined(acc: Tuple[str, ...], line: str) -> Tuple[str, ...]:
        if line.startswith("+ "):
            return acc + (line[1:].strip(),)
        return acc[:-1] + (f"{acc[-1]} {line.strip()}",) if acc else acc

    def item(text: str) -> Tuple[str, str]:
        match = HEADER_ITEM.fullmatch(text)
        if not match:
            return ("", text)
        value = match["value"].strip()
        return (match["label"].strip(), value[:-1] if value.endswith(".") else value)

    return tuple(item(text) for text in reduce(joined, lines, ()))


def parse_report(text: str) -> Report:
    """Split a report into its title, its header, and its body.

    Total: a file with no title or no header parses to empty parts, which the
    checks then name.  The title is the first `# ` line; the header is the run
    of bullet lines (and their indented continuations) after it, up to the
    first blank line once the run has begun; the body is everything after."""
    lines = text.splitlines()
    title_at = next((i for i, line in enumerate(lines) if line.startswith("# ")), None)
    if title_at is None:
        return Report("", (), "")
    rest = lines[title_at + 1:]
    start = next((i for i, line in enumerate(rest) if line.strip()), len(rest))
    in_header = (lambda line: line.startswith("+ ") or
                 (line.startswith("   ") and bool(line.strip())))
    end = next((i for i in range(start, len(rest)) if not in_header(rest[i])), len(rest))
    header = header_items(rest[start:end]) if start < len(rest) and rest[start].startswith("+ ") else ()
    body_lines = rest[end:] if header else rest
    return Report(lines[title_at][2:].strip(), header, "\n".join(body_lines).strip())


# =============================================================================
# Checks
# =============================================================================

def name_problems(file_name: str) -> List[str]:
    names = names_of_file(file_name)
    if names is None:
        return [f"the file name {file_name!r} is not YYYY-MM-DD-<slug>.md"]
    checked = names_for(names.date, names.slug)
    return [] if checked.is_ok else list(checked.unwrap_err().context["problems"])


def file_line_problems(text: str, file_name: str) -> List[str]:
    """The first line names the file, as every file in this repository does."""
    expected = f"<!-- File: {REPORTS_DIR}/{file_name} -->"
    first = text.splitlines()[0] if text else ""
    return [] if first == expected else [f"the first line must be {expected!r}"]


def title_problems(report: Report, file_name: str) -> List[str]:
    names = names_of_file(file_name)
    if not report.title:
        return ["no title: the report needs a `# ` heading that begins with its date"]
    return (
        ([] if names is None or report.title.startswith(names.date) else
         [f"the title must begin with the date, {names.date}"])
        + ([] if not ISSUE_REFERENCE.search(report.title) else
           ["the title has a `#N`, which GitHub would link to this repository's item N; write \"issue N\""])
    )


def work_problems(repository: str, work: str) -> List[str]:
    """The Issue or pull request field, against the Repository field."""
    if repository == PRIVATE:
        return [] if work == NOT_NAMED else [
            f"a private repository's report says \"{NOT_NAMED}\" for the issue or pull request"]
    if work in (NONE, NOT_NAMED):
        return []
    items = work.split(", ")
    return [] if all(WORK_ITEM.fullmatch(item) for item in items) else [
        f"the issue or pull request is {work!r}; write \"issue N\", \"pull request N\","
        f" or both, comma-separated, or \"{NONE}\""]


def header_problems(report: Report, file_name: str) -> List[str]:
    labels = report.labels
    missing = [label for label in HEADER_FIELDS if label not in labels]
    extra = [label or "(not a **Field**: bullet)" for label in labels if label not in HEADER_FIELDS]
    if not report.header:
        return ["no header: the bullet list of fields must follow the title"]
    shape = (
        ([f"the header lacks {', '.join(missing)}"] if missing else [])
        + ([f"the header has items that are not fields: {', '.join(extra)}"] if extra else [])
        + ([f"the header's fields must be in the order {', '.join(HEADER_FIELDS)}"]
           if not missing and not extra and labels != HEADER_FIELDS else [])
    )
    empty = [f"the {label} field is empty" for label, value in report.header
             if label in HEADER_FIELDS and not value]
    names = names_of_file(file_name)
    # A value still holding FILL is reported once, by line_problems, rather
    # than again here for its form.
    def filled(label: str) -> str:
        value = report.field(label)
        return "" if PLACEHOLDER.search(value) else value
    date, repository, work = filled("Date"), filled("Repository"), filled("Issue or pull request")
    return (
        shape + empty
        + ([] if not date or names is None or date == names.date else
           [f"the Date field is {date}; the file name's date is {names.date}"])
        + ([] if not repository or repository == PRIVATE or OWNER_NAME.fullmatch(repository) else
           [f"the Repository field is {repository!r}; write owner/name, or \"{PRIVATE}\""])
        + (work_problems(repository, work) if repository and work else [])
    )


def body_problems(report: Report) -> List[str]:
    return [] if HTML_COMMENT.sub("", report.body).strip() else ["the report has no body"]


def line_problems(text: str, home: str) -> List[str]:
    """What no line of a report may hold: an unfilled placeholder, an
    em-dash, or a path under a home directory."""
    def found(number: int, line: str) -> List[str]:
        homes = [m.group(0) for m in HOME_PATH.finditer(line)] + (
            [home] if home and home in line else [])
        return (
            ([f"line {number}: FILL left in place"] if PLACEHOLDER.search(line) else [])
            + ([f"line {number}: an em-dash; use a semicolon, colon, comma, or parentheses"]
               if EM_DASH in line else [])
            + ([f"line {number}: a path under a home directory ({', '.join(homes)})"]
               if homes else [])
        )
    return [p for number, line in enumerate(text.splitlines(), start=1)
            for p in found(number, line)]


def report_problems(text: str, file_name: str, home: str) -> Tuple[str, ...]:
    """Every reason, found from the text alone, to refuse this report.

    `home` is the home directory of the user submitting it, refused anywhere
    in the text whatever its form."""
    report = parse_report(text)
    return tuple(
        name_problems(file_name)
        + file_line_problems(text, file_name)
        + title_problems(report, file_name)
        + header_problems(report, file_name)
        + body_problems(report)
        + line_problems(text, home)
    )


def check_report(text: str, file_name: str, home: str) -> Result[Report, PipelineError]:
    """The parsed report, or a refusal carrying every problem."""
    problems = report_problems(text, file_name, home)
    return (Result.ok(parse_report(text)) if not problems
            else Result.err(problem(f"{file_name}: the report is refused", problems)))


def mentions(text: str, word: str) -> bool:
    """True when text names `word` as a whole word, ignoring case."""
    return re.search(rf"(?<![\w-]){re.escape(word)}(?![\w-])", text, re.IGNORECASE) is not None


def working_repository_problems(text: str, report: Report, working: str, private: bool) -> List[str]:
    """A report submitted from inside a private repository says so and never
    names it.  `working` is that repository's owner/name."""
    if not private:
        return []
    name = working.split("/")[-1]
    return (
        ([] if report.field("Repository") == PRIVATE else
         [f"this is submitted from a private repository, so the Repository field must say \"{PRIVATE}\""])
        + ([f"the report names the private repository it was written in ({name})"]
           if mentions(text, working) or mentions(text, name) else [])
    )


# =============================================================================
# The commit, the pull request, the index
# =============================================================================

def github_repository(url: str) -> Optional[str]:
    """owner/name of a GitHub remote URL (ssh, scp-like, or https), else None."""
    match = re.fullmatch(
        r"(?:git@github\.com:|ssh://git@github\.com/|https://github\.com/)"
        r"(?P<repo>[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+?)(?:\.git)?/?", url.strip())
    return match["repo"] if match else None


def commit_message(report: Report) -> Tuple[str, str]:
    """The commit's subject and body."""
    return (f"field report: {report.title}",
            "One session's agda-mcp field report, submitted by\n"
            "scripts/python/field_report.py (issue #252).\n\n"
            f"\U0001F916 AI-assisted development: {report.field('Model')}")


def work_links(repository: str, work: str) -> str:
    """The Issue or pull request field with each item linked, when it can be."""
    if repository == PRIVATE or not OWNER_NAME.fullmatch(repository):
        return work

    def link(item: str) -> str:
        match = WORK_ITEM.fullmatch(item)
        if not match:
            return item
        kind = "issues" if match["kind"] == "issue" else "pull"
        return f"[{item}](https://github.com/{repository}/{kind}/{match['number']})"
    return ", ".join(link(item) for item in work.split(", "))


def pull_request_text(report: Report, names: Names, github_repo: str) -> Tuple[str, str]:
    """The pull request's title and body.  The body is not hard-wrapped:
    GitHub renders each newline in it as a line break."""
    repository = report.field("Repository")
    shown = {
        "Repository": (repository if repository == PRIVATE
                       else f"[{repository}](https://github.com/{repository})"),
        "Issue or pull request": work_links(repository, report.field("Issue or pull request")),
    }
    fields = "\n".join(f"+  **{label}**: {shown.get(label, report.field(label))}."
                       for label in HEADER_FIELDS if label != "Date")
    body = (
        f"A field report from one session, as one new file, `{names.relative_path}`, "
        f"submitted by `scripts/python/field_report.py submit` ([#252]).\n\n"
        f"{fields}\n\n"
        f"\U0001F916 AI-assisted development: {report.field('Model')}\n\n"
        f"[#252]: https://github.com/{github_repo}/issues/252\n"
    )
    return (f"field report: {report.title}", body)


def index_table(reports: Sequence[Tuple[str, Report]]) -> str:
    """A Markdown table of the reports' headers, in the order given."""
    head = ("| Date | Report | Repository | Harness | Model | Tools called |\n"
            "|------|--------|------------|---------|-------|--------------|")
    rows = [f"| {r.field('Date')} | [{Path(name).stem[11:]}]({name}) | {r.field('Repository')} "
            f"| {r.field('Harness')} | {r.field('Model')} | {r.field('Tools called')} |"
            for name, r in reports]
    return "\n".join([head] + rows) + "\n"


# =============================================================================
# Effects: git and gh
# =============================================================================

def git(*args: str) -> Result[str, PipelineError]:
    """Run git; its standard output, stripped."""
    return run_command(["git", *args], capture_output=True, text=True).map(
        lambda done: done.stdout.strip())


def gh(*args: str) -> Result[str, PipelineError]:
    """Run gh with GH_TOKEN removed; its standard output, stripped."""
    return run_command(["env", "-u", "GH_TOKEN", "gh", *args], capture_output=True,
                       text=True).map(lambda done: done.stdout.strip())


def common_dir(path: Path) -> Result[Path, PipelineError]:
    """The git common directory of the repository holding `path`."""
    return git("-C", str(path), "rev-parse", "--path-format=absolute",
               "--git-common-dir").map(lambda out: Path(out).resolve())


def worktrees_dir(common: Path) -> Path:
    """Where this repository keeps its worktrees: `worktrees/` beside the
    main checkout (or beside a bare repository)."""
    main_checkout = common.parent if common.name == ".git" else common
    return main_checkout.parent / "worktrees"


def is_public(repository: str) -> Result[bool, PipelineError]:
    """Whether GitHub reports `repository` as public."""
    return gh("api", f"repos/{repository}", "--jq", ".private").map(lambda out: out == "false")


def origin_repository(directory: Path) -> Optional[str]:
    """owner/name of the GitHub repository whose checkout holds `directory`,
    or None when it is in no git repository or its origin is not GitHub."""
    url = git("-C", str(directory), "remote", "get-url", "origin")
    return github_repository(url.unwrap()) if url.is_ok else None


def new_report(repo: Path, names: Names) -> Result[Path, PipelineError]:
    """Fetch, make the report's worktree and branch from origin/main, and
    write the template there.  Returns the report file's path."""
    template_spec = f"origin/{BASE_BRANCH}:{REPORTS_DIR}/{TEMPLATE_NAME}"

    def refuse_existing(_: str) -> Result[str, PipelineError]:
        local = git("-C", str(repo), "rev-parse", "--verify", "--quiet",
                    f"refs/heads/{names.branch}")
        remote = git("-C", str(repo), "ls-remote", "--heads", "origin",
                     f"refs/heads/{names.branch}")
        if local.is_ok or (remote.is_ok and remote.unwrap()):
            return Result.err(problem("the branch exists", [
                f"{names.branch} already exists; choose another slug"]))
        return remote

    def make(common: Path) -> Result[Path, PipelineError]:
        worktree = worktrees_dir(common) / names.branch
        if worktree.exists():
            return Result.err(problem("the worktree exists", [f"{worktree} already exists"]))
        return (git("-C", str(repo), "show", template_spec)
                .and_then(lambda template: git(
                    "-C", str(repo), "worktree", "add", "-q", "--no-track", "-b",
                    names.branch, str(worktree), f"origin/{BASE_BRANCH}")
                    .map(lambda _: template))
                .and_then(lambda template: write_text(
                    worktree / names.relative_path, fill_template(template, names) + "\n"))
                .map(lambda _: worktree / names.relative_path))

    return (git("-C", str(repo), "fetch", "-q", "origin", BASE_BRANCH)
            .and_then(refuse_existing)
            .and_then(lambda _: git("-C", str(repo), "cat-file", "-e", template_spec)
                      .map_err(lambda e: problem("no template on origin/main", [
                          f"{template_spec} does not exist; has issue #252 merged?"])))
            .and_then(lambda _: common_dir(repo))
            .and_then(make))


@dataclass(frozen=True)
class Located:
    """A report file in its worktree."""

    path: Path
    worktree: Path
    names: Names


def locate(repo: Path, path: Path) -> Result[Located, PipelineError]:
    """The report's worktree, refused unless it is a worktree of `repo` on the
    report's branch, with the report as its only change."""
    names = names_of_file(path.name)
    if not path.is_file() or names is None:
        return Result.err(problem("not a report", [
            f"{path} is not a file named YYYY-MM-DD-<slug>.md"]))
    folder = str(path.parent)

    def placed(worktree: Path) -> Result[Located, PipelineError]:
        relative = path.relative_to(worktree).as_posix() if path.is_relative_to(worktree) else ""
        branch = git("-C", folder, "symbolic-ref", "--quiet", "--short", "HEAD").unwrap_or("")
        status = git("-C", folder, "status", "--porcelain=v1", "--untracked-files=all")
        changes = status.unwrap_or("").splitlines() if status.is_ok else ["(git status failed)"]
        problems = (
            ([] if relative == names.relative_path else
             [f"the report must be {names.relative_path} in its worktree"])
            + ([] if branch == names.branch else
               [f"the worktree is on {branch or 'no branch'}; the report's branch is {names.branch}"])
            + ([] if changes in ([f"?? {names.relative_path}"], [f"A  {names.relative_path}"]) else
               ["the worktree must hold the report and no other change; git status says: "
                + "; ".join(changes)])
        )
        return (Result.ok(Located(path, worktree, names)) if not problems
                else Result.err(problem("the report's worktree is refused", problems)))

    same = (common_dir(path.parent).and_then(lambda mine: common_dir(repo).and_then(
        lambda theirs: Result.ok(mine) if mine == theirs else Result.err(problem(
            "not this repository", [f"{path} is not in a worktree of {repo}"])))))
    return (same
            .and_then(lambda _: git("-C", folder, "rev-parse", "--show-toplevel"))
            .map(lambda top: Path(top).resolve())
            .and_then(placed))


def privacy_problems(text: str, report: Report, cwd: Path) -> List[str]:
    """The checks that ask GitHub: the named repository is public, and a
    report from inside a private repository says so and never names it."""
    repository = report.field("Repository")
    named = (([] if is_public(repository).unwrap_or(False) else
              [f"GitHub does not report {repository} as a public repository"])
             if OWNER_NAME.fullmatch(repository) else [])
    working = origin_repository(cwd)
    working_private = working is not None and not is_public(working).unwrap_or(False)
    return named + (working_repository_problems(text, report, working, working_private)
                    if working else [])


def submit_report(repo: Path, path: Path, github_repo: str, cwd: Path,
                  home: str) -> Result[Tuple[str, str], PipelineError]:
    """Check, commit, push, open the pull request, remove the worktree.

    Returns the pull request's URL and a note on the worktree."""
    def private_checked(text: str, report: Report) -> Result[Report, PipelineError]:
        found = privacy_problems(text, report, cwd)
        return (Result.ok(report) if not found
                else Result.err(problem(f"{path.name}: the report is refused", found)))

    def checked(located: Located) -> Result[Tuple[Located, Report], PipelineError]:
        return (read_text(located.path)
                .and_then(lambda text: check_report(text, path.name, home)
                          .and_then(lambda report: private_checked(text, report)))
                .map(lambda report: (located, report)))

    def published(pair: Tuple[Located, Report]) -> Result[Tuple[str, str], PipelineError]:
        located, report = pair
        tree = str(located.worktree)
        subject, body = commit_message(report)
        title, text = pull_request_text(report, located.names, github_repo)
        return (git("-C", tree, "add", "--", located.names.relative_path)
                .and_then(lambda _: git("-C", tree, "commit", "-q", "-m", subject, "-m", body))
                .and_then(lambda _: git("-C", tree, "push", "-q", "-u", "origin", located.names.branch))
                .and_then(lambda _: gh("api", "-X", "POST", f"repos/{github_repo}/pulls",
                                       "-f", f"title={title}", "-f", f"head={located.names.branch}",
                                       "-f", f"base={BASE_BRANCH}", "-f", f"body={text}",
                                       "--jq", ".html_url")
                          .map_err(lambda e: e.with_context(
                              note=f"{located.names.branch} is pushed; open its pull request by hand")))
                .map(lambda url: (url, removed(located))))

    def removed(located: Located) -> str:
        if cwd.resolve().is_relative_to(located.worktree):
            return f"the worktree {located.worktree} stays: the working directory is inside it"
        gone = git("-C", str(repo), "worktree", "remove", str(located.worktree))
        return (f"removed the worktree {located.worktree}; the branch stays" if gone.is_ok
                else f"the worktree {located.worktree} stays: {gone.unwrap_err().message}")

    return locate(repo, path.resolve()).and_then(checked).and_then(published)


def read_reports(repo: Path) -> Result[List[Tuple[str, Report]], PipelineError]:
    """Every report in a checkout, by file name, oldest first."""
    def parsed(paths: List[Path]) -> List[Tuple[str, Report]]:
        return [(p.name, parse_report(read_text(p).unwrap_or(""))) for p in paths
                if names_of_file(p.name)]
    return ls_dir(repo / REPORTS_DIR, "*.md").map(parsed)


# =============================================================================
# The command line
# =============================================================================

def describe(error: PipelineError) -> str:
    """An error as lines for a person: the message, then each problem."""
    problems = error.context.get("problems", ())
    rest = {k: v for k, v in error.context.items() if k != "problems"}
    return "\n".join(
        [f"field_report: {error.message}"]
        + [f"  + {p}" for p in problems]
        + [f"  {k}: {v}" for k, v in rest.items()]
    )


def parse_arguments(argv: Sequence[str]) -> argparse.Namespace:
    # --repo is accepted after the subcommand, where a reader expects it.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--repo", type=Path, default=DEFAULT_REPO,
                        help="the checkout whose origin receives the report (default: this file's)")
    parser = argparse.ArgumentParser(
        prog="field_report.py",
        description="Write and submit an agda-mcp field report as a pull request of one new file.")
    commands = parser.add_subparsers(dest="command", required=True)
    new = commands.add_parser("new", parents=[common],
                              help="make the report's worktree and file; print its path")
    new.add_argument("slug")
    new.add_argument("--date", default=datetime.date.today().isoformat(),
                     help="the report's date (default: today)")
    submit = commands.add_parser("submit", parents=[common],
                                 help="check, commit, push, and open the pull request")
    submit.add_argument("path", type=Path)
    submit.add_argument("--github-repo", default=None,
                        help="owner/name for the pull request (default: from --repo's origin)")
    commands.add_parser("index", parents=[common], help="print a table of every report's header")
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    options = parse_arguments(sys.argv[1:] if argv is None else argv)
    repo = options.repo.resolve()
    if options.command == "new":
        result = names_for(options.date, options.slug).and_then(lambda n: new_report(repo, n))
        if result.is_ok:
            print(result.unwrap())
            return 0
    elif options.command == "submit":
        github_repo = options.github_repo or origin_repository(repo)
        if github_repo is None:
            print("field_report: --repo's origin is not on GitHub; pass --github-repo", file=sys.stderr)
            return 2
        result = submit_report(repo, options.path, github_repo, Path.cwd(), str(Path.home()))
        if result.is_ok:
            url, note = result.unwrap()
            print(url)
            print(note, file=sys.stderr)
            return 0
    else:
        result = read_reports(repo)
        if result.is_ok:
            print(index_table(result.unwrap()), end="")
            return 0
    print(describe(result.unwrap_err()), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
