<!-- File: docs/field-reports/2026-10-22-private-conversion-costs.md -->

# 2026-10-22, a private repository: six new modules, and two conversion blowups

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 17, normalize 2, type_of 1.

The session wrote six new literate modules (about 2,000 lines) in a private
library on top of a public one, with every module under `--safe`, and finished
with the project's own gate green from a cold cache.  The edit-and-check loop ran
through agda-mcp; the performance work, which took more of the session than the
proofs, ran on the command line, because two kinds of declaration cost minutes and
more than 10 GB to check and the diagnosis needed Agda's profiler and a memory cap.

+  **Tools used**.  `check_file` was the loop for every new module: 2 to 3 s a
   call on a warm cache (the dependencies' interfaces built), with diagnostics
   that named the problem in every failure but one (an unsolved implicit argument,
   a clash with an imported operator name, a parse error in a dependency, a wrong
   argument count to a smart constructor).  `normalize` measured one evaluation in
   place: the answer's `elapsedMs` minus `lane.loadElapsedMs` put one table
   operation at 35 ms before a change and 3 ms after.  `type_of` with `rewrite:
   AsIs` printed the type of an applied lemma.
+  **What worked**.  The diagnostics' `code` field and range, which made each
   fix a one-line edit; the verdict on the dependency that broke, not only on the
   file asked about (a parse error in an imported module came back from the
   importing file's check, with the right path); and `normalize`'s two timings,
   which isolate an evaluation from the load.
+  **What was awkward or missing**.  One `check_file` ran 182 s and came back
   `success: false` with `verdict.exitCode: -9` and no diagnostic.  The process
   had been killed for memory, which the answer did not say; a note that the exit
   was a signal, and which, would have saved a guess.  The server has no way to
   pass a memory cap or a profiling flag, so finding the cause (a `where` block
   inside a `with` chain, cheap once moved into a helper) took a bisection on the
   command line under `ulimit -v` with `--profile=definitions`.  Later, a
   declaration whose type printed exactly as its value's inferred type, under
   `type_of` with `AsIs`, cost 25 s to check: the two types differed only in which
   module copy named a definition, which display forms hide, so `type_of` could
   not show the difference that mattered.  The fix (`--lossy-unification` in the
   using module, and explicit implicit arguments to a module application whose
   inference went through a definition that reduces to a product) came from
   probes on the command line.  A `normalize` with `reload: true` reported a
   67 s load, which was the file's own expensive declaration being rechecked, not
   the expression; the answer was right, but a reader can mistake whose time it is.
+  **Command line comparison**.  For writing and fixing proofs, agda-mcp was the
   more efficient loop: no shell setup per call, structured diagnostics, and
   checks of a few seconds.  For performance it was not usable on its own: every
   finding about cost came from `agda --profile=definitions`, `--profile=conversion`
   and `/usr/bin/time` under a virtual-memory cap, on scratch modules truncated at
   a marker, and the server's own long checks were the ones most likely to end in
   an unexplained kill.
