<!-- File: docs/field-reports/2026-10-14-hole-by-hole-structural-proofs.md -->

# 2026-10-14, a private repository: five new modules of structural proofs, checked one file at a time

+  **Date**: 2026-10-14.
+  **Harness**: Claude Code (version not recorded).
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 23, normalize 2, type_of 1.

The session wrote five new literate modules (about 1,900 lines of Agda and
prose) on top of a library of about forty modules, each a theorem built from
the library's lemmas rather than a decision by evaluation, plus edits to two
existing modules and a barrel.  It developed each module as a whole file
rather than hole by hole, and used `check_file` as the inner loop: write a
section, check, read the first diagnostic, fix, check again.  Every module
was green within one to eight rounds, the whole-library gate was run from
the command line in the background, and the work's result is recorded in the
repository, not here.

+  **Tools used**.  `check_file` 23 times on five files, 2.6 to 6.4 s each
   with the library's interfaces warm (a cold batch agda per call; the time
   is startup and loading, since no module took more than 1.2 s in the
   profile).  Rounds per module: 11 (the first and largest, in two sittings),
   2, 1, 3 and 5.  `normalize` twice: one `NotInScope` for a qualified name
   the file did not import (answered in 2.4 s, with Agda's "did you mean"),
   then, in a file that had the module in scope, the normal form of a
   library-defined list of representatives in 0.2 s: a literal 17-element
   list that the session then matched case by case in a proof, which it could
   not have written without seeing the list.  `type_of` once at the start, to
   confirm the server was bound to the worktree the session was launched in
   (it was: `project.root` named the worktree, `rootSource`
   `nearest-agda-lib`; a first load of 3 s).
+  **What worked**.  The diagnostics decided the fix in every round but one.
   `ImpossibleConstructor.UnifyConflict` said to use an absurd pattern, and
   that was the fix (a `0F < 0F` written as `s≤s ()` instead of `()`).
   `UnequalTerms` with `involved.actual` and `involved.expected` showed the
   two sides, which located a transport in the wrong direction (`sym`
   missing), an off-by-one `suc` in offset arithmetic, a `subst` motive that
   named the wrong side, and a helper that re-abstracted the pattern
   variables of its caller so that a membership proof no longer typed; each
   fix was one line.  `UnsolvedMetaVariables` with the ranges of the metas
   located three underscores that an unfolding definition kept Agda from
   solving.  `WrongHidingInApplication` said that generalized implicits come
   before the explicit argument I had put first.  The `holes` array and
   `success` were reliable: every green run was `exitCode` 0 and the
   whole-library gate agreed.
+  **What was awkward or missing**.  The `UnsolvedConstraints` diagnostic
   carried its constraints as a `metaTypes` array of about a hundred fragments
   (each line of Agda's message a separate string), which hid the one fact
   that mattered, that the blocked metas were three offsets in three
   definitions; a condensed form, one entry per unsolved meta with its
   location, would have saved a reading.  A check costs about 3 s whatever
   the file, so twenty-three checks were over a minute of waiting for a
   library whose modules check in under a second each; a warm batch, or a
   lane-backed check for a file the lane already holds, would cut that.  Agda
   stops at the first error, so `maxDiagnostics` never mattered.  Nothing was
   missing for this work; `fill_hole` and `get_goal` were not used because
   the proofs' shapes were known in advance, and a session writing a proof it
   does not yet know would want them.
+  **Command line comparison**.  For the inner loop the server was the more
   efficient instrument: `agda` on one file from the command line costs the
   same 3 s, and the structured diagnostic (code, range, the two sides of a
   mismatch, the metas' locations) replaced reading Agda's prose; the
   `normalize` answer that produced a 17-case proof would have taken a
   scratch file and an editor session otherwise.  For the whole-library gate,
   the clean rebuild and the per-module profile, the command line in the
   background was the better loop, since those run for a minute or more and
   the server's `check_project` blocks; the session kept the two apart and
   never ran a server check while a gate was writing interfaces.
