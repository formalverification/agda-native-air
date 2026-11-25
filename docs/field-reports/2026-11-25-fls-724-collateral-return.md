<!-- File: docs/field-reports/2026-11-25-fls-724-collateral-return.md -->

# 2026-11-25, Conway collateral return accounting in a stacked worktree

+  **Date**: 2026-11-25.
+  **Harness**: Codex CLI 0.172.0.
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: issue 724.
+  **Tools called**: type_of 1.

The session prepared the Conway collateral return accounting helpers and
their coin preservation lemmas in a worktree stacked on the optional total
collateral change.  The edited modules and scratch cases passed with the
project's pinned Agda environment.

+  **Tools used**.  A verbose `type_of` call asked for the type of
   `cbalance` in the existing UTxO module.  The server reported 215 ms
   overall and 39 ms for its attempted load.
+  **What worked**.  The server found the intended worktree and started an
   Agda 2.8.0 interaction process.  The verbose result identified the
   registry used for the load.
+  **What was awkward or missing**.  The load returned `LibraryError`.
   The registry was the server's own library list, which lacked the
   ledger's classes, meta, set theory, and prelude dependencies.  The
   preceding stacked session had reported the same failure.
+  **Command line comparison**.  The pinned Nix shell used the worktree's
   libraries and accepted the seeded interfaces from the identical base.
   That made the CLI the working development loop.  The successful proof
   check took 25 seconds and the successful scratch module took 14 seconds.
