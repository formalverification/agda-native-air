<!-- File: docs/field-reports/2026-10-13-agda-algebras-616-direct-decompositions.md -->

# 2026-10-13, agda-algebras: direct decompositions, six new modules and an example

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: ualib/agda-algebras.
+  **Issue or pull request**: pull request 616.
+  **Tools called**: check_file 49, type_of 1.

The session wrote about 3,000 lines of literate Agda for agda-algebras: six new
modules under `Setoid.Decompositions` (factor pairs, products of congruences,
indecomposability, decision procedures and a factorization theorem for finite
algebras, the strict refinement property and unique factorization), a worked
example that decides a factor pair by evaluation, and small additions to seven
existing modules.  It also wrote one example module in a downstream private
library that imports the new modules.  Everything was drafted in sections of
20 to 150 lines and checked with `check_file` after each section; the library's
own gates (`make check` and six others) ran on the command line at the end, and
all passed.

+  **Tools used**.  `check_file` was the whole loop: 49 calls, 30 green on the
   first try and 19 red, each red one fixed in one or two edits.  A call took 2
   to 8 s on a section whose dependencies had interfaces, and 12 to 15 s when a
   changed dependency had to be rechecked.  `type_of` was called once, at the
   start, to see that the server would answer for a file in another checkout.
   No hole was opened: the definitions were small enough to write whole, so
   `get_goal`, `fill_hole`, and the search tools went unused.
+  **What worked**.  One server served two checkouts.  It was launched from
   the downstream library's worktree, whose library registry pointed at a
   worktree of agda-algebras, and it answered for files in both, resolving each
   file's root from its nearest `.agda-lib` (`rootSource: nearest-agda-lib`); so
   a change spanning two libraries was developed in one session with no
   restart.  The diagnostics were precise and structured: `AmbiguousName` listed
   both candidates with the open that brought each into scope (seven of the 19
   failures, all clashes between a setoid's `sym`, `refl`, or `reflexive` and
   another module's, each fixed by a `renaming`);
   `ImpossibleConstructor.UnifyConflict` named the clause and suggested the
   absurd pattern; `NotInScope` gave a did-you-mean that was right each time.
+  **What was awkward or missing**.  `UnsolvedMetaVariables` came back with
   source ranges only (the `metas` field is filled only from a warm lane, and
   these were cold batch checks), so each of the five unsolved-meta failures
   needed a separate look at the file to see which implicit argument Agda could
   not infer; the meta's type at the range would have named it at once.  The
   bigger gap is performance: `check_file` reports no per-module time, and a
   module that spent 3.4 s of a 5 s check in `Typing.With` (a `with` whose
   scrutinee's type mentions a term certified by evaluation) looked like any
   other green check.  The cost showed up only in a command-line
   `--profile=modules` run made for the library's slow-module rule, and
   `--profile=internal` located it; a timing field, or a profile tool, would
   have caught it while the module was being written.
+  **Command line comparison**.  For writing whole definitions and checking
   them, `check_file` was at least as fast as running `agda` on the file, and
   its structured diagnostics were quicker to act on than Agda's full messages,
   particularly the ambiguity reports.  The command line was still needed for
   everything the server does not do: the library's gates, the profiles, and
   timing.  With holes unused, the lane-based tools did not get a fair trial in
   this session.
