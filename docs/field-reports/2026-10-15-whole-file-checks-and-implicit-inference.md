<!-- File: docs/field-reports/2026-10-15-whole-file-checks-and-implicit-inference.md -->

# 2026-10-15, a private repository: five new modules checked whole-file, and forty unsolved metas read from their positions

+  **Date**: 2026-10-15.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 15.

The session wrote five new literate modules (about 1,800 lines of Agda and
prose) over agda-algebras' congruence lattice at its absorbing relation
level: order lemmas, a record of eight conditions on an assignment of four
generators, an iterated construction on it with an identity proved by
induction, natural-number arithmetic on a rank function, and a theorem by
induction on a rank bound with its case split decided on ranks.  Every proof
was written whole, never through a hole, and `check_file` was the only tool
used: write a module, check, read the diagnostics, fix, check again.  Rounds
per module: 1, 2, 5, 3, 4.  The whole-library gate ran from the command line
in the background, and the result is in the repository, not here.

+  **Tools used**.  `check_file` fifteen times on five files, 0.3 to 5.4 s
   each (0.3 s for a 160-line module with no library imports, 1.2 to 2.5 s
   for the others with the library's interfaces warm, 5.4 s once for the
   largest dependency chain).  `project.root` named the worktree the session
   was launched in, with `rootSource` `nearest-agda-lib`, on every call, and
   `checkedFromSource` was true on every call.  No other tool was called:
   the proofs' shapes were known in advance, so `get_goal` and `fill_hole`
   had no work, and the two facts the session needed from the library
   (a lemma's exact signature, a module's exports) it read from the source
   files with `grep` faster than a `search_by_name` round trip.
+  **What worked**.  Of the nine failed rounds, seven were decided by the
   diagnostic alone.  `NotInScope` carried its three `candidates`, which
   named the missing import.  `AmbiguousName` listed both candidates with
   where each was brought into scope (a reasoning module's constructor
   against a record field of the same name), which named the `hiding`.
   `ConstructorDoesNotFitInData` printed the inferred sort against the
   declared one, which gave the record's level.  `MetaCannotDependOn` named
   the variable and the expression, an identity lambda over an
   implicit-function type.  `UnsolvedConstraints` printed the level
   equations, `𝓞 ⊔ 𝓥 ⊔ α ⊔ ρ ⊔ ?ℓ₀ = 𝓞 ⊔ 𝓥 ⊔ α ⊔ ρ ⊔ ℓ₀`, which is unsolvable
   by design and told the session to pass the level by name.  `success` and
   `exitCode` were reliable, and the gate agreed with every green run.
+  **What was awkward or missing**.  Two rounds were the same failure in
   forty places: the library's `≑-refl`, `≑-sym`, `≑-trans` and
   `∧-lowerˡ` take their congruences implicitly, and Agda cannot recover
   them through the defined relations `⊆` and `≑`.  The diagnostic was one
   `UnsolvedMetaVariables` whose `range` spanned lines 205 to 706 and whose
   `metaTypes` were forty file positions with no types: the lane did not
   hold the file (it had never loaded green), so the per-meta `type` the
   schema promises from a warm lane was absent.  The session printed the
   forty lines and saw that each was one of those four names.  One entry per
   meta with the name of the lemma whose implicit it is, even cold, would
   have made that one reading instead of a shell loop; and a `range` across
   five hundred lines is not an anchor, so the first position should be the
   diagnostic's `line`, with the rest listed.  The fix, writing every chain
   with the standard library's setoid reasoning over the library's lattice
   bundle so that every intermediate term is named, was then mechanical, and
   a note on that pattern would save the next session the two rounds.
   Nothing else was missing.
+  **Command line comparison**.  The server was the better inner loop: a
   check costs about what `agda` on the file costs, and the structured
   diagnostic (code, candidates, the sort mismatch, the level equations)
   replaced reading Agda's prose every time but the forty-meta one, where
   neither instrument showed the lemma names and the source had to be read.
   The whole-library gate, the clean rebuild with its wall time and the
   per-module profile ran from the command line in the background, since
   `check_project` blocks and the gate writes interfaces; the session never
   ran a server check while the gate was running.
