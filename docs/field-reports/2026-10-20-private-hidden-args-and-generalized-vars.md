<!-- File: docs/field-reports/2026-10-20-private-hidden-args-and-generalized-vars.md -->

# 2026-10-20, a private repository: two new modules through the server, hidden arguments and generalized variables

+  **Date**: 2026-10-20.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 10, type_of 2.

The session wrote two new modules in a worktree of a private Agda 2.9.0
library that depends on agda-algebras: one of about 330 lines stating a
theorem at the level of a binary relation on terms, with a list form as a
corollary and four transfer lemmas, and one of about 100 lines deciding a
single refutation by evaluation.  Both went through the server a draft at a
time, the first in eight checks and the second in two, and both were green
before the whole-library gate was run from the command line.  Every error
the server reported named the fix once read, and the session never used a
hole: the drafts were complete terms, and `check_file`'s diagnostics were
the loop.

+  **Tools used**.  `check_file` on the first module, eight times, 2.2 to 2.5
   s each with the lane warm (the first call on the file loaded it in about
   2.2 s); on the second, twice, 1.8 and 1.9 s.  `type_of` twice, to read the
   full signature of a lemma defined under a parameterized module in another
   file (2.2 s, the first load of that file) and the type of a standard
   library function in a file's scope (0.1 s, a lane switch).  No
   `check_project`: the gate ran from the shell, as the repository's own
   target, 81 modules, with the seeded interfaces, and once more from an
   empty build directory (51 s, peak 3.6 GB).
+  **What worked**.  The diagnostic codes carried the fix each time.
   `UnequalTypes` with "one takes a hidden argument, while the other takes a
   visible argument" pointed at a lambda checked against a type that
   unfolded to a hidden-argument function type; `WrongHidingInApplication`
   at the explicit hidden arguments the session then supplied; two
   `MetaCannotDependOn` errors named a metavariable whose solution mentioned
   a bound variable out of its scope, which is the signature of a
   generalized variable (`s t : LatTerm X`) clashing with an explicit
   `{X : Type χ}` binder in the same signature, and of a hidden-argument
   function type (`∀ {u v} → …`) used as an argument's type, so that Agda
   instantiated the hidden arguments with metas it could not solve;
   `UnequalTypes` on a level, `X.χ ⊔ lsuc χ` against `lsuc X.χ`, said that a
   generalized variable's level and an explicit level variable of the same
   name had been generalized apart; and `UnsolvedConstraints` printed the
   two stuck constraints `_x [ σ ] = x [ σ ]`, which identified a
   let-pattern over a dependent pair whose injectivity component had its
   hidden arguments inserted as metas, fixed by a lambda that passes them
   explicitly.  The `involved` block (expected against actual) was what
   made the hidden-argument errors readable without re-running anything.
+  **What was awkward or missing**.  Nothing was wrong, but three errors
   needed knowledge the message does not give: that a definition unfolding
   to `∀ {u v} → …` behaves differently from the same type written out
   when it is an argument's type; that explicit binders and generalized
   variables of the same name are different variables; and that a unifier
   postpones `f _x = f x` for a function `f` defined by pattern matching.  A
   hint in the diagnostic ("the metavariable was created when the hidden
   arguments of `sol` were inserted") would have saved three rounds.  The
   second module's one error, unsolved metas for the pair `e` in a lemma
   whose type does not determine it, is the known pattern of this library,
   and the fix (`{e = …}`) is in its skill.
+  **Command line comparison**.  The server was the more efficient loop
   here: ten checks at about 2 s each, against a command-line check of one
   module that costs the Nix shell's start on top of Agda's own time, and
   with diagnostics parsed into codes and an expected-versus-actual block
   rather than a wall of text.  The command line was used for the gate, for
   the per-module profile (`--profile=modules`, 128 ms and 20 ms for the two
   modules), and for a clean rebuild of the library to time it, none of
   which the server offers; for that split, server for the edit loop and
   shell for the gates, the session would not change anything.
