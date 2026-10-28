<!-- File: docs/field-reports/2026-10-27-private-literate-batch.md -->

# 2026-10-27, a private repository: eight literate modules written whole, checked file by file

+  **Date**: 2026-10-27.
+  **Harness**: Claude Code 2.1.310.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 20, exports_of 1, search_by_name 1.

The session added six new literate Agda modules (about 1,900 lines with
prose) and extended three existing ones in a library of about 160 modules,
each new module between 100 and 550 lines, all under `--safe`.  It wrote each
module whole, checked it with `check_file`, and fixed what the diagnostics
named until the file was green; no hole was left open on purpose, so
`get_goal` and `fill_hole` were not needed.  Every module ended green, and the
project's own gate (a make target over an aggregator module) was run from the
shell at the end.

+  **Tools used**.  `check_file` 20 times, 2.2 to 4.2 s each with the
   imported interfaces already built, the time being mostly the load of the
   imports (the profiler later put each module's own check at 16 to 520 ms).
   `exports_of` once, on a module of the dependency library (2.7 s, a first
   load), to read the exact names and implicit arguments of a module
   before writing against it.  `search_by_name` once, which returned nothing
   for a lemma that, as `grep` then confirmed, the standard library does not
   have.
+  **What worked**.  The diagnostic codes named the fix in most rounds:
   `AmbiguousName` listed both candidates and where each came into scope (a
   standard-library operator clashing with a library one), and the fix was one
   renaming; `NotInScope` offered "did you mean", which pointed at a pair of
   mutually recursive definitions declared one at a time;
   `TerminationIssue` listed the problematic calls, and both rounds of it were
   fixed by passing a node's children apart instead of rebuilding the node in
   a call, which the listed call made plain.  The server had been started
   before the new worktree's local Agda configuration existed, and every check
   still resolved the libraries of the right checkout.
+  **What was awkward or missing**.  One root cause (an implicit type
   parameter of a data type that nothing in the types of its uses
   determined) produced five diagnostics, ordered `SplitError.UnificationStuck`
   first, then `UnsolvedConstraints`, then an `UnsolvedMetaVariables` listing
   about thirty locations; the ranking put a symptom first, and nothing named
   the parameter.  The fix (making the parameter explicit) came from reading
   the unsolved metas' types, which the diagnostic did carry.  Two later
   rounds were the same kind (implicit arguments of a function that its
   argument's type could not determine); the `UnsolvedConstraints` entry
   naming the blocked metas was the useful one each time, so a ranking that
   put it first when it names a definition's own implicit would save a read.
+  **Command line comparison**.  For this work, writing whole modules and
   checking them, the server and the command line cost the same per check
   (the interface load dominates both), and the server was the better loop
   only for its structured diagnostics: codes, candidates and ranges without
   reading the batch output.  The project's gate, the per-module profile and
   the release checks ran from the shell, as they must; the server's
   `check_project` was not tried.
