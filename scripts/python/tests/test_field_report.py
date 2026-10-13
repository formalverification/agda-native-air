"""
Tests for `scripts/python/field_report.py`.

File: scripts/python/tests/test_field_report.py

Description
-----------
The checker is the executable form of docs/field-reports/README.md, so it is
pinned three ways: each rule against a report that breaks only that rule; the
committed template, which `new` writes and which must be refused for its
FILLs and nothing else; and every committed report, which must pass, so that
a report's pull request runs its own check in CI.

The commands are driven against a world built in `tmp_path`: a bare origin
seeded with the template, a clone of it inside `<container>/main`, a second
repository standing for the one a session works in, and a fake `gh` on PATH
that answers visibility queries from a table and logs every call.  Git runs
with an empty global config and a fixed identity, so neither the user's
config nor CI's matters.  The last test runs the script by absolute path from
inside the other repository, as a session does.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_field_report.py`
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List

import pytest

from scripts.python.field_report import (
    HEADER_FIELDS,
    Names,
    commit_message,
    fill_template,
    github_repository,
    names_for,
    names_of_file,
    new_report,
    parse_report,
    pull_request_text,
    report_problems,
    submit_report,
    working_repository_problems,
)

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "python" / "field_report.py"
REPORTS = ROOT / "docs" / "field-reports"
HOME = "/nonexistent-home"
NAME = "2026-10-12-agda-algebras-592.md"
NAMES = Names("2026-10-12", "agda-algebras-592")

# The fake gh: visibility from FAKE_GH_PRIVATE (a JSON object, owner/name ->
# bool; a repository not in it answers 404 as GitHub does for one you cannot
# see), a fixed URL for a created pull request, and every call logged with
# whether GH_TOKEN reached it.
FAKE_GH = """\
import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_GH_LOG"], "a", encoding="utf-8") as log:
    log.write(json.dumps({"args": args, "token": "GH_TOKEN" in os.environ}) + "\\n")
private = json.loads(os.environ.get("FAKE_GH_PRIVATE", "{}"))
if args[:3] == ["api", "-X", "POST"]:
    print("https://github.com/test/repo/pull/7")
elif args[:1] == ["api"] and args[1][len("repos/"):] in private:
    print("true" if private[args[1][len("repos/"):]] else "false")
else:
    print("gh: Not Found (HTTP 404)", file=sys.stderr)
    sys.exit(1)
"""


def report_text(name: str = NAME, *, title: str = "", repository: str = "ualib/agda-algebras",
                work: str = "issue 592, pull request 602",
                body: str = "The session wrote four modules.\n\n+  **Tools used**.  `check_file`.") -> str:
    """A complete report, which each rule's test then breaks in one place."""
    date = name[:10]
    return (f"<!-- File: docs/field-reports/{name} -->\n\n"
            f"# {title or date + ', agda-algebras issue 592: substitutions'}\n\n"
            f"+  **Date**: {date}.\n"
            f"+  **Harness**: Claude Code 2.1.282.\n"
            f"+  **Model**: Claude Opus 5.5\n   (Anthropic).\n"
            f"+  **Effort**: high.\n"
            f"+  **Repository**: {repository}.\n"
            f"+  **Issue or pull request**: {work}.\n"
            f"+  **Tools called**: check_file 12, normalize 3.\n\n"
            f"{body}\n")


def problems(text: str, name: str = NAME, home: str = HOME) -> List[str]:
    return list(report_problems(text, name, home))


# ------------------------------------------------------------- the checker

def test_a_complete_report_passes_and_parses() -> None:
    report = parse_report(report_text())
    assert problems(report_text()) == []
    assert report.labels == HEADER_FIELDS
    # A wrapped value is joined, and its final period dropped.
    assert report.field("Model") == "Claude Opus 5.5 (Anthropic)"
    assert report.body.startswith("The session wrote")


def test_the_template_as_new_writes_it_is_refused_for_its_fills_alone() -> None:
    filled = fill_template((REPORTS / "TEMPLATE.md").read_text(encoding="utf-8"), NAMES)
    found = problems(filled)
    assert found and all("FILL left in place" in p for p in found), found
    assert filled.splitlines()[0] == f"<!-- File: docs/field-reports/{NAME} -->"


