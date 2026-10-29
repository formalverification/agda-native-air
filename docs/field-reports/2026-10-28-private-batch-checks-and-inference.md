<!-- File: docs/field-reports/2026-10-28-private-batch-checks-and-inference.md -->

# 2026-10-28, a private repository: three new modules, checked whole

+  **Date**: 2026-10-28.
+  **Harness**: Claude Code 2.1.310.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 10, type_of 4, exports_of 1, check_project 1.

The session wrote three new literate modules (about 1,250 lines in all) in a
private repository, each a complete file of definitions and proofs over
setoids, then checked each with `check_file` until it was green, read back the
types of the main statements with `type_of`, and ran the project's gate with
`check_project`.  All three modules check under the project's safe options,
the gate is green, and each module's own check costs well under a second.  Two
of the ten `check_file` calls failed, both on the same kind of error, and each
was fixed in one edit.

+  **Tools used**.  `check_file` took 2.0 s to 3.2 s a call with the imported
   interfaces already built (a cold batch run each time, so this is mostly
   interface loading); `check_project` took 3.3 s, with one module to recheck.
   `type_of` took 1.9 s on its first call (the lane's load), 130 ms to 170 ms
   on a call that switched files, and 4 ms on a repeat.  `exports_of` was
   called once, on a dependency module that the file in scope did not import.
+  **What worked**.  The two failures were the same error: a function whose
   argument expects several implicit-argument laws, given a law by name, left
   that law's implicit arguments to inference, and Agda could not invert a
   definition by pattern matching to find them.  The `UnsolvedMetaVariables`
   diagnostic gave the exact source ranges of the unsolved metas (four short
   ranges on one line, then one on another), which pointed at the arguments to
   eta-expand with explicit implicits; in the first failure, the
   `InversionDepthReached` warnings named the definition Agda would not
   invert.  `type_of` on each main
   statement printed it with the enclosing module's parameters as explicit
   arguments, which is what was needed to confirm that the statements say what
   the prose says.  `check_project` reported `modulesChecked` and the gate's
   tail, and its verdict matched a command-line `make check` run afterwards.
+  **What was awkward or missing**.  In the first failure, the
   `UnsolvedConstraints` diagnostic came first (as the most likely root
   cause), and its `involved.metaTypes` array held several hundred strings
   that were fragments of the constraint's printed text, split at its line
   breaks, not the types of metas.  It made that one answer many times longer
   than any other, which `maxDiagnostics` does not bound, and it carried no
   source range; the second diagnostic, `UnsolvedMetaVariables`, was the
   actionable one.  `exports_of` answered `NotInScope` for the module that the file did
   not import, as documented, and its "did you mean" suggestions were
   unrelated names from the standard library; the module's exports were then
   read with grep from its source.  `get_goal` and `fill_hole` were not used:
   each definition's type was known before it was written, so the modules
   were written whole and checked, and no hole was ever open.
+  **Command line comparison**.  About even for this work.  The checks were
   no faster through the server than `agda` from the command line (both run
   a cold batch Agda), but the structured verdict and the meta ranges were
   quicker to act on than scanning Agda's text, apart from the one oversized
   constraint answer, which a command line piped through `head` would have
   kept short.  The command line remained the tool for the per-module cost
   (`--profile=modules`) and for the project's release gates, which the server
   does not run.
