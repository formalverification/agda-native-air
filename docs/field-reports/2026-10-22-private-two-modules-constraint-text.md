<!-- File: docs/field-reports/2026-10-22-private-two-modules-constraint-text.md -->

# 2026-10-22, a private repository: two new literate modules and an example section, checked through the server

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 11.

The session wrote two new literate Agda modules (about 330 and 400 lines,
under `--without-K --exact-split --safe`), added one field to a record of an
existing module and the use of it in a well-founded loop, moved one general
list lemma from a higher module to a lower one with three importers
repointed, and added a section of about 25 lines to an example module.  It
wrote whole definitions and checked each file after a round of edits; no
hole was opened.  Every file checked within five rounds, and the project's
`make check` from source (94 modules, 1 min 6 s) and a per-module profile
were the final gate, from the command line.

+  **Tools used**.  `check_file` 9 times, each answered in 2.6 to 6.1 s,
   with no timeout: the existing module with its new field (5.0 s, green
   first time), the first new module (3.5 s, green first time), the second
   new module (five rounds, 2.6 to 3.6 s), one of the repointed importers
   (6.1 s, green), and the example module (3.3 s, green first time).
   The server ran the checkout's own wrapper, Agda 2.9.0 (a pre-release)
   with standard-library 2.3, the same binary the command line runs.
+  **What worked**.  Four diagnostics named their fix.  First,
   `UnequalTerms` on a swapped transitivity printed both terms (`u` against
   `t`) and the expression under check, which was enough to see the two
   arguments had traded places.  Second, `UnequalTerms` with `X` against
   `X₁`, "at type (Type X.χ)", showed that a helper in a `where` block had
   named a generalized variable of its parent's signature, which a `where`
   block cannot see; the helper moved to the top level.  Third, and most
   useful, `UnsolvedConstraints` printed the blocked constraints
   themselves, of the shape `⌊ _x ⌋ᴶ = ⌊ h ⌋ᴶ (blocked on _x)` beside a
   `find … (map⁻ c∈) .proj₁` term: the unifier had reduced `map f (h ∷ t)`
   to a cons before meeting `map f ?xs`, so the list behind a membership
   could not be recovered, and passing it as a named implicit
   (`{xs = h ∷ t}`) fixed five sites at once.  Fourth, the same answer's
   remaining constraint, `(other … | d) .proj₁ = _779 (… section = (filter
   P? us))`, showed a metavariable applied to a non-variable argument from
   a `subst` over a section `(_ ∈_)` whose element was a projection of a
   `with`-defined value; naming the element in the section settled it, and
   the sibling constraint `⌊ _h ⌋ᴶ = ⌊ h ⌋ᴶ` pointed at a fold whose
   children had to be given explicitly because the fold on a cons list
   reduces before unification.  All of this came from reading the
   constraint text; no goal or candidate trial was needed.
+  **A later round: a probe and its control**.  After a review, the
   session moved a lemma's home and re-exported it from the old one, and
   used `check_file` twice on scratch modules to test the move: one
   importing the lemma through three paths at once (green in 14.6 s,
   which rechecked the edited module from source: the re-export makes no
   ambiguous name), and a control importing it from a copy of the old
   module without the re-export (red in 5.6 s).  The control's answer
   put the root cause first even though its severity was only
   `warning`: `ModuleDoesntExport`, naming the missing name as its
   candidate, then the `NotInScope` error it caused.  A probe that
   needs no edit to a tracked file, checked in seconds, is the cheapest
   way to settle a compatibility question about imports.
+  **What was awkward or missing**.  Two things.  The `UnsolvedMetaVariables`
   diagnostic lists positions only, and the metas' types come only from a
   warm lane; after a whole-file `check_file` the lane holds nothing, so
   the types were not there, and the session matched positions against
   the file by hand (a `sed -n` with line numbers).  A `check_file` option
   to load the file into the lane after a failed check, or a note that
   `get_goal` on a fresh hole would warm it, would save that step.  And the
   constraint text was cut ("17 more lines") in the first failing answer;
   the lines shown were the decisive ones, but a way to ask for the whole
   constraint set, as `maxDiagnostics: 0` does for diagnostics, would be
   worth having.
+  **Command line comparison**.  The server was the more efficient loop for
   the three modules: each check cost the same Agda run the command line
   would make, without entering the dev shell, and the diagnostics arrived
   parsed, with the constraint text that decided each fix.  The from-source
   gate, the timing and the per-module profile stayed on the command line,
   since they clean the build directory; the server was kept away from the
   build directory while they ran.
