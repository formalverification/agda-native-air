<!-- File: docs/field-reports/2026-11-03-private-repo-interval-certificate.md -->

# 2026-11-03, a private repository: certifying a lattice as a group interval at two layers

+  **Date**: 2026-11-03.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 10.

The session added one emitted certificate module (about 14 000 lines of
tables), one emitted data module (a group of order 100 as tables, about 1 600
lines), one hand-written instance module (about 450 lines: a group built from
the tables, eight subgroups, an escalation classification, two order
isomorphisms), and small additions to five library modules (a record, three
transport lemmas, one cross-layer passage).  Every module checks; the final
gate was the project's own `make check` from the shell, twice, once per
rebuild of the aggregator.

+  **Tools used**.  `check_file` only, ten calls: once on the emitted
   certificate module (41 s cold, green first time), four on a library
   module whose import closure covered the five edited ones (2.7 s, 6.1 s,
   6.1 s, 3.1 s: the first three red, the fourth green), four on the instance
   module (34 ms for a parse error, then 79 s, 44 s, 46 s: red, red, green),
   and one on a downstream module after a definition moved between two
   library files (7.5 s, green with one warning).  The cost of each call was
   the stale part of the import closure plus the file; the server reused the
   interfaces the shell's `make check` had just built, so no call paid for
   the whole library.
+  **What worked**.  The diagnostics were root cause first and named the fix
   in every red run: an `UnsolvedConstraints` whose blocked metas showed a
   defined relation unfolded into a lambda over a record projection (the
   implicit arguments of a composition lemma could not be inferred from a
   type that unfolds that far, so they were passed explicitly, four times in
   three files); an `UnsolvedMetaVariables` whose ranges pointed at an
   implicit index created under an operator-section binder (`(_≈ f x)`),
   which is applied to the section variable and so is not a pattern, fixed
   by writing the lambda and the index out; a `ParseError` for a `where`
   clause under an `opaque` block; and a `CoverageNoExactSplit` warning
   naming the overlapping clause.  The `ClashingDefinition` that the shell
   gate found (a name already exported by a module the barrel re-exports)
   was outside every `check_file` closure the session had chosen, which is
   the gate's job, not the tool's.
+  **What was awkward or missing**.  Nothing blocked.  Two observations.
   First, `check_file` reports elapsed time but not memory, and this
   session's question for the heaviest module was its residency under the
   project's 6 GB cap; that number came from the shell (`+RTS -s`) and the
   per-definition profile (`--profile=definitions`) in one run, so the tool
   was not consulted for the measurement at all.  Second, when the
   diagnostic's `involved.metaTypes` quoted a meta applied to `(section =
   (f x))`, the notation took a minute to read as "a meta under a section
   binder"; a one-line gloss in the diagnostic would have saved it.
+  **Command line comparison**.  For the four library edits the tool loop
   was the more efficient: one call checked the stale closure and returned
   the first error with its range, where the shell's `make check` would have
   rebuilt the aggregator and run the whole library (about ten minutes cold
   here) to reach the same error.  For the heavy instance module the two
   were equal in time (the check itself is 45 to 80 s either way) and the
   shell won on information, since the memory and the profile were the
   point.  The session never used `fill_hole` or `get_goal`: the modules
   were written whole from two existing modules of the same shape, and the
   checker's diagnostics were enough to repair them.
