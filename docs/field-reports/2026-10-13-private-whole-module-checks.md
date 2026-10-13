<!-- File: docs/field-reports/2026-10-13-private-whole-module-checks.md -->

# 2026-10-13, a private repository: five new literate modules written whole and checked file by file

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 16.

The session wrote five new literate Agda modules (about 1,700 lines with
their prose, under `--without-K --exact-split --safe`) and edited two
existing ones.  It wrote each module, or each section of the largest one,
as complete definitions rather than holes, and checked the file with
`check_file` after each section; the project's own `make check` and a
per-module profile were the final gate, from the command line.  All five
modules checked; 5 of the 16 calls failed, and each failure was fixed in
one edit.

+  **Tools used**.  `check_file` only, 16 times, each answered in 2.3 to
   10.3 s.  Most of that is loading the dependencies' interfaces: a call on
   an unchanged file whose interface was current (`checkedFromSource`
   false) still took 4.6 s, and a call after a dependency changed took
   10.3 s, rechecking three dependencies on the way.  One call with
   `verbose: true` confirmed the binary: the dev shell's wrapper at the
   checkout root, which runs the pre-release Agda 2.9.0 against the
   checkout's own library registry.
+  **What worked**.  The diagnostics named four of the five fixes.
   `NotInScope` came back with `did you mean` and the qualified original,
   which was a missing name in an import list.  `UnequalTerms` gave the
   expected and actual terms of a rewrite whose equation ran the wrong way.
   `NoParseForApplication` listed the operators in scope with their
   fixities, which showed that a product type former was missing from the
   imports.  An `UnsolvedConstraints` failure from a parameterized module
   applied without its implicit type parameter produced a constraint dump
   of about 30 lines, but its first range pointed at the two `open` lines
   responsible, and that range was the fix.  Every verdict agreed with the
   final `make check`.
+  **What was awkward or missing**.  Two things.  First, the verbose echo
   shows every check run with an extra `-i` include path into
   agda-native-air's own main checkout (its bundled Agda sources), beside
   the project's library file.  It did no harm here, but a project module
   whose name collided with one there would resolve differently under the
   tool than under the project's build, so the extra path is worth a look.
   Second, the fixed cost of 2 to 5 s per call, spent loading interfaces,
   dominates a loop of small edits; the live interaction lane (`get_goal`,
   `type_of`) would have amortized it, but the work was written in whole
   definitions and never needed a goal.
+  **Command line comparison**.  For this work, writing whole definitions
   and checking whole files, the command line would have been about as
   fast: the same Agda, the same interface loading, one call per check.
   `check_file` was the better loop by a small margin, because its
   diagnostics arrived as structured codes and ranges that did not need
   reading out of Agda's prose, and because it needed no shell setup.  The
   final gate stayed on the command line, where the build's heap limit and
   the timing are the build's own.
