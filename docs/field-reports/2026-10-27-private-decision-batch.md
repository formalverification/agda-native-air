<!-- File: docs/field-reports/2026-10-27-private-decision-batch.md -->

# 2026-10-27, a private repository: new modules of evaluated decisions

+  **Date**: 2026-10-27.
+  **Harness**: Claude Code 2.1.310.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 6.

The session added two new literate modules and two short definitions to an
existing one, in a private Agda library.  Almost every definition is a
decision procedure evaluated at check time (`from-yes`/`from-no` on a `Dec`,
or `refl` on a computed natural number), plus a few lines of composition.  All
three files checked on the first try, so no goal was ever open and no
interactive tool had work to do.

+  **Tools used**.  `check_file` six times: one existing module after an
   addition (2.1 s), the first new module three times (2.3, 2.6 and 2.4 s,
   after its first write, a re-wrap of two long lines, and the removal of
   unused imports), and the second new module twice (5.1 and 5.1 s).  Each
   was a cold batch run, imports included, and each came back
   `success: true` with no diagnostics.
+  **What worked**.  The server took the worktree as its project root
   (`rootSource: nearest-agda-lib`) although the session had been launched
   before the dev shell had written the worktree's `.agda/` directory; the
   first call after `nix develop` had created it simply worked.  Verdicts
   matched the command line's exit codes, and the full gate (`make check`,
   160 modules) agreed.
+  **What was awkward or missing**.  Nothing in the tool.  The work's real
   question was cost: how long a check-time evaluation takes on large terms,
   and how much memory it peaks at.  `check_file` reports `elapsedMs` but no
   peak memory, so the measurements (wall time and peak RSS under
   `/usr/bin/time`, and `--profile=modules` for a module's own share) were
   all made on the command line.  A peak-RSS field, or a pass-through for
   `--profile`, would have let the tool answer that question too.
+  **Command line comparison**.  For writing and checking, about even: a
   `check_file` call and a CLI run of the same file took the same time, and
   the tool's structured verdict saved reading Agda's output.  For
   measuring, the command line was the only loop: five probe modules timed
   under `/usr/bin/time` (one at 58 s and 3.6 GB), and three
   `--profile=modules` runs.  Had a file failed, `get_goal` and `fill_hole`
   would have mattered; here none did.
