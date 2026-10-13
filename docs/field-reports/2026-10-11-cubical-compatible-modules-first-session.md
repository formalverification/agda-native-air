<!-- File: docs/field-reports/2026-10-11-cubical-compatible-modules-first-session.md -->
<!--
  Recovered under issue #252.  Written on 2026-10-11 as a section of
  docs/mcp-field-reports.md in the main checkout and never committed there;
  recovered from main's stash of 2026-10-11 23:17.  The title is the
  section's heading in this directory's form (the date, then the repository
  and the work, with "#N" written "issue N"), and the header was added from
  the section's own text, "not recorded" marking what it does not say.  The
  body is the section's, unchanged.
-->

# 2026-10-11, a private repository: four new modules under `--cubical-compatible` (Claude Opus 5.5)

+  **Date**: 2026-10-11.
+  **Harness**: Claude Code (version not recorded).
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 13.

Wrote four new Agda modules (76 to 397 lines; profile `--safe
--cubical-compatible`, one of them also `--prop`) in a private repository,
under Claude Code with the agda-mcp server connected (Agda 2.8.0,
agda-stdlib 2.3).  Each module was written whole and then repaired from the
diagnostics; the project's own gate ran on the command line at the end and
passed.

+  **Tools used**.  `check_file` 13 calls, nothing else: no holes, so
   `get_goal` and `fill_hole` had nothing to do, and standard-library names
   came from grep over the Nix store.  The failures were about names,
   operator precedence and universe levels, not about what term fills a
   goal.
+  **Speed**.  150 to 310 ms for a small module with warm library interfaces,
   4.2 to 4.6 s for the largest, which imports some forty library modules.
+  **Diagnostics that named the fix**.  `NotInScope` listed candidates, and
   the right one was among them (a module-qualified alias,
   `↭.↭-reflexive`).  An `UnequalTerms` whose `actual` was `A` and
   `expected` `B` at an argument position pointed at precedence: an
   operator declared without fixity bound tighter than another declared
   `infixl 5`.  `UnequalSorts` printed `Set A.a != Set a`, which named the
   cause, a generalized variable `A : Set a` whose level Agda generalizes
   separately from an `a` written in the same signature.
+  **Warnings, which the project's gate hides**.  `check_file` returns
   warnings with `severity: "warning"` beside errors, and on a passing file
   with `success: true`.  That mattered here: the project's checker reports
   only pass or fail, and three `UnsupportedIndexedMatch` warnings
   ("relies on injectivity of the data constructor `_∷_`", and on
   `Agda.Builtin.Bool.Bool.true` for the `yes` and `no` patterns of `Dec`)
   came only from `check_file`; the module was rewritten until it had none.
+  **Outside the project**.  `check_file` also checked a scratch file in a
   directory outside the repository (the project root became that
   directory) and reported its warning.  That call had
   `checkedFromSource: false`, because a command-line run had just left an
   interface file, and the warning still came back.
+  **Command line comparison**.  Five control files were checked on the
   command line instead, `nix develop --command bash -c 'cd … && agda F.agda'`,
   out of habit for files outside the project, before I found that the
   server took them too.  Each such run spent seconds entering the dev
   shell, against the server's sub-second answer on the same kind of file,
   and its output had to be filtered by hand.  The server was the more
   efficient loop for every check in this session; the command line was
   needed only for the project's gate.
