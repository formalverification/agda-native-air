<!-- File: docs/field-reports/2026-10-21-private-generated-data-and-check-time-decisions.md -->

# 2026-10-21, a private repository: new modules with generated data and decisions at check time

+  **Date**: 2026-10-21.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh (the harness settings' `effortLevel`).
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 9, normalize 1, search_by_name 4.

The session wrote five new literate modules: two of definitions and general
lemmas (about 200 and 340 lines), one generated data module of about 1,100
lines, and two that decide finite statements at check time by `from-yes`
of nested `all?`, one of them marked heavy under the project's barrel
policy.  It wrote each module whole and fixed it from `check_file`'s
diagnostics, without holes; all five check, and the project's gate passes.

+  **Tools used**.  `check_file` nine times, answered in 0.6 to 8.1 s:
   five accepted modules and four rejections, each fixed in one edit
   (`UnsolvedConstraints`, `ModuleDoesntExport`, `LiteralTooBig`,
   `UnequalTypes`).  `normalize` once, on a sum that the check-time
   decisions would evaluate a few hundred times: 4.1 s, of which the
   lane's first load was 3.8 s (`lane.loadElapsedMs`).  `search_by_name`
   four times, all answered at once.
+  **What worked**.  The diagnostic codes made each fix mechanical.
   `UnsolvedConstraints` listed its blocked constraints in
   `involved.metaTypes` (`_m_708 * n = m * n : ℕ`), which named the cause,
   an implicit argument that cannot be inferred through a product, so the
   fix was to pass it explicitly.  `LiteralTooBig` (Agda expands a
   natural-number literal pattern into `suc` patterns) ruled out a
   generated function that matched on large literals before any time went
   into it, and `ModuleDoesntExport` carried the missing name in
   `involved.candidates`.  The `normalize` answer, with the load time
   reported apart from the total, gave the cost of one evaluation (about
   0.26 s), which predicted the first design's check time (about two
   minutes; the command line then measured 140 s) and led to a second
   design whose decisions take 6 s.
+  **What was awkward or missing**.  `search_by_name` found nothing for
   three standard-library lemmas the session needed and the library has
   (`sum-permute` in `Algebra.Properties.CommutativeMonoid.Sum`,
   `combine-injective` and `remQuot-combine` in `Data.Fin.Properties`),
   while a search for a function of the project's other library
   dependency found it at once; the corpus appears not to index the
   standard library, and the session located the lemmas and their
   neighbors by grep in the Nix store.  `check_file` cannot pass Agda's
   `+RTS` options or `--profile`, and the project's policy turns on each
   module's own check time under a heap cap, so every timing ran on the
   command line
   (`+RTS -M6G -A128M -RTS` with `--profile=modules`, then
   `--profile=definitions`, which placed 5.8 s of a 6.2 s module in one
   definition).  A `profile` option on `check_file`, returning Agda's
   table, would have kept that in the server.
+  **Command line comparison**.  For writing the modules the server was
   the better loop: answers in seconds with the cause in a structured
   field.  For measuring check-time cost the command line was the only
   loop, since the measurement needs the heap cap and the profiler.
