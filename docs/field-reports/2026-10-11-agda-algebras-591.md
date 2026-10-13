<!-- File: docs/field-reports/2026-10-11-agda-algebras-591.md -->
<!--
  Recovered under issue #252.  Written on 2026-10-11 as a section of
  docs/mcp-field-reports.md in the main checkout and never committed there;
  recovered from main's stash of 2026-10-11 23:17.  The title is the
  section's heading in this directory's form (the date, then the repository
  and the work, with "#N" written "issue N"), and the header was added from
  the section's own text, "not recorded" marking what it does not say.  The
  body is the section's, unchanged.
-->

# 2026-10-11, agda-algebras issue 591: semidistributivity and Whitman's condition (Claude Opus 5.5)

+  **Date**: 2026-10-11.
+  **Harness**: Claude Code (version not recorded).
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: ualib/agda-algebras.
+  **Issue or pull request**: issue 591, pull request 601.
+  **Tools called**: check_file 7, type_of 1.

Claude Code launched from the worktree root, agda-mcp connected (Agda 2.8.0;
the project is on 2.9.0).  Result: five new modules (about 1,000 lines:
predicates, invariance and decisions; the free-lattice theorems; a
table-driven lattice constructor; the examples `M₃` and `N₅`), a sweep added
to `Setoid.Algebras.Finite`, and a pull request, in under an hour of wall
time, about half of it reading.

+  **Tools used**.  `check_file` 7 calls, one per module draft (2.5, 19.4,
   14.2, 9.6, 5.9, 6.1, and 6.6 s), and `type_of` once (27.9 s, a first lane
   load) to read the elaborated type of `canonicalJoinands-refine`.  Nothing
   else.  Standard-library signatures came from grep over the Nix store.
+  **What happened**.  Every `check_file` call answered `success: true` on the
   first try, so the server was a verdict oracle only: no diagnostic was ever
   read, no hole was opened, and `get_goal` and `fill_hole` had nothing to do.
   The modules were planned on paper from the existing APIs (the inversion
   `∧≤∨-inv`, Theorem 1.19 as `canonicalJoinands-refine`, `≅→≤`) before a line
   was written.
+  **2.8.0 against 2.9.0**.  Every server verdict agreed with the 2.9.0
   command line.  The server keeps its own `_build/2.8.0`, so the first check
   after an edit to an imported module re-checked the importers under 2.8.0
   as the command line did under 2.9.0; the work was done twice.
+  **Command line comparison**.  Inside `nix develop`, the worktree's
   `./.agda/bin/agda` took 1.0 to 7.8 s for the same modules, faster than
   `check_file` on every one, and it is the version of record, so each module
   was checked both ways.  Three controls for the decision procedures (a
   wrong verdict that must be rejected, and two lattices whose verdicts are
   known from the literature) ran on the command line out of habit; the
   expected failure came back as exit 42 with an `UnequalTypes` message that
   was enough on its own.  On this issue the command line was the more
   efficient loop: the work had no debugging in it, and for pure verdicts the
   server's structured diagnostics bring nothing while its older Agda costs a
   second check.  The server would have earned its place had a module failed.
