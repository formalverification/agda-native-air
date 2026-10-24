<!-- File: docs/field-reports/2026-10-22-private-long-development-session.md -->

# 2026-10-22, a private repository: a five-hour development session, sixteen new modules

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1, then Claude Opus 5.5 (Anthropic); the harness
   changed models partway through.
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 132, search_by_name 3.

A session in a private repository wrote sixteen new literate Agda modules,
about nine thousand lines, under `--safe` and `--without-K`, in about five
hours of wall clock, and finished with all of them checking and the library's
full gate green.  Every check of an edited file went through the server's
`check_file`; the command line was used only to profile, which the server
cannot do.

+  **Tools used**.  `check_file` 132 times: 40 green, 92 with diagnostics
   during development, none timed out.  The median call took 3.5 s; the
   longest took 104.6 s, a heavy module re-checked together with a heavy
   dependent after an edit to the dependent.  `search_by_name` 3 times, to
   find a standard-library lemma's exact name.
+  **What worked**.  The diagnostics named the fix in nearly every failed
   check.  `UnequalTerms` with its expected and actual terms showed which side
   of an arithmetic equation needed a rewrite, usually at a glance.
   `ClashingDefinition` listed the module-application chain that had brought
   the earlier definition into scope, which located name clashes introduced by
   opening a large module.  `UnsolvedMetaVariables` with ranges located the
   implicit arguments to make explicit; in one case making four of them
   explicit took a definition from 30.5 s to under 0.1 s.  `ModuleDoesntExport`
   caught an import line spliced into the wrong place by a script.
+  **What was awkward or missing**.  Three things.  First, no timing below the
   file: a check that grew from 11 s to 48 s gave no hint of which definition
   was responsible, and finding it took the command line's
   `--profile=definitions`; since the server's batch check writes the
   interface file, the profiling run had to delete that file first or it only
   loaded it.  A per-definition profile from `check_file` would remove that
   round trip.  Second, no memory figure: one design brought a module's peak
   to 5.9 GB against a 6 GB heap limit, which only `/usr/bin/time` on the
   command line showed; a peak-memory field in the verdict would have caught
   it at the first green check.  Third, `UnsolvedConstraints` for unification
   blocked inside a standard-library arithmetic operation produced over a
   hundred lines of `metaTypes`; the first constraint and its blocking meta
   were all that was needed.
+  **Command line comparison**.  For the edit-and-check loop the server was the
   more efficient: structured diagnostics with ranges, no shell quoting, and
   the green verdict trusted by its exit code.  For performance work the
   command line was necessary: per-definition and per-phase profiles,
   peak memory, and a cold check of the whole library.  A session doing both
   used both, and lost time only on the interface file the server had written.
