<!-- File: docs/field-reports/README.md -->

# Field reports

A field report is one session's account of using the agda-mcp server for real
work: which tools it called, what worked, what was awkward or missing, and
whether the command line was the more efficient loop.  The reports are
evidence in both directions, and the server's field-driven issues (Milestone 5
of [`GITHUB_PROJECT.md`]) are argued from them.  If the server slowed the work
down, the report says exactly that.

Each report is one file, `YYYY-MM-DD-<slug>.md`, written by the session that
did the work and submitted as a pull request that adds that one file, so that
William reviews every report before it is public.  The reports written from
2026-08-21 to 2026-10-11 are sections of [`mcp-field-reports.md`], which is
frozen ([#252]).

## Writing a report

Two commands do it, run with the system `python3` from any directory, whatever
repository the session is working in; `<main>` below is this repository's main
checkout, and the script needs nothing beyond the standard library and the
checkout it lives in.

1.  `python3 <main>/scripts/python/field_report.py new <slug>` fetches
    `origin`, makes a worktree of this repository on a new branch
    `field-report-<date>-<slug>` from `origin/main`, under the `worktrees/`
    directory beside the main checkout, writes [`TEMPLATE.md`] there as
    `docs/field-reports/<date>-<slug>.md` with the date filled in, and prints
    that file's path.  The slug is lowercase words and digits joined by
    hyphens, naming the repository and the work (`agda-algebras-592`); a
    session in a private repository chooses one that names neither
    (`private-batch-checks`).
2.  Write the report in that file, replacing every `FILL`.
3.  `python3 <main>/scripts/python/field_report.py submit <path>` checks the
    file (below), commits it as the branch's one commit, pushes the branch,
    opens the pull request, prints its URL, and removes the worktree; the
    branch stays, locally and on `origin`.  A refused report names each
    problem; fix them and run `submit` again.

`new` and `submit` both take `--base <branch>` (default `main`) to stack a
report on a branch that has not merged yet; GitHub retargets its pull request
to `main` when that branch merges and is deleted.  `field_report.py index`
prints a table of every report's header, newest last.

## The header

The title is a level-one heading that begins with the date.  The header is the
bullet list right under it, with these fields in this order, each value
non-empty:

| Field | What it holds |
|-------|---------------|
| Date | `YYYY-MM-DD`, the same as the file name's |
| Harness | the harness and its version (Claude Code 2.1.282, Codex CLI 0.162.1) |
| Model | the model and its maker (Claude Opus 5.5 (Anthropic)) |
| Effort | the reasoning effort (`high`, `xhigh`), or "not set" |
| Repository | `owner/name` of a public repository, or "a private repository" |
| Issue or pull request | "issue N", "pull request N", comma-separated, or "none"; "not named" for a private repository |
| Tools called | each agda-mcp tool called, with its count, or "none" |

A value the session cannot know (an older harness's version, say) is written
"not recorded".  The body follows the header, in the shape the template gives:
a paragraph on the work, then the tools used, what worked, what was awkward or
missing, and the comparison with the command line.  A session that called no
tool says so; that is a finding too.

## Privacy

This repository is public.  A session in a private repository writes about
tool usage only: its report says "a private repository" for the repository and
"not named" for the issue, and it quotes no mathematics, no module or
definition names, and nothing from anyone's unpublished work.  The same holds
for a public repository's session that touched someone's unpublished work.

## What `submit` checks

Before it commits anything, `submit` refuses a report for any of the following:

+  a file name that is not `YYYY-MM-DD-<slug>.md`, or a file outside a
   worktree of this repository whose branch is that name's
   `field-report-<date>-<slug>`, or a worktree with any other change;
+  a missing title or header field, a field out of order, a date that is not
   the file name's, or a `FILL` left anywhere outside a code span (where a
   report may quote it);
+  an empty body;
+  a path under a home directory anywhere in the file (`~/`, `$HOME`,
   `/home/`, `/Users/`, `/root/`, or the home directory of the user running
   it);
+  an em-dash, which this repository's prose never uses;
+  a Repository field naming a repository that GitHub does not report as
   public, or a private repository's report whose Issue field is not "not
   named";
+  a report submitted from inside a private GitHub repository (the working
   directory's `origin`) that does not say "a private repository", or that
   names that repository anywhere.

The checks cannot read for mathematics or unpublished work; William's review
of the pull request does.

## The index

This directory's listing is the index.  File names begin with the date, so
GitHub lists the reports oldest first and newest last, ahead of this file and
the template, and the listing is complete at every commit.  No file lists the
reports by hand: every report's pull request would have to edit that file, and
two such pull requests open at once would conflict as soon as one merged.
`field_report.py index` generates the table from the files' headers when one
is wanted.

[#252]: https://github.com/formalverification/agda-native-air/issues/252
[`GITHUB_PROJECT.md`]: ../GITHUB_PROJECT.md
[`mcp-field-reports.md`]: ../mcp-field-reports.md
[`TEMPLATE.md`]: TEMPLATE.md
