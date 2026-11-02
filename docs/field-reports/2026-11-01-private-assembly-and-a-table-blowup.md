<!-- File: docs/field-reports/2026-11-01-private-assembly-and-a-table-blowup.md -->

# 2026-11-01, a private repository: assembling a result from its parts, and a table instance the lane could not hold

+  **Date**: 2026-11-01.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 5.

The session closed a formalization whose hard part earlier sessions had
carried through: it wrote four new literate modules (a transport of a finite
structure to the form the library's finite theory works on, by deduplicating
an enumeration with the standard library's `deduplicate`; the assembly of a
record that other modules had taken as a hypothesis; a module restating three
theorems with that record supplied; an example module) and added one instance
on a 14-element table to an existing example module, besides prose, a manifest
and a README.  Every new module checks in under 0.2 s of its own.  The
instance hit a known trap, which five one-definition probes on the command
line located in a few minutes.

+  **Tools used**.  `check_file`, once per new module after writing it whole:
   1.9 s (one warning, `CoverageNoExactSplit`, naming the two clauses it
   concerned), 2.9 s, 2.9 s and 2.9 s (one of these failed, with
   `UnsolvedConstraints` and `UnsolvedMetaVariables`, whose
   `involved.metaTypes` quoted the stuck constraints: two metas blocked on a
   lookup into a closed vector, from a generic order lemma applied at
   concrete tables), and a fifth on the edited example module, which the lane
   killed at its bound after 125 s (`success: false`, `exitCode: -9`,
   `timedOut: false`).  No `get_goal` or `fill_hole`: the modules were short
   enough to write whole, and each needed at most one revision.
+  **What worked**.  The warning named the exact clauses, and the fix was an
   as-pattern on the argument the case tree split.  The unsolved-constraint
   diagnostic made the failure legible without opening Agda: the blocked
   lookups said that the lemma's implicit middle term was being inferred
   through a table, so the proof was rewritten as a case split on the five
   candidates, which checked on the next call.  For the four new modules the
   loop was write, check, read the one diagnostic, fix: four calls and no
   command line.
+  **What was awkward or missing**.  The killed check answered
   `exitCode: -9` with `timedOut: false`, so the answer does not say that the
   bound was hit; a reader infers it from the elapsed time.  More to the
   point, a check that dies at the bound gives no diagnostic, and "what is
   slow" cannot be asked of the server: the session fell back to the command
   line for five probe modules of one definition each, run in parallel under
   `timeout 300` and a 6 GB heap, which located the cost (a module
   application with inferred implicit arguments at a concrete table: 113 s
   and the heap exhausted; the same application with the arguments given,
   2 s).  A per-call time bound on `check_file`, or a `--profile=modules`
   echo in the answer of a slow check, would have kept the question on the
   server.
+  **Command line comparison**.  For the four new modules the server was the
   more efficient loop: one call each, the diagnostic's structured fields
   answering the question.  For the instance the command line was, and had
   to be: the lane's bound is the server's, not the caller's, and the probes
   needed parallel runs with their own bounds and memory caps, which a shell
   gives in one line.  The library's cold check ran through the project's
   Makefile, as the project prescribes.
