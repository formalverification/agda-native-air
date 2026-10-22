<!-- File: docs/field-reports/2026-10-22-private-whole-module-checks-and-eval-costs.md -->

# 2026-10-22, a private repository: five new modules checked whole, with the cost work on the command line

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 12.

The session wrote five new literate Agda modules (about 2,300 lines in all) in
a git worktree of a private library, each written whole and then checked with
`check_file` until green, and did all timing and profiling with the batch
`agda` on the command line.  All five modules check; the library's own gate
passes.  No hole was ever left in a file, so no goal or fill tool was called.

+  **Tools used**.  `check_file` 12 times, on five files: 2.2 to 3.8 seconds
   per call against warm interfaces, and 8.2 and 10.5 seconds for the two
   calls on a file whose check evaluated large closed terms.  Every call resolved the project
   root to the worktree (`rootSource: nearest-agda-lib`), as the
   registration intends; the session did not pass `verbose` to see which
   binary ran, and relied on the registration's wrapper (Agda 2.9.0 in the
   checkout's dev shell, which the command line runs too).
+  **What worked**.  Three of the five modules were green on the first call.
   Every `NotInScope` diagnostic carried candidates that named the fix
   directly (a missing `_+_`, a missing projection, a missing lemma name):
   one edit and one more call each.  For a definition whose implicit
   arguments Agda could not infer, the `UnsolvedConstraints` error came with
   an `InversionDepthReached` warning on the exact expression, and that
   warning, not the error, was what pointed at the fix (pass the arguments
   explicitly).  `success` and `verdict.exitCode` always agreed with what
   the command line later reported for the same file.
+  **What was awkward or missing**.  Two things.  First, size: on a file with
   unsolved metas over large normalized terms, the `involved.metaTypes`
   array of one diagnostic ran to several hundred entries, each a fragment of
   a normal form, so a capped `maxDiagnostics: 3` still returned a very long
   answer; the useful part was the meta locations in the second diagnostic,
   which a client could have had without the dump.  A per-diagnostic cap on
   `involved`, or a `brief` mode that keeps locations and drops metaTypes,
   would help.  Second, cost: the work needed per-module and per-definition
   check times (`--profile=modules`, `--profile=definitions`), runs pinned to
   one core with `taskset`, and a library rebuild from source with an
   alternating control arm on another checkout; none of that is in the
   server's surface, so all of it ran on the command line.  A `profile`
   option on `check_file` that returns Agda's profile table would have
   covered the first two.
+  **Command line comparison**.  For writing and fixing the modules, the
   server was as fast as the command line and its structured diagnostics
   were easier to act on (codes, ranges, candidates).  For the cost work,
   which in this session was about a third of the time, the command line was
   the only loop: it found a definition costing 1.3 seconds of conversion
   checking (by `--profile=definitions` and bisecting with holes, each run
   about 4 seconds) that the server's verdicts, being only green or red,
   could not show.
