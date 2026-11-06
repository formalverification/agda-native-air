<!-- File: docs/field-reports/2026-11-03-fls-chain-environment-record.md -->

# 2026-11-03, formal-ledger-specifications: a rule's environment record

+  **Date**: 2026-11-03.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: not named.
+  **Tools called**: definition_of 1.

The session changed the signature of one transition system in a Dijkstra-era
module, from a unit environment with a product signal to a new one-field
environment record with the block alone as the signal, and carried the change
through the rule's two constructors, its executable instance (the decision
procedure and the completeness proof), the foreign wrapper that exports the
step to Haskell, and the Haskell API's export list.  The whole change
typechecked at its first batch run; the closure gate then re-checked five
modules in 24 seconds and the test library's fifty modules in 102 seconds,
with zero warnings.

+  **Tools used**.  One `definition_of` on the edited module, 9.2 seconds,
   which answered at stage "load" with `NotInScope` for a mixfix name at line
   127 of a file in a dependency library.  The server's pinned Agda carries an
   older build of that dependency than the project's lock file now resolves
   (the pin went stale on an upstream bump two weeks earlier), so the lane
   cannot load any file of this tree.  No other tool was called: with the lane
   unable to load, `check_file` and `fill_hole` would have run the same stale
   wrapper.
+  **What worked**.  The error named the file and the line, which identified
   the stale pin at once, since an earlier session had recorded the symptom;
   no time went to suspecting the project's own code.
+  **What was awkward or missing**.  Nothing warns that the pin's dependency
   set no longer matches the project's lock.  A check at server start that
   compares the wrapper's library file against the project's flake, or a
   diagnostic that says "dependency pin stale" in place of a `NotInScope` deep
   inside a library, would have told the session in one line.  And the pin is
   fixed at registration (`--agda-bin` in the server's configuration), so a
   session cannot point the running server at the project's devShell binary;
   a per-call override, or an `agda-bin` resolved from the project's flake at
   start, would remove this class of failure.
+  **Command line comparison**.  The command line was the more efficient loop
   here, and not only because of the stale pin.  The edit was mechanical (one
   record, one signature, two constructors, four pattern-matching clauses) and
   composed in one pass from reading the files; the devShell's agda binary,
   resolved once with `nix develop --command which agda` and then run directly
   from the worktree root, checked the edited module in 14 seconds on a warm
   cache, so a batch check answered as fast as a lane query would have.
   Hole-driven development would have paid off only if the completeness proof
   had failed, and it did not.  Total agda-mcp time: 9 seconds, no answer.
