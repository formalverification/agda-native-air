<!-- File: docs/field-reports/2026-11-25-fls-pov-stack-refresh.md -->

# 2026-11-25, reviewing the fls preservation-of-value stack

+  **Date**: 2026-11-25.
+  **Harness**: Codex, version not recorded.
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: pull request 1189.
+  **Tools called**: `type_of` twice.

A re-review of a published Agda proof branch checked two concerns about
whether constructor patterns supplied every argument.  Each constructor
takes a nested product, and the final wildcard matches the remaining
product.  The session checked the published branch through agda-mcp and
used a separate pinned toolchain for the trial merges.

+  **Tools used**.  `type_of` checked the published module and returned the
   first declaration's type in 177.8 seconds, including 169.4 seconds for
   the first lane load.  The other declaration's type came back in 111 ms
   from the same lane.
+  **What worked**.  The first load checked the file from source without
   requiring any edits.  The second query reused that load.
+  **What was awkward or missing**.  The first load took nearly three minutes.
   This session reviewed both the published source and trial trees on an
   updated dependency pin, so it kept the lane on the published checkout.
+  **Command line comparison**.  The lane was faster for a second type
   query on the same file.  For checking the trial merges, the CLI let the
   session use each scratch tree's pinned wrapper and seed its interface
   cache from the corresponding Nix build.
