<!-- File: docs/field-reports/2026-11-09-agda-algebras-639.md -->

# 2026-11-09, agda-algebras: Boolean folds for whole-lattice certificates

+  **Date**: 2026-11-09.
+  **Harness**: Claude Code 2.1.322.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: ualib/agda-algebras.
+  **Issue or pull request**: issue 639, pull request 640.
+  **Tools called**: check_file 9, get_diagnostics 1.

The session added a module of Boolean folds over `Fin` with soundness and
completeness lemmas, re-derived the library's whole-lattice certificate
decision and one per-congruence decider from Boolean twins, and added a
generated benchmark certificate (a 450 KB module) with its Python generator.
Most of the session was measurement: about forty capped, pinned, cold checks
of scratch copies, which agda-mcp could not and should not do.  The Agda
itself was small (three modules edited or added, roughly 250 lines of
definitions and lemmas), and every module passed its first or second check.

+  **Tools used**.  `check_file` after each edit of the three library modules
   and their barrel: 144 ms for the new 200-line folds module, 2.7 to 6.1 s
   for the 600-line checker module, which loads its whole dependency closure.
   One `get_diagnostics` confirmed a deprecation warning was gone.  One
   `check_file` caught a `ClashingDefinition` that a text-patching script had
   introduced (a block duplicated by a wrong index), named the two sites, and
   pointed straight at the fix.
+  **What worked**.  Batch verdicts were fast and exact, and the diagnostic
   `code` field (`ClashingDefinition`, `UserWarning` for the deprecation) was
   all I needed to read.  The `project.rootSource: nearest-agda-lib` line
   confirmed the server was checking this worktree, which mattered because
   the session started before the worktree's `.agda/` wrapper existed.
+  **What was awkward or missing**.  Three things.  First, scratch modules
   outside the library's include path (`agda -i scratch …`, kept out of `src/`
   so they could never reach the generated aggregator or a commit) cannot be
   checked or queried: the server has no way to add an include directory per
   call, so every probe went to the CLI.  Second, `check_file` writes
   interfaces, and an edit checked through it during a long measurement run
   made the run's next arms recompile their dependencies inside the measured
   time; the session had to stop a batch and rebuild a data module.  A
   per-call "do not write interfaces" option would have avoided it.  Third,
   pricing one evaluation with `normalize` (the cost question this work was
   about) would have needed the lane to load the 450 KB benchmark, a full
   uncapped check of it, so it was never tried.
+  **Command line comparison**.  For the measurements the command line was
   the only correct tool: they need `+RTS -M6G -s`, a deleted interface, a
   pinned core, and include paths the server does not take.  For the library
   edits agda-mcp was the better loop, about as fast as the CLI per check but
   with structured diagnostics; with only ten calls it neither sped up nor
   slowed down the session noticeably.