def test_every_committed_report_passes() -> None:
    reports = [p for p in REPORTS.glob("*.md") if names_of_file(p.name)]
    assert reports
    for path in reports:
        assert problems(path.read_text(encoding="utf-8"), path.name) == [], path.name


def test_the_readme_names_the_header_fields_in_the_checkers_order() -> None:
    rows = [line.split("|")[1].strip()
            for line in (REPORTS / "README.md").read_text(encoding="utf-8").splitlines()
            if line.startswith("| ") and not line.startswith("| Field")]
    assert tuple(rows) == HEADER_FIELDS


@pytest.mark.parametrize("date, slug", [
    ("2026-10-12", "Agda-algebras"), ("2026-10-12", "two--hyphens"), ("2026-10-12", "trailing-"),
    ("2026-10-12", "x" * 61), ("2026-02-30", "fine"), ("12-10-2026", "fine"),
])
def test_a_bad_date_or_slug_is_refused(date: str, slug: str) -> None:
    assert names_for(date, slug).is_err


def test_names_follow_the_date_and_slug() -> None:
    names = names_for("2026-10-12", "agda-algebras-592").unwrap()
    assert (names.file_name, names.relative_path, names.branch) == (
        NAME, f"docs/field-reports/{NAME}", "field-report-2026-10-12-agda-algebras-592")
    assert names_of_file(NAME) == names and names_of_file("README.md") is None


def test_the_file_name_and_the_first_line_must_agree() -> None:
    assert any("is not YYYY-MM-DD" in p for p in problems(report_text(), "notes.md"))
    other = "2026-10-12-other.md"
    assert any("first line must be" in p for p in problems(report_text(), other))


@pytest.mark.parametrize("edit, expected", [
    (lambda t: t.replace("+  **Effort**: high.\n", ""), "lacks Effort"),
    (lambda t: t.replace("**Effort**: high", "**Effort**:"), "Effort field is empty"),
    (lambda t: t.replace("+  **Effort**: high.\n", "").replace(
        "+  **Tools called**", "+  **Effort**: high.\n+  **Tools called**"), "in the order"),
    (lambda t: t.replace("**Date**: 2026-10-12", "**Date**: 2026-10-11"), "file name's date"),
    (lambda t: t.replace("+  **Harness**", "+  Harness"), "not fields"),
])
def test_the_header_is_complete_and_in_order(edit, expected: str) -> None:
    assert any(expected in p for p in problems(edit(report_text()))), problems(edit(report_text()))


@pytest.mark.parametrize("repository, work, refused", [
    ("a private repository", "not named", False),
    ("a private repository", "issue 3", True),
    ("ualib/agda-algebras", "none", False),
    ("ualib/agda-algebras", "not named", False),
    ("ualib/agda-algebras", "#592", True),
    ("ualib/agda-algebras", "issue 592 and PR 602", True),
    ("agda-algebras", "issue 592", True),
])
def test_the_repository_and_its_work_items(repository: str, work: str, refused: bool) -> None:
    found = problems(report_text(repository=repository, work=work))
    assert bool(found) == refused, found


@pytest.mark.parametrize("line, home", [
    ("in `~/git/x`", HOME), ("under $HOME/x", HOME), ("under ${HOME}/x", HOME),
    ("at /home/alice/x", HOME), ("at /Users/alice/x", HOME), ("at /root/x", HOME),
    ("at ~alice/x", HOME), ("at /srv/me/x", "/srv/me"),
])
def test_a_path_under_a_home_directory_is_refused(line: str, home: str) -> None:
    found = problems(report_text(body=f"The checkout {line}."), home=home)
    assert any("home directory" in p for p in found), found


@pytest.mark.parametrize("line", [
    "`src/home/x`", "~35 calls", "https://example.com/home/x", "the `$HOMEWORK` variable",
])
def test_a_path_that_only_looks_like_home_passes(line: str) -> None:
    assert problems(report_text(body=f"Saw {line}.")) == []


