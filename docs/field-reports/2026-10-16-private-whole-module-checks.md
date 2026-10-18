<!-- File: docs/field-reports/2026-10-16-private-whole-module-checks.md -->

# 2026-10-16, a private repository: two new modules written whole and checked with check_file

+  **Date**: 2026-10-16.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max (40 at the start of the session).
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 9.

The session added two literate Agda modules to a private library, one of about
740 lines and one of about 580, and edited a barrel module.  Each module was
written whole, from a proof worked out on paper, and then checked with
`check_file`; no hole was left in either, so the interaction lane was never
needed.  Both modules check under `--safe`, the library's gate (48 modules
from an empty build) passes, and the work is in a pull request.

+  **Tools used**.  `check_file` 9 times: 7 successes, each 2.3 to 3.5 s, on
   files whose dependencies' interfaces were built; 2 failures.  The first
   failure, 2.3 s, was a single `UnequalTypes` diagnostic on a definition
   whose signature used a generalized variable where the level of an
   explicitly bound one was meant; its range and its expected and actual
   types named the fix.  The second, 31.9 s, reported 8 diagnostics of code
   `SplitError.BlockedType`, all from definitions written as two names
   sharing one signature with an underscore for the result type
   (`f g : ∀ k → _`, mutually recursive); writing the full types out fixed
   all eight at once, and the next check passed.
+  **What worked**.  The verdicts were exact and the green results trusted:
   two additions of about 150 and 450 lines passed on their first check, and a
   command-line check from source, after deleting the interface, agreed each
   time (exit 0).  The project root was resolved from the worktree's library
   file (`rootSource: nearest-agda-lib`), so the session, launched from the
   worktree, checked the worktree's files with no configuration.  Diagnostic
   codes were specific enough to act on without reading the prose.
+  **What was awkward or missing**.  The eight `BlockedType` diagnostics came
   ordered from the last definition in the file to the first, where the
   README promises the most likely root cause first; for independent errors
   of one kind, source order would have read better, and a note that all
   eight share a cause (an underscore result type in a shared signature)
   would have saved reading them.  The failing check took ten times as long
   as a passing one, presumably the elaboration of the unsolved
   metavariables; that cost is invisible until it lands.  Profiling
   (`--profile=modules`) and the whole-library gate were run from the command
   line, in the background, since `check_project` blocks the session for the
   gate's duration (32 s here, at a load average near five).
+  **Command line comparison**.  For checking a whole module, `check_file`
   and the command line cost the same (about 2.6 s each, the command line
   inside the project's Nix shell), and `check_file`'s structured diagnostics
   made it the better loop.  For profiling and for the gate the command line
   was more efficient, because it can run in the background while the
   session works on something else.  The interaction lane (`get_goal`,
   `fill_hole`) was not needed: each proof was planned completely before it
   was typed, and the failures were declaration-level, not goal-level.
