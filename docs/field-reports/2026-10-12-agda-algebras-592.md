<!-- File: docs/field-reports/2026-10-12-agda-algebras-592.md -->
<!--
  Recovered under issue #252.  Written on 2026-10-12 as a section of
  docs/mcp-field-reports.md in the main checkout and never committed there;
  recovered from main's working tree on 2026-10-12.  The title is the
  section's heading in this directory's form (the date, then the repository
  and the work, with "#N" written "issue N"), and the header was added from
  the section's own text, "not recorded" marking what it does not say.  The
  body is the section's, unchanged.
-->

# 2026-10-12, agda-algebras issue 592: substitutions, free generating sets, and embeddings (Claude Opus 5.5)

+  **Date**: 2026-10-12.
+  **Harness**: Claude Code (version not recorded).
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: ualib/agda-algebras.
+  **Issue or pull request**: issue 592, pull request 602.
+  **Tools called**: check_file 12, type_of 1, exports_of 1, normalize 3.

Claude Code launched from the worktree root, agda-mcp connected (Agda 2.8.0,
with its own `_build/2.8.0`; the project is on 2.9.0, and every verdict agreed
with the 2.9.0 command line).  Result: four
new library modules (substitution, closure, free generation, embeddings) and two
example modules, about 2,200 lines, in one session; the largest pieces were
Lemma 1.3 and Corollary 1.12 of Freese, Ježek, and Nation and their Lemma 9.13.

+  **Tools used**.  `check_file` 12 calls (5.8 to 8.5 s each, 25.6 s for the
   first file importing a newly merged module); `type_of` once (22.4 s, a first
   lane load, to confirm the server saw the worktree); `exports_of` once, with
   `pattern`, to read the types of three lemmas of a canonical-forms module;
   `normalize` 3 times.  No holes were opened, so `get_goal` and `fill_hole` had
   nothing to do: each module was planned on paper against the existing APIs and
   written whole.
+  **What worked**.  Six of the twelve checks failed, and every failure was
   fixed from the structured diagnostic alone, without reading Agda's prose:
   `AmbiguousName` with both candidates (`cong` from `Func`); `UnequalTerms`
   `Y.υ != υ`, which named the generalized-variable trap at once (a `Y : Type υ`
   variable and `υ` in the same signature generalize two levels);
   `WrongHidingInApplication` (generalized implicits come before a module's
   explicit argument); and three `UnsolvedConstraints` and `UnsolvedMetaVariables`
   whose ranges pointed at the argument whose implicit could not be inferred
   (`fromPairs` and `Gen`, whose algebra the carrier does not determine; the list
   of `∈-filter⁻`; a where-bound lemma passed to `mkhom`, which needed
   `λ {f} → compatible {f}`).
+  **`normalize` found a misprint in a paper**.  Normalizing `canonical a` for a
   term from Freese's notes on Dean's problem returned a canonical term of a few
   hundred lines of nested `suc`, unreadable.  A ten-line `show` function into
   `String`, written in a scratch module and normalized in its place, printed the
   form in the paper's notation in 13 s, and it differed from the form the notes
   display in two meetands.  That is the most useful single answer the server
   gave this session.
+  **What was awkward**.  `normalize` at top level did not see names the file
   brought in with `open M using (…)`: `canonical` was `NotInScope` in a file
   that opened it, and the qualified name was needed.  The first `normalize` on a
   new file cost a 53 s lane load.  The server has no way to pass RTS options or
   `--profile`, and both decided this session: the worked example passed every
   uncapped check and exhausted the 6 GB heap of the project's `make check`
   (`+RTS -M6G`), which only the command line showed, and
   `--profile=definitions` located the cost in two definitions.  A
   `ClashingDefinition` in a barrel two levels up is invisible to `check_file`
   on the new module; checking the barrel file would have caught it.
+  **Command line comparison**.  The command line (`./.agda/bin/agda`, 2 to 7 s
   per module) was used for barrel checks, for timing and profiling under the
   heap cap, and for measurement modules in a scratch library outside the
   repository (`-i <dir>`, since the wrapper's `--no-default-libraries` ignores a
   scratch `.agda-lib`).  For writing and repairing modules the server was the
   better loop: its diagnostics were structured, and none needed filtering.  For
   cost, the command line was the only loop.