def test_an_em_dash_a_fill_and_an_empty_body_are_refused() -> None:
    assert any("em-dash" in p for p in problems(report_text(body="One — two.")))
    assert any("FILL" in p for p in problems(report_text(body="FILL: the report.")))
    assert any("no body" in p for p in problems(report_text(body="<!-- nothing -->")))


def test_the_title_begins_with_the_date_and_has_no_issue_reference() -> None:
    assert any("begin with the date" in p for p in problems(report_text(title="agda-algebras")))
    assert any("`#N`" in p for p in problems(report_text(title="2026-10-12, agda-algebras #592")))
    assert any("no title" in p for p in problems(report_text().replace("# 2026", "2026")))


def test_a_report_from_inside_a_private_repository() -> None:
    clean = report_text(repository="a private repository", work="not named")
    named = report_text(repository="a private repository", work="not named",
                        body="Wrote modules in Hidden-Thing.")
    public = report_text()
    check = working_repository_problems
    assert check(clean, parse_report(clean), "acme/hidden-thing", True) == []
    assert any("names the private" in p
               for p in check(named, parse_report(named), "acme/hidden-thing", True))
    assert any("must say" in p for p in check(public, parse_report(public), "acme/hidden-thing", True))
    assert check(public, parse_report(public), "acme/public-thing", False) == []


@pytest.mark.parametrize("url, expected", [
    ("git@github.com:formalverification/agda-native-air.git", "formalverification/agda-native-air"),
    ("https://github.com/ualib/agda-algebras", "ualib/agda-algebras"),
    ("ssh://git@github.com/a-b/c.d.git", "a-b/c.d"),
    ("/tmp/origin.git", None),
    ("https://gitlab.com/a/b.git", None),
])
def test_github_repository_reads_a_remote_url(url: str, expected) -> None:
    assert github_repository(url) == expected


def test_the_commit_and_the_pull_request_text() -> None:
    report = parse_report(report_text())
    subject, body = commit_message(report)
    assert subject == "field report: 2026-10-12, agda-algebras issue 592: substitutions"
    assert body.endswith("AI-assisted development: Claude Opus 5.5 (Anthropic)")
    title, text = pull_request_text(report, NAMES, "test/repo")
    assert title == subject
    assert "[issue 592](https://github.com/ualib/agda-algebras/issues/592)" in text
    assert "[pull request 602](https://github.com/ualib/agda-algebras/pull/602)" in text
    assert "[#252]: https://github.com/test/repo/issues/252" in text
    # Not hard-wrapped: every line is a whole paragraph, bullet, or definition.
    assert all(line == "" or line.startswith(("A field", "+  **", "\U0001F916", "[#252]"))
               for line in text.splitlines()), text


def test_a_private_reports_pull_request_links_nothing() -> None:
    report = parse_report(report_text(repository="a private repository", work="not named"))
    _, text = pull_request_text(report, NAMES, "test/repo")
    assert "**Repository**: a private repository." in text
    assert "**Issue or pull request**: not named." in text


# ------------------------------------------------------------ the commands

def git(*args: str, cwd: Path) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True,
                          text=True).stdout.strip()


