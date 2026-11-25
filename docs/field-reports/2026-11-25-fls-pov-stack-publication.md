<!-- File: docs/field-reports/2026-11-25-fls-pov-stack-publication.md -->

# 2026-11-25, checking a proof refactor across fls worktrees

+  **Date**: 2026-11-25.
+  **Harness**: Codex, version not recorded.
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: pull request 1210.
+  **Tools called**: `type_of` once.

A proof refactor in a sibling worktree shared an argument used by three
proof sites.  The author session had started from a different worktree of
the same project.

+  **Tools used**.  A `type_of` query asked for the type of an existing
   lemma in the sibling worktree.  It returned in 1.4 seconds.
+  **What worked**.  The response identified the intended fls worktree as
   the project root and reported the Agda error code and the registry in
   use.
+  **What was awkward or missing**.  The lane failed to load the file with
   `LibraryError`.  The registry named in the diagnostic belonged to a
   different project and did not contain the required fls libraries.
+  **Command line comparison**.  The session used the pinned flake wrapper
   from the sibling checkout for the focused module check, then checked
   the whole ledger closure and its consumer wiring.  Those checks passed.
   The CLI was the usable loop for this worktree in this run.
