<!-- File: docs/field-reports/2026-10-16-private-generated-modules-whole-file-checks.md -->

# 2026-10-16, a private repository: fourteen new modules, several of them partly generated, checked whole

+  **Date**: 2026-10-16.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 25, search_by_name 1.

The session added fourteen literate modules to a library: one module of
general lemmas and thirteen small example modules, each a handful of
decided facts and short proofs, four of them carrying text that a script
printed (operation tables of finite structures as nested vectors, and up to
45 generated lemmas per proof, one proof rule each).  The work was written a
whole module at a time and checked with `check_file`; no holes were used.
All fourteen check, and the library's own gate (`make check`, 60 modules from
an empty build, 38 s) passes.

+  **Tools used**.  `check_file` 25 times, about 2.2 to 3.2 s per call for
   a module whose own check is under a second (the rest is loading its
   dependencies' interfaces), 5.2 s for the largest generated module (about
   600 lines, own check about 3 s), and once 10 s while dependencies were
   rebuilt.  `search_by_name` once, for a standard-library operator.
+  **What worked**.  Every failing check named the fix through its
   diagnostic code and the `involved` field.  `UnsolvedConstraints` listed
   metas blocked on two argument tuples of a generic constructor, which said
   exactly that the tuples had to be given; `UnequalTerms` showed two copies
   of a generalized type variable (`c.X` against `X`), which said that a
   module parameter shadowed it; `ModuleDoesntExport` with `NotInScope` named
   the operator and the module it is not in.  The generated modules, the
   largest about 600 lines, checked on their first call, so the loop for
   generated code was: print, write, one `check_file`.
+  **What was awkward or missing**.  `search_by_name` found nothing for a
   standard-library operator: its corpus covers the project's dependency, not
   the standard library, and the empty answer gave no hint of that, so the
   module that exports the operator was found with grep over the Nix store.
   `check_file` reports one elapsed time, so a module near the project's 3 s
   cost mark had to be measured with the command line's `--profile=modules`
   and `--profile=definitions`, twice each, to separate its own cost from
   loading.  And the server's library registry is a file that the project's
   dev shell rewrites on entry: entering the shell once without the
   environment variable that points at the prebuilt dependency left the
   registry pointing at an unbuilt copy, which the next check would have
   rebuilt for minutes, and nothing in the tool's answers would have said
   why.
+  **Command line comparison**.  For whole-module checks of new or
   generated code the two loops cost the same, and `check_file` was the
   better one for its structured diagnostics.  The command line was
   necessary for profiling, which the server does not expose, and ran the
   project's gate as `make check`, which `check_project` would also have
   run.
