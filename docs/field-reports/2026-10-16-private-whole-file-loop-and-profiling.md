<!-- File: docs/field-reports/2026-10-16-private-whole-file-loop-and-profiling.md -->

# 2026-10-16, a private repository: two new modules by whole-file checks, profiling on the command line

+  **Date**: 2026-10-16.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 13, check_project 3, type_of 2,
   search_by_name 1.

The session added two literate modules to a private Agda library under
`--without-K --exact-split --safe` (Agda 2.9.0, the project's Nix dev shell,
the server launched from a git worktree): one of definitions and short
theorems that apply existing lemmas, and one of closed examples whose proofs
are `from-yes` and `from-no` of decision procedures, evaluated at check time.
Both were written whole, a block at a time, and checked with `check_file`
after each block; no holes were left for the server to fill.  Both modules and
the project gate went green; the gate ran 48 modules from source in 23.7 s on
the command line.

+  **Tools used**.  `check_file` was the loop: 13 calls, 1.9 to 2.4 s each
   when only the edited file was stale (almost all of it Agda loading the
   imported interfaces), and 9.6 s once, when edits to two imported modules
   made the server re-check them first.  `type_of` twice, to confirm that a
   record field's type elaborates at the universe levels a consumer will use
   (1.8 s on the lane's first load of the file, 0.4 s after an edit, with
   `lane.load: "changed"`).  `check_project` three times, 2 to 5 s against
   warm interfaces.
+  **What worked**.  Every red `check_file` led to the fix.  An
   `UnequalTypes` diagnostic quoted the expected and actual types, which showed
   at a glance that an infix product had bound looser than an infix
   equivalence; parentheses fixed it.  `check_project`'s `outputTail` listed
   the modules the gate re-checked, which showed that a dependency library had
   been checked from a second copy of its sources: an earlier `nix develop`,
   run without the variable that points the dev shell at the main checkout's
   copy, had rewritten the worktree's library registry.  The server read the
   new registry on its next call, as it should; only the tail made the switch
   visible.  `project.root` named the worktree on every answer.
+  **What was awkward or missing**.  Three things, as follows:
   +  Twice, an `UnsolvedConstraints` diagnostic came back first with no
      `line` or `range`, and its `involved.metaTypes` was the constraint text
      split on whitespace into dozens of fragments (qualified names and
      parenthesized pieces of terms), not types.  The root cause was in the
      second diagnostic, `UnsolvedMetaVariables`, whose first location was the
      line to fix.  The first time it was a library operator used with an
      implicit size argument left to inference, in an `open M arg` line; the
      second time, a definition whose type is a defined synonym for an
      implicit function type (`∀ {f} → ∀ {a} → …`), passed as an explicit
      argument, so that Agda inserted the implicit arguments early;
      eta-expanding it (`λ {f} {a} → d {f} {a}`) fixed that.  The
      ranked-first diagnostic should be one with a location when the other has
      none, and `metaTypes` should not be filled from a constraint's text.
   +  `search_by_name` with a two-segment qualified pattern (`M.f`, schematic)
      returned an empty list for a function that exists in the standard
      library, in the module the pattern names; a grep of the standard
      library's source in the Nix store found it at once.  Either the corpus
      does not index that module or a dotted pattern is not matched against
      qualified names; the answer does not say which.
   +  No tool reports time per definition, so every timing came from the
      command line (below).
+  **Command line comparison**.  For checking, neither loop was faster: a
   whole-file `check_file` and a command-line `agda` on the same file both
   took about 2 s, nearly all of it loading interfaces, and the server's
   structured diagnostics were easier to act on.  The command line was
   necessary for what the server does not offer: `--profile=definitions` and
   `--profile=internal` (to time each closed decision, all between under 10 ms
   and 52 ms, and to subtract deserialization from a module's own cost),
   `make clean` followed by a timed `make check` for the from-source wall time
   and peak memory, and `taskset` pinning.  A `profile` option on
   `check_file`, returning Agda's per-definition table, would have kept the
   timing in the server.
