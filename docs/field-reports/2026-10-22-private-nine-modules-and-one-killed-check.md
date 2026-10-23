<!-- File: docs/field-reports/2026-10-22-private-nine-modules-and-one-killed-check.md -->

# 2026-10-22, a private repository: nine new modules and a limit construction

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 40, type_of 1, search_by_name 1.

The session wrote nine new literate modules (about 2,300 lines) in a private
Agda library, all under `--safe`, and a theorem that assembles them: decision
procedures over finite data, an inductive predicate with a decidability proof
by a fixpoint on finite subsets, a classical principle as a record argument, a
generic limit construction with its laws derived from an order, finite
products with a finiteness structure, and a recursive construction whose final
theorem names the principle in its type.  The session was launched from the
worktree after one `nix develop` there, so the server answered for the
worktree's files from the first call (`rootSource: nearest-agda-lib`).
Every module was developed by writing it whole, calling `check_file`, and
fixing one diagnostic per round; the rounds were 9, 4, 2, 1, 8, 7, 4, 4 and
4 for the nine modules.  The pull request's final gate ran from the command
line.

+  **Tools used**.  `check_file` was the loop: 2 to 5 s per call for a module
   whose imports were already loaded, 40 calls in all.  One call was killed
   by the server after 134 s (`verdict.exitCode: -9`, no diagnostic, `success:
   false`); the command line then showed a heap exhaustion at the 6 GB bound
   in 48 s, and a bisection by truncated copies of the module, timed from the
   command line, found the cost in one definition.  `type_of` served as the
   probe that the server was bound to the worktree, and `search_by_name` with
   `inScopeAt` reported five hits none of which the file could write, which
   was the right answer (the name needed a different module).
+  **What worked**.  The diagnostics were precise enough to fix from without
   opening the file: AmbiguousName named both candidates and the opens that
   brought them (eight such rounds, all name clashes between a setoid's
   `sym`, `trans`, `refl` and the propositional ones, or two structures'
   order lemmas); NotInScope with its "did you mean" list; MetaCannotDependOn
   showed the mismatched quantifier order between a record field and its
   decider; UnequalTypes with `expected`/`actual` caught three fixity
   mistakes, where a local alias of a decision operator bound tighter than a
   term constructor; UnsolvedConstraints listed the metas, from which the
   pattern "a syntactic object cannot be inferred from its value under an
   interpretation" was read and fixed by making the term arguments explicit throughout one module.  The
   one ModuleDoesntExport warning (patterns `10F` to `15F` do not exist) came
   with the error it caused.
+  **What was awkward or missing**.  The killed call gave no indication of
   what it had been doing: no elapsed-time breakdown, no memory figure, no
   partial diagnostic, so the diagnosis moved to the command line (`agda +RTS
   -M6G` with `/usr/bin/time`) and to hand-made truncated copies of the
   module, about fifteen command-line runs.  A `check_file` option to report
   the peak heap and the time, and a way to check a file with a given RTS
   heap bound, would have kept that in the loop.  `search_by_name` without a
   corpus of the repository's own in-progress modules cannot find a name
   written minutes earlier; expected, but it meant `grep`.
+  **Command line comparison**.  The server was the more efficient loop for
   the development: each round was one call with a structured diagnostic,
   where the command line would have meant a run, a scroll and a parse, and
   the warm lane made the 2 to 5 s per call possible.  The command line was
   the better instrument for the one performance problem, because it reports
   time and memory and takes RTS options.
