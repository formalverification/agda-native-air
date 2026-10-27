<!-- File: docs/field-reports/2026-10-26-fls-rebase-over-dependency-bump.md -->

# 2026-10-26, formal-ledger-specifications: two rebases over a dependency bump, and a stale pin

+  **Date**: 2026-10-26.
+  **Harness**: Claude Code 2.1.310.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: not named.
+  **Tools called**: none.

The session rebased two pull requests onto a `master` whose one new commit
bumped the agda-sets dependency.  It rebuilt one of them so that it carries a
colleague's open pull request's commit unchanged (the two then merge in either
order), replayed another model's commits on top, and made one Agda edit: a
`Computational` instance's decided conjunction, adapted to the colleague's new
rule, whose premise changed from a mapping function to a list equation.  Both
branches passed the whole-closure gate through the project's flake shell (243
and 242 modules from source, zero warnings).

+  **Tools used**.  None.  The bump changed a dependency of every module, so
   the whole closure had to be checked from source in any case, and the one
   edit had its shape fixed by the rule it decides.  Two detached batch runs
   with a status file did the work while the session did other things.
+  **What worked**.  Nothing to report for the server.  The project skill's
   recipe for a detached whole-closure gate held as written.
+  **What was awkward or missing**.  The Agda the server runs for this
   project is a pinned wrapper with the dependency libraries baked in as a
   library file, and it went stale silently when the project's lock file
   moved.  Its link resolves to a different build from the one the project's
   flake evaluates to now, and its agda-sets build lacks a definition the
   bump moved upstream from the project's own extension directory (a grep
   finds `_≢ᵐ_` in the new build and not in the pinned one).  The session
   found this by reading the bump's diff and comparing store paths by hand,
   not from the server.  A check through the server of a file on the new
   `master` should then fail with a scope error, though none was run.  The
   registration passes the same wrapper as the project's check command, so
   `check_project` would be affected too.  A startup check comparing the
   pinned libraries with the project's lock file, or a `project` block that
   names the library builds in use, would have surfaced it.
+  **Command line comparison**.  For rebasing and gating, the command line
   was the right loop: one detached script per branch, through the flake
   shell that the new lock file defines.  Hole-driven development had no
   place in this work.
