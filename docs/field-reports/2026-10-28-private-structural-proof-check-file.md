<!-- File: docs/field-reports/2026-10-28-private-structural-proof-check-file.md -->

# 2026-10-28, a private repository: one structural module against check_file

+  **Date**: 2026-10-28.
+  **Harness**: Claude Code 2.1.310.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 7.

The session wrote one new literate module of about 780 lines, all structural
proofs (inductions and a well-founded recursion, no decision procedure run on a
concrete term), and developed it against `check_file`, with the project's own
`make check` run from the shell as the final gate.  The module was written
whole before the first call; that call was red, one edit pass fixed every
error, and every later call was green.  The gate was green at the end.

+  **Tools used**.  `check_file` seven times on the one file.  Six took 2.36
   to 2.49 s with the imported library's interfaces already built; one took
   12.0 s, right after an unrelated shell command had entered the project's
   dev shell without an override variable, which rewrote the library registry
   the server reads to point at another copy of a dependency.  The first call
   returned success false, exit code 42, and 14 diagnostics:
   `UnsolvedConstraints` first, then `UnsolvedMetaVariables` with some thirty
   ranges, then a series of `InversionDepthReached` warnings.
+  **What worked**.  The warnings named the cause.  Each `InversionDepthReached`
   named the defined function Agda refused to invert and the expression whose
   type it was checking, and the `involved.metaTypes` of the first error listed
   every constraint with the meta it was blocked on.  Together they showed one
   cause behind all fourteen: a predicate written as a function into a Π type
   rather than as a data or record type, so that unification could not recover
   its argument from a hypothesis of that type.  The fix was to pass those
   arguments explicitly, at ten sites, in one edit; the next call was green.
   The verdict came from the exit code, and the empty hole list confirmed that
   nothing was left open.
+  **What was awkward or missing**.  The root cause sat in the warnings, after
   the two errors, although the list is ordered most likely cause first; the
   first error's message was cut after 22 lines and the meta list was mostly
   repetition.  When `InversionDepthReached` warnings accompany unsolved metas,
   ranking them first, or grouping the metas by the definition that blocks
   them, would put the cause at the top.  The 12 s call came with no word of
   why; a line saying that the registry had changed since the last call would
   have explained it without `verbose`.  `get_goal`, `fill_hole` and the
   search tools were not needed: the proofs were written from the types of
   existing lemmas, which the session read in their source.
+  **Command line comparison**.  About even for this work.  The command line
   checked the same module in 2.05 s wall (three runs), against 2.4 s for
   `check_file`, and either loop would have found the same fourteen errors.
   The server's structured diagnostics made the single red call quicker to
   diagnose than Agda's plain output would have been, and that was the one
   place the choice mattered.
