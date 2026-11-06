<!-- File: docs/field-reports/2026-11-03-private-repo-interval-certificate.md -->

# 2026-11-03, a private repository: certifying a lattice as a group interval at two layers

+  **Date**: 2026-11-03.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Fable 5.1, then Claude Opus 5.5 (Anthropic).
+  **Effort**: high, then max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 12.

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

## Addendum, 2026-11-04: a green the project's gate could not hold

The same session, continued the next day after the pull request's CI run
failed with `Heap exhausted` under the project's 6 GB heap cap, in the
emitted certificate module that `check_file` had reported green in 41 s
(above).

+  **What happened**.  Checked alone from the shell under the project's
   options plus `+RTS -M14G -s`, the module needs 6.27 GB of residency and
   11.8 GB in all.  `check_file` runs batch Agda with no `-M`, so it passed,
   and it wrote the module's interface; the project's capped gate then found
   that interface current and never re-checked the module, so the gate was
   green locally twice.  CI, building from a cache without the interface,
   was the first capped check the module ever had.  The report above called
   the call "green first time", which was true of the tool and said nothing
   about the build.
+  **What the session did**.  Two more `check_file` calls (a library module,
   4.2 s, green first time; the module that replaced the heavy one's use,
   67 s, green), and every memory figure from the shell: the module under
   the cap with its interface deleted, `+RTS -s` for residency, and
   `--profile=definitions` for where the time went, on scratch copies that
   located the cost.  The heavy module moved to the project's separate
   high-memory lane.
+  **What was awkward or missing**.  A green `check_file` on a new large
   module is no evidence that the module fits the project's gate, and the
   interface it leaves behind makes the gate agree.  Three things would have
   caught it: `check_file` taking the project's RTS options (or a heap
   cap), reporting peak memory beside elapsed time, or flagging a check
   whose peak exceeds a configured bound.  Until then the remedy is the
   shell's: delete the interface and check under the gate's options.
+  **Command line comparison**.  For this question the command line was
   the only instrument; the tool loop stayed the faster way to find type
   errors.
