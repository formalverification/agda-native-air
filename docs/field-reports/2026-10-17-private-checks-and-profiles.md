<!-- File: docs/field-reports/2026-10-17-private-checks-and-profiles.md -->

# 2026-10-17, a private repository: new modules checked with the server, measured on the command line

+  **Date**: 2026-10-17.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 17, get_diagnostics 7, type_of 1,
   search_by_name 1.

The session wrote one new module of about 600 lines, a small supporting
module, additions to three existing modules, and five example modules whose
proofs are mostly decisions run by evaluation at type-checking time (one of
them carries about 2,500 lines of machine-generated data that a library
checker re-verifies).  Every module reached a green check_file before the
final whole-library gate, which passed from an empty build directory in about
40 s.  The server was connected from the start, on a worktree whose library
registry the dev shell had just created, and it served that worktree's files
without a root mismatch.

+  **Tools used**.  check_file was the loop: 17 calls, most 2 to 5 s on a warm
   interface cache, the heaviest example 24.8 s (its own check, measured
   later on the command line, was about 11 s after an optimization; the rest
   was dependencies).  get_diagnostics, 7 calls, on the largest module while
   its implicit arguments were being sorted out.  type_of once at the start,
   to confirm that the server resolved names in the new worktree (first load
   1.9 s).  search_by_name once, for a lemma about composing homomorphisms.
+  **What worked**.  The verdicts matched the command-line gate every time.
   The diagnostic codes named the fixes directly in most rounds:
   ClashingDefinition (a local name colliding with a generalizable variable),
   WrongHidingInApplication (implicit arguments in the wrong position, with
   the function's type printed), NotInScope with the candidate it wanted, and
   ModuleDoesntExport, correctly at warning severity, for a name a `renaming`
   clause asked for that the module does not export.  An UnequalTerms
   diagnostic printed the two stuck terms side by side, which showed at once
   that two evaluations agreed only up to a lemma, not by computation, so the
   fix was a lemma rather than a rewrite.  Checks of modules whose content is
   large decisions (thousands of instances swept by evaluation) behaved
   exactly like the batch command, timings included.
+  **What was awkward or missing**.  One round produced an UnsolvedConstraints
   diagnostic whose `involved.metaTypes` ran to several hundred lines of
   blocked constraints, ranked first, while the cause was named only by
   InversionDepthReached warnings further down ("refusing to invert pattern
   matching of" an operator defined by recursion, with the expression): an
   implicit argument that cannot be inferred from a type computed by a
   function.  The warnings were the useful diagnostics there, and a ranking
   that put an InversionDepthReached warning above the constraint dump it
   explains would have saved reading the dump.  search_by_name's corpus did
   not contain the lemma the library has today (it found only older copies
   under other module trees), so a grep of the library's sources answered
   instead.  No tool gives timings below the module; the profiling that
   decided which decisions to reorder (one change cut a module's own check
   from about 20 s to about 6 s for the same verdicts) was the command line's
   `--profile=definitions`.
+  **Command line comparison**.  For the edit-and-check loop the server was as
   fast as the command line and better, because its diagnostics arrived as
   codes and ranges rather than prose to grep.  For timing and profiling the
   command line was the only loop: costs under a memory cap, per-module and
   per-definition profiles, and checks of intermediate commits in a throwaway
   worktree.  The session used both, the server for writing and the command
   line for measuring.
