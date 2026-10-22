<!-- File: docs/field-reports/2026-10-22-private-eight-module-session.md -->

# 2026-10-22, a private repository: eight new modules in one session, by whole-file checks

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic); the review round of the addendum, Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 45, type_of 1.

The session wrote eight new literate Agda modules from scratch, about 2,900
lines of Agda and prose together, on a worktree whose agda-mcp server had been
registered through the repository's `.mcp.json` after one `nix develop` in that
worktree.  Each module was designed on paper first, written whole, checked
with `check_file`, corrected from the diagnostics, and rechecked, between two
and nine times a module; every module was green by the end of the session, and
the eight were committed, with the repository's full `make check` run on the
command line in the background.  No hole was ever opened: `fill_hole` and
`get_goal` were not called, because the proofs were known before they were
typed and the whole-file check was the loop.

+  **Tools used**.  `check_file` 38 times, 2.0 to 3.0 s each on a warm tree
   (the server runs a cold `agda` per call, with the library's interfaces
   already built), the longest 2.99 s.  `type_of` once, to learn the argument
   order of a standard-library lemma whose name reads either way; since the
   file did not load at that moment, the answer was the file's first error
   rather than the type, which happened to be the mismatch the lemma caused,
   so the question was answered anyway.  `check_project` was not used; the
   project's gate ran on the command line because a timed, cold run was
   wanted for the costs.
+  **What worked**.  The diagnostics named the fix each time, and the
   `involved` fields carried the detail that mattered: `AmbiguousName` with
   both candidates and their provenance, for the recurring clash between a
   setoid's `sym`, `trans`, `refl` and the propositional ones, and once for a
   record field named like a universe-level variable; `ModuleArityMismatch`
   with the telescope, for applying a record module to its parameters again;
   `TerminationIssue` with the problematic calls, including the with-function
   calls, which pointed at the `with` blocks to replace by a sum eliminator;
   `UnsolvedConstraints` with the blocked metavariables and what blocked them
   (`blocked on _bs`), which pointed at a list behind a `foldr` or a `filter`
   that Agda cannot invert, fixed by passing the list explicitly or by
   turning the relation into an inductive family; `WrongHidingInLHS`,
   `UnequalTypes` and `UnequalTerms` with expected and actual terms;
   `NotInScope` with a did-you-mean that named the right module for a lemma
   imported from the wrong one; `ModuleDoesntExport` as a warning before the
   error it caused; and `CannotEliminateWithPattern`, accurate for a
   constructor name that was not imported and so had become a variable
   pattern, the one message whose cause needed thought.  Diagnostics come
   root cause first, so one fix per round was usually the whole round.  The
   root detection worked in the worktree from the first call.
+  **What was awkward or missing**.  `UnsolvedMetaVariables` lists positions
   only, as line and column ranges, with no type for each meta; the paired
   `UnsolvedConstraints` entry was what located the problem, and a check
   whose only error is unsolved metas with no constraints would say little.
   Long messages are cut ("… (42 more lines)") and the cut sometimes fell
   before the last constraint.  The warm-lane `holes` goal peek never
   applied, since no file had holes.  A `type_of` on a file that does not
   load answers with the load error; a note in the answer saying that the
   expression was never typed would make that unmistakable.  Nothing was
   missing that the work needed.
+  **Command line comparison**.  The server was the more efficient loop for
   this work: the same 38 checks on the command line would have cost the same
   agda time, but the structured diagnostics, with codes to branch on and the
   expected and actual terms set apart, saved the reading of agda's text
   each round, and the per-call root and verdict fields removed any doubt
   about which tree and which file were checked.  The one thing done on the
   command line, the whole-library check with `time`, was done there because
   the measurement was wanted, not because the server could not have run it.

## Addendum, the same day: a review round

After a review of the pull request, the session, which the harness had
meanwhile switched to Claude Opus 5.5, made seven more `check_file` calls on a
warm tree, 2.2 to 3.1 s each.  The first reproduced a reviewer's claim in a
scratch module: it failed with `UnequalTerms`, and the expected and actual
terms in `involved` differed in one universe level, which was the claim
exactly, while a control declaration earlier in the same file checked.  The
second ran the same module after the fix, green.  Five more checked the
changed files, green, three of them for prose edits only, as a guard against
a broken code fence.  The expected and actual pair made the reproduction one
call, with nothing to read in Agda's prose but the two terms.  The full gate
ran on the command line again, timed, after a merge of the main branch.
