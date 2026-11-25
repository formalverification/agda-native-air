<!-- File: docs/field-reports/2026-11-24-private-toolchain-upgrade.md -->

# 2026-11-24, a private repository moved from the Agda 2.9.0 nightly to the release

+  **Date**: 2026-11-24.
+  **Harness**: Claude Code 2.1.332.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: medium.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: type_of 2, get_diagnostics 2.

The session moved a private library of about 220 modules from the Agda 2.9.0
nightly and a patched standard library 2.3 to the released Agda 2.9.0 and
standard library 2.4.1, by moving one flake pin.  Nothing failed to check; four
deprecated standard-library names were renamed in 38 modules by a scripted
textual replacement.  The work was a toolchain move, so the whole-library
`make check` from the command line, run under GNU time and in the background,
carried it, and the server was used only to confirm which Agda it ran before
and after the move and to give two per-module verdicts.

+  **Tools used**.  Before the move, one `type_of` with `verbose: true`
   (3.3 s, lane load `first`) showed the server running the worktree's own
   wrapper against the registry naming the old standard library.  After the
   dev shell was re-entered on the new pins, which rewrote the wrapper, one
   `type_of` (3.4 s) answered with lane load `restarted`, a new `agdaStamp`
   for the wrapper, and the new standard library in `registeredLibraries`.
   Two `get_diagnostics` calls (3.0 s and 4.2 s, interfaces already built)
   gave exit 0 with no warning for a ported module, and exit 0 with seven
   `UserWarning` diagnostics for a module deliberately left unported, each
   with the deprecation message naming the replacement.
+  **What worked**.  The wrapper stamp did what it is for: the server noticed
   that the Agda behind the wrapper had changed and restarted its lane on its
   own, with no restart of the server and no `reload`.  The `verbose` echo
   (the binary, the registry, the libraries it registered) settled which
   toolchain answered at each stage in one call.  The diagnostics' warnings
   agreed in count and position with the batch run's.
+  **What was awkward or missing**.  Nothing in the server.  The verdict for a
   whole-library toolchain move still has to come from a cold batch run with
   the interfaces deleted, which is minutes of wall time (five to seven here,
   at a load average between 6 and 11 from other sessions), so it ran outside
   the server.  `check_project` could have run it, but it blocks the session
   for the whole gate, where a background shell run left the session free to
   survey the deprecated names meanwhile.
+  **Command line comparison**.  For this work the command line was the more
   efficient loop: the port was a rename across many files with no holes and
   no proof search, and its evidence (counts of `Checking` lines, warnings by
   kind once per position, wall time, peak memory) came from the batch logs.
   The server earned its four calls by answering the one question the logs do
   not, which Agda and which registry a session's tools are using, before and
   after the move.