@pytest.fixture
def world(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Dict[str, Path]:
    """A bare origin with the template on main, its clone at
    <container>/main, another repository to work from, and a fake gh."""
    config = tmp_path / "gitconfig"
    config.write_text("")
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", str(config))
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    for role in ("AUTHOR", "COMMITTER"):
        monkeypatch.setenv(f"GIT_{role}_NAME", "A Tester")
        monkeypatch.setenv(f"GIT_{role}_EMAIL", "tester@example.com")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    fake = bin_dir / "gh"
    fake.write_text(f"#!{sys.executable}\n{FAKE_GH}")
    fake.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("FAKE_GH_LOG", str(tmp_path / "gh.log"))
    monkeypatch.setenv("FAKE_GH_PRIVATE", json.dumps({
        "ualib/agda-algebras": False, "acme/public-thing": False,
        "acme/hidden-thing": True, "acme/secret": True}))
    monkeypatch.setenv("GH_TOKEN", "a-token-gh-must-not-see")

    origin = tmp_path / "origin.git"
    git("init", "-q", "--bare", "-b", "main", str(origin), cwd=tmp_path)
    seed = tmp_path / "seed"
    git("clone", "-q", str(origin), str(seed), cwd=tmp_path)
    (seed / "docs" / "field-reports").mkdir(parents=True)
    (seed / "docs" / "field-reports" / "TEMPLATE.md").write_text(
        (REPORTS / "TEMPLATE.md").read_text(encoding="utf-8"), encoding="utf-8")
    (seed / "README.md").write_text("a repository\n")
    git("add", ".", cwd=seed)
    git("commit", "-q", "-m", "seed", cwd=seed)
    git("push", "-q", "origin", "HEAD:main", cwd=seed)
    main = tmp_path / "container" / "main"
    git("clone", "-q", str(origin), str(main), cwd=tmp_path)

    other = tmp_path / "other"
    git("init", "-q", "-b", "main", str(other), cwd=tmp_path)
    git("remote", "add", "origin", "https://github.com/acme/public-thing.git", cwd=other)
    monkeypatch.chdir(other)
    return {"origin": origin, "main": main, "other": other, "seed": seed, "tmp": tmp_path}


def gh_calls(world: Dict[str, Path]) -> List[dict]:
    log = world["tmp"] / "gh.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def test_new_makes_the_worktree_the_branch_and_the_file(world: Dict[str, Path]) -> None:
    path = new_report(world["main"], NAMES).unwrap()
    worktree = world["tmp"] / "container" / "worktrees" / NAMES.branch
    assert path == worktree / NAMES.relative_path
    text = path.read_text(encoding="utf-8")
    assert text.startswith(f"<!-- File: docs/field-reports/{NAME} -->")
    assert "+  **Date**: 2026-10-12." in text and "YYYY" not in text
    assert git("symbolic-ref", "--short", "HEAD", cwd=worktree) == NAMES.branch
    # No upstream yet: `submit` sets it when it pushes.
    assert subprocess.run(["git", "rev-parse", "--abbrev-ref", "@{upstream}"], cwd=worktree,
                          capture_output=True).returncode != 0
    assert git("status", "--porcelain", cwd=worktree) == f"?? {NAMES.relative_path}"


def test_new_refuses_a_branch_that_exists_here_or_on_origin(world: Dict[str, Path]) -> None:
    git("branch", NAMES.branch, cwd=world["main"])
    assert "already exists" in str(new_report(world["main"], NAMES).unwrap_err().context)
    taken = Names("2026-10-12", "taken")
    git("push", "-q", "origin", f"HEAD:refs/heads/{taken.branch}", cwd=world["seed"])
    assert "already exists" in str(new_report(world["main"], taken).unwrap_err().context)


def test_new_refuses_when_origin_main_has_no_template(world: Dict[str, Path]) -> None:
    git("rm", "-q", "docs/field-reports/TEMPLATE.md", cwd=world["seed"])
    git("commit", "-q", "-m", "drop the template", cwd=world["seed"])
    git("push", "-q", "origin", "HEAD:main", cwd=world["seed"])
    assert "no template" in new_report(world["main"], NAMES).unwrap_err().message
    assert not (world["tmp"] / "container" / "worktrees" / NAMES.branch).exists()


def submit(world: Dict[str, Path], path: Path):
    return submit_report(world["main"], path, "test/repo", Path.cwd(), HOME)


def test_submit_from_another_repository_opens_a_pull_request_of_one_file(
        world: Dict[str, Path]) -> None:
    path = new_report(world["main"], NAMES).unwrap()
    path.write_text(report_text(), encoding="utf-8")
    url, note = submit(world, path).unwrap()
    assert url == "https://github.com/test/repo/pull/7"
    # On origin: one commit on main's tip, adding exactly the report.
    origin = world["origin"]
    assert git("rev-list", "--count", f"main..{NAMES.branch}", cwd=origin) == "1"
    assert git("diff", "--name-status", "main", NAMES.branch, cwd=origin) == (
        f"A\t{NAMES.relative_path}")
    assert git("log", "-1", "--format=%an", NAMES.branch, cwd=origin) == "A Tester"
    posts = [c for c in gh_calls(world) if c["args"][:3] == ["api", "-X", "POST"]]
    assert len(posts) == 1 and posts[0]["args"][3] == "repos/test/repo/pulls"
    assert f"head={NAMES.branch}" in posts[0]["args"] and "base=main" in posts[0]["args"]
    assert not any(c["token"] for c in gh_calls(world))
    # The worktree is gone; the branch stays.
    assert "removed the worktree" in note and not path.exists()
    assert git("branch", "--list", NAMES.branch, cwd=world["main"]).endswith(NAMES.branch)


def assert_nothing_published(world: Dict[str, Path], path: Path) -> None:
    assert path.exists()
    assert git("ls-remote", "--heads", "origin", NAMES.branch, cwd=world["main"]) == ""
    assert not any(c["args"][:3] == ["api", "-X", "POST"] for c in gh_calls(world))


def test_submit_refuses_the_unfilled_template(world: Dict[str, Path]) -> None:
    path = new_report(world["main"], NAMES).unwrap()
    error = submit(world, path).unwrap_err()
    assert any("FILL" in p for p in error.context["problems"])
    assert_nothing_published(world, path)


def test_submit_refuses_a_worktree_with_another_change(world: Dict[str, Path]) -> None:
    path = new_report(world["main"], NAMES).unwrap()
    path.write_text(report_text(), encoding="utf-8")
    (path.parents[2] / "README.md").write_text("changed\n")
    error = submit(world, path).unwrap_err()
    assert any("no other change" in p for p in error.context["problems"])
    assert_nothing_published(world, path)


def test_submit_refuses_a_report_outside_a_report_worktree(world: Dict[str, Path]) -> None:
    stray = world["other"] / NAME
    stray.write_text(report_text(), encoding="utf-8")
    assert "not in a worktree of" in str(submit(world, stray).unwrap_err().context)


def test_submit_refuses_a_repository_github_does_not_call_public(world: Dict[str, Path]) -> None:
    path = new_report(world["main"], NAMES).unwrap()
    path.write_text(report_text(repository="acme/secret"), encoding="utf-8")
    error = submit(world, path).unwrap_err()
    assert any("acme/secret as a public" in p for p in error.context["problems"])
    assert_nothing_published(world, path)


def test_submit_from_inside_a_private_repository(world: Dict[str, Path]) -> None:
    git("remote", "set-url", "origin", "git@github.com:acme/hidden-thing.git", cwd=world["other"])
    path = new_report(world["main"], NAMES).unwrap()
    path.write_text(report_text(), encoding="utf-8")
    assert any("must say" in p for p in submit(world, path).unwrap_err().context["problems"])
    path.write_text(report_text(repository="a private repository", work="not named",
                                body="Checked modules of hidden-thing."), encoding="utf-8")
    assert any("names the private" in p
               for p in submit(world, path).unwrap_err().context["problems"])
    assert_nothing_published(world, path)
    path.write_text(report_text(repository="a private repository", work="not named"),
                    encoding="utf-8")
    assert submit(world, path).is_ok


def test_the_script_runs_by_absolute_path_from_another_repository(
        world: Dict[str, Path]) -> None:
    def run(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(SCRIPT), *args], cwd=world["other"],
                              capture_output=True, text=True)
    created = run("new", "agda-algebras-592", "--repo", str(world["main"]), "--date", "2026-10-12")
    assert created.returncode == 0, created.stderr
    path = Path(created.stdout.strip())
    refused = run("submit", str(path), "--repo", str(world["main"]), "--github-repo", "test/repo")
    assert refused.returncode == 1 and "FILL left in place" in refused.stderr
    path.write_text(report_text(), encoding="utf-8")
    done = run("submit", str(path), "--repo", str(world["main"]), "--github-repo", "test/repo")
    assert done.returncode == 0, done.stderr
    assert done.stdout.strip() == "https://github.com/test/repo/pull/7"
