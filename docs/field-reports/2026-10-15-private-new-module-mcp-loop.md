<!-- File: docs/field-reports/2026-10-15-private-new-module-mcp-loop.md -->

# 2026-10-15, a private repository: one new literate module and a corollary, checked and probed through the server

+  **Date**: 2026-10-15.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 7, get_goal 1, fill_hole 2, type_of 4,
   exports_of 1.

The session wrote one new literate Agda module of about 300 lines (a
record, two maps between it and an existing record, and two round-trip
lemmas, under `--without-K --exact-split --safe`) and a one-line corollary
at the end of an existing module.  It wrote whole definitions, checked the
file after each round of edits, and opened a hole only where an error
message did not name the fix.  Both files checked after six rounds; the
project's `make check` (45 modules) and a pinned per-module profile were
the final gate, from the command line.

+  **Tools used**.  `check_file` 7 times, each answered in 2.7 to 3.7 s.
   `get_goal` once (2.7 s, the lane's first load of the file), `fill_hole`
   twice (3.1 s for the candidate that passed, 42 ms for one that did not
   parse, which was refused before any check ran), `type_of` 4 times (7 ms
   on the warm lane, 3.1 s after a forced reload), and `exports_of` once
   (4 ms).
+  **What worked**.  Five things.  First, the session was launched from the
   worktree root before the dev shell had written the checkout's Agda
   wrapper and library registry there; entering the shell once from the
   command line was enough, and the first `check_file` afterwards resolved
   the project root (`nearest-agda-lib`) and checked with no restart of the
   server.  Second, `NoParseForApplication` listed the two operators of the
   expression with their shared precedence, which named the fix
   (parentheses around both sides).  Third, `UnequalTypes` printed two
   level variables with different names (`I.ι` against `ι`), which showed
   that a generalized variable's level and a level written in the signature
   had been generalized separately; explicit binders fixed it.  Fourth, a
   `check_file` on a file with one open hole also reported an unrelated
   `UnequalTerms` 200 lines further on, with both terms, so two fixes went
   into one round trip.  Fifth, `type_of` with `rewrite: Normalised` on a
   record field printed its type with every definition unfolded (7 ms on
   the warm lane), which confirmed that the field says what the module's
   prose claims and nothing more; that is a reviewer's use of the tool,
   beside the author's.
+  **What was awkward or missing**.  One error message pointed away from
   its cause.  A two-lambda proof of an equivalence between two negated
   propositions failed with `NotLeqSort` ("Type A.ι is not less or equal
   than Type (ℓ₁ ⊔ ℓ₂)"), and the fix turned out to be eta-expanding the
   implicit binders of bound variables whose types begin with one, which
   points at implicit-argument insertion rather than at any sort.  The
   message named a sort, not an argument, so the session replaced the body
   with a hole, read the goal with `get_goal`, and tried a candidate with
   the implicit binders eta-expanded, which passed at once.  A note in the
   diagnostic when a sort comparison arises inside an inserted implicit
   application would have saved those two calls.  Separately, the
   normalized type of a record field ran to about 40 lines of fully
   qualified names: readable, but a `rewrite` that unfolds definitions and
   keeps names short would suit this use better.
+  **Command line comparison**.  The server was the more efficient loop
   for the development.  Each check cost the same Agda run the command line
   would make, without the 3 to 4 s of entering the dev shell, and the
   goal, the candidate trial and the normalized types came back in
   milliseconds to 3 s each, where the command line would have meant an
   edit and a recheck for each.  The final gate and the cost measurements
   stayed on the command line, because they clean the build directory and
   time whole checks; the server was kept away from the build directory
   while those ran.
