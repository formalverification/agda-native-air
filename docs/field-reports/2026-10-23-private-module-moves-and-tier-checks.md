<!-- File: docs/field-reports/2026-10-23-private-module-moves-and-tier-checks.md -->

# 2026-10-23, a private repository: moving modules between namespaces and checking subsets

+  **Date**: 2026-10-23.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: type_of 1, resolve_name 1, exports_of 1.

The session reorganized a library of about 150 literate modules: it moved two
dozen modules into a new top-level namespace (file moves plus a scripted
rewrite of module names, imports and prose links), moved three small pieces of
code between modules so that one subset of the library would close under
imports, split one module in two, and split a barrel.  No proof was written;
the Agda work was renames and relocations, verified by type-checking.  The
verification ran on the command line (`make check`, incremental and from
source), and the server was used afterwards for three spot questions about
where a relocated name now resolved.

+  **Tools used**.  `type_of` on a relocated lemma, asked in the scope of one
   of its importers: 2.3 s, almost all of it the lane's first load
   (`lane.load: first`, 2288 ms), and the type came back in the new module's
   vocabulary, which confirmed the import pointed at the new home.
   `resolve_name` on a relocated definition from a second importer: 217 ms
   (`lane.load: switch`), with a two-step provenance chain (the opening of the
   new module, then its definition site), exactly the question a rename
   raises.  `exports_of` on the new split-off module, in the scope of its one
   example importer, with `limit: 0`: 307 ms, the whole surface (12 values and
   one nested module) with types, so a missing export would have shown before
   any compile.
+  **What worked**.  All three answers were right and fast after the first
   load, and every answer named the tree it used (`rootSource:
   nearest-agda-lib`, the worktree's own root): the server, launched from the
   worktree, served the worktree's files with no root mismatch.  The
   provenance chain of `resolve_name` is better evidence for a move than a
   grep, because it follows the actual `open import`.
+  **What was awkward or missing**.  The question this work needed most was
   "does this subset of the library check on its own, with every other module
   absent?", to prove that the subset closes under imports in Agda and not
   only in a textual import scan.  No tool answers it: `check_project` runs
   the project's own gate over the whole tree, and a scratch tree holding the
   subset is a different root with its own library file.  The session built
   one by hand (an archive of the subset, a `.agda-lib`, a libraries file, an
   aggregator, and the store path of the Agda binary with
   `--no-default-libraries --library-file`), and it checked in 1 min 47 s.
   A `check_project` option naming a set of modules to check in isolation
   (copied into a temporary root that reuses the project's dependency
   interfaces) would have answered it in one call.
+  **Command line comparison**.  For this work the command line was the more
   efficient loop, and by a wide margin: the edits were bulk text rewrites,
   and the verdict that mattered was the whole library's (an incremental
   `make check` took 14 s after the moves, and the from-source check 2 min
   32 s for 149 modules).  The server earned its place as a confirmation step,
   three sub-second questions after the fact, not as the development loop.
