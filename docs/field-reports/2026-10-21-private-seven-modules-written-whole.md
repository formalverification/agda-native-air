<!-- File: docs/field-reports/2026-10-21-private-seven-modules-written-whole.md -->

# 2026-10-21, a private repository: seven new modules written whole and checked one at a time

+  **Date**: 2026-10-21.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 12, type_of 3, exports_of 1, search_by_name 1,
   search_by_type 3.

The session added seven literate modules to a library, about 2300 lines in
all.  Most of the work generalized existing definitions and proofs over one
more parameter; one module carried a new proof.  Each module was written
whole and checked with `check_file`, with every import's interface already
built, and six of the seven were green on their first check.  `type_of`
then confirmed the statements the modules export, and the command line did
the measurement: per-module timings, profiling, and alternating cold runs of
the project's gate.  The server ran from the worktree root after one
`nix develop` there, and every answer named that worktree as its project
root.

+  **Tools used**.  `check_file` took 2.0 to 3.2 s a call, a cold batch agda
   each time.  The one module that failed took three checks.  The first
   failure was `UnequalTypes` with a one-column range, at a positional
   implicit argument that had bound a generalized level variable instead of
   the argument meant.  The second was `UnsolvedConstraints` together with
   `UnsolvedMetaVariables`, whose `metaTypes` named the two proof arguments
   the elaborator could not infer, with the line and columns of the call.  The
   third was green.  Both diagnostics named the fix outright.  `type_of` took
   2.1 s for its first question (the lane loading the file) and 3 ms for each
   later one; it showed the generalized implicit arguments in Agda's own
   order, which is what a reader of the module meets.  `exports_of` with a
   `pattern` took 178 ms and listed the twenty matching members of a
   dependency with their types, which settled that the names a new module
   imports are public without opening the file.
+  **What worked**.  The diagnostics' codes and ranges were exact, and
   success was the exit code alone, so a green answer could be trusted without
   reading the output.  The lane's reuse made the statement checks cost
   nothing.  Writing whole modules and checking each once was the right grain
   for definitions transcribed from existing ones; no hole was needed, so
   `get_goal` and `fill_hole` went unused.
+  **What was awkward or missing**.  `search_by_name` and `search_by_type`
   returned empty lists for one standard-library name and three standard
   arithmetic statements that exist, with no hint that the corpus covers the
   project and not the standard library.  The session fell back to grepping
   the standard library's sources in the Nix store.  A note in an empty
   answer saying which libraries the corpus holds would have saved the four
   calls.  The server has no profiling tool: a module's own type-checking
   time, as against the loading of its imports (25 to 392 ms of each 1.5 to
   2.2 s check here), came from the command line's `--profile=modules`, and
   the gate's peak memory from `/usr/bin/time`, which `check_project` does not
   report.
+  **Command line comparison**.  For writing and checking, the server was
   slightly the better loop: each check cost what the command line costs,
   about 2 s, but needed no `nix develop` wrapper and no reading of Agda's
   prose for the verdict.  For measurement the command line was the only
   loop: timing a module with only its own interface deleted, profiling it,
   and alternating cold runs of the gate across two checkouts are not things
   the server does.
