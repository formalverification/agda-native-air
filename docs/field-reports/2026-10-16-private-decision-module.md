<!-- File: docs/field-reports/2026-10-16-private-decision-module.md -->

# 2026-10-16, a private repository: a new module of decisions, checked through the server

+  **Date**: 2026-10-16.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 7, search_by_name 1.

The session wrote one new literate Agda module of about 890 lines in a
private repository: ninety-four decisions by evaluation (`from-yes` and
`from-no` on the library's decision procedures), one proof of about ninety
lines by case analysis on inversion lemmas, and a few short derived lemmas,
each written whole after the statements and their witnesses had been chosen
with a Python tool.  The module checked green on its first full check
through the server, and again after an edit to its prose; hours later a
second block of eighteen decisions, two lemmas generalized from the first
block, and one short proof also checked green on the first call, and again
after its witness was replaced by a smaller one; a third block, thirty-one
decisions (one on a term of 190 generator occurrences) and a lemma of three
lines, checked green on its first call too.  The session's other Agda
work, the whole-library gate and the module's timing, ran on the command
line.

+  **Tools used**.  `check_file` five times: once on an existing module of
   the repository as a connection check (2.5 s, `checkedFromSource` false,
   since its interface was current), and six times on the new module (2.5,
   2.9, 2.5, 2.4, 1.9 and 2.6 s, exit 0, no holes, no diagnostics;
   `checkedFromSource` true except for the 1.9 s call, made right after a
   command-line check had written the interface).
   `search_by_name` once, with a short substring that is also a common word:
   the answer, about 80 KB on one line, was over the client's output limit
   and was saved to a file instead of shown.
+  **What worked**.  The verdict that mattered came fast and was
   unambiguous: the new module, its long proof included, checked green on the
   first call, and so did the later blocks.  The server had started before the worktree's library registry
   existed (the session created it by entering the dev shell after it began),
   and the first check found the registry anyway; `project.root` named the
   worktree, so there was no doubt which checkout had been checked.
+  **What was awkward or missing**.  `search_by_name` with no module filter
   matches across the whole corpus in name order, here the dependency's names
   before the repository's own, and one common substring overflowed the
   client.  A filter by module prefix, or a smaller default `limit` with the
   total and a way to continue, would have made it usable; the session used
   `grep` on the repository's sources instead, which answered in a second.
   No goal or hole tool was needed, since the proof was written whole.
+  **Command line comparison**.  For this work the two loops were about even,
   and the server was a little faster per check: `check_file` took 2.4 to
   2.9 s, and the command line 2.7 to 5.1 s wall for the same file, the dev
   shell's start and the interfaces' load included, while Agda's own
   `--profile=modules` put the module's check at about 0.33 s, before the
   second block and after it, and 0.8 s after the third.  The command
   line was the better tool for what the server does not do here: the
   module's cost against the repository's heavy-module mark, measured three
   times, and the whole-library gate, run in the dev shell as the
   repository's CI runs it.
