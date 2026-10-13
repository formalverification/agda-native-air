<!-- File: docs/field-reports/2026-10-13-private-filter-ideal-assembly.md -->

# 2026-10-13, a private repository: an assembly step that blew up the checker, bisected and fixed

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 5, type_of 1.

The session's work was elaboration engineering: a construction whose
mathematics was finished two months ago had been stalled by an Agda blowup
(one lemma application exhausting a 32 GB heap at a concrete instance of
sixty elements), and the task was to rebuild the ambient object so that the
checker could get through, then repeat the construction at an instance of 216
elements.  The outcome: one new generic module (checks in 3 s), the
sixty-element instance assembled (4.9 s of CPU, 616 MB of residency, where the
old approach spent 32 GB on one application), the 216-element data module
emitted and checked (11.9 s, 986 MB), and the 216-element instance checked
under the project's 6 GB cap (459 s, 2.5 GB of residency) after its
decisions were rewritten as Boolean folds; with the library's `Dec` sweeps it
had needed a 14 GB heap.  Three findings that the session did not set out to
make decided these results, and all three were found by bisection on the
command line, not through the server.

+  **Tools used**.  `check_file` on the module to extend, before any change:
   green from its interface in 2.5 s, which confirmed the server was wired to
   the worktree's own Agda and library registry.  `check_file` on the new
   generic module twice: the first answered `AmbiguousName` with both
   candidates and the two `open` sites that brought them in (the fix was
   obvious from the message), the second was green in 3.3 s.  `check_file` on
   the first extended version of the instance module: still running after
   120 s, moved to the background by the harness, and at 176 s the Agda
   process was at 7.1 GB and 100 % CPU; stopped with `TaskStop`.  `check_file`
   on the final instance module: green from its interface in 2.5 s.  `type_of`
   on the headline theorem: answered 154 kB on one line, the lattice argument
   fully expanded into its tables, saved to a file the harness would not let
   the session read whole; the module's own signature was the usable answer.
+  **What worked**.  The two diagnostics-shaped calls did exactly what the
   command line does, with the error's candidates and sites structured instead
   of in prose, and the interface-fresh checks were instant.  Nothing in the
   server's behavior was wrong.
+  **What was awkward or missing**.  Three things, all about cost rather than
   correctness.  First, `check_file` runs Agda with no heap cap: the runaway
   check reached 7.1 GB before it was stopped, where the project's gate caps
   at 6 GB and would have died in two minutes with a verdict.  A cap matching
   the project's RTS options (or an option to pass them) would turn a runaway
   into an answer.  Second, the server reports elapsed time but not memory, and
   this session's whole question was memory: every measurement that mattered
   (peak RSS, maximum residency, the exit code of a capped run) came from
   `/usr/bin/time` and `+RTS -s` on the command line, in sixteen scratch
   copies of the module truncated or extended by one definition each.  A
   `check_file` that returned Agda's `+RTS -s` summary, or at least peak RSS,
   would have let the bisection run through the server.  Third, `type_of` on
   a theorem whose type contains a large concrete argument printed the
   argument in full (154 kB); a bound on the printed size, or printing
   defined names unexpanded, would make the answer readable.
+  **Command line comparison**.  The command line was the more efficient
   loop for this session, by a wide margin, because the work was a
   measurement problem: of about forty Agda runs, all but five were timed and
   memory-capped runs of scratch or working modules, which only the command
   line can do today.  The server's share, two cold checks with structured diagnostics
   and three instant interface-fresh verdicts, was fine for what it was.  The
   session also wrote and checked Agda with no holes, so none of the goal
   tools were needed; the proofs were short enough to write from the lemma
   statements, and every error came back as a batch diagnostic.
