<!-- File: docs/field-reports/2026-10-22-fls-chain-refactor.md -->

# 2026-10-22, fls: developing the CHAIN refactor in a sibling worktree

+  **Date**: 2026-10-22.
+  **Harness**: Codex; version not recorded.
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: pull request 1346, pull request 1355.
+  **Tools called**: get_goal 2, type_of 1; counts include rejected calls.

This phase implemented the approved review changes.  It replaced the separate
CERTIFY relation with contextual premises in CHAIN, added a reusable
Computational-EB instance, and moved structural checks before closure
execution.  The complete Agda closure passed.  Fresh extraction and 23
regression cases through the public Haskell chainStep API also passed.

+  **Tools used**.  The first get_goal call omitted holeIndex and was
   rejected by argument validation.  The second supplied holeIndex 0 for a
   new module in the sibling PR worktree.  Its fallback load failed with
   AmbiguousTopLevelModuleName, listing both the session checkout and the
   sibling checkout as candidates.  A type_of query returned a type with a
   meta; it did not provide a successful load verdict for the new proof.
+  **What worked**.  The tool diagnostics made the duplicate source roots
   visible.  Switching to the pinned Agda wrapper from the PR worktree and
   using --interaction-json supplied the actual goal contexts.  These drove
   the EB completeness proof and the CHAIN completeness cases.  The final
   batch checks used the same wrapper and the correct working directory.
+  **What was awkward or missing**.  The session was launched in the main
   checkout, while the approved changes belonged in a sibling worktree.
   The fallback load saw both checkouts as source candidates.  It would help
   to report the backend and effective source roots when a query falls back
   to loading a file.  These observations do not establish which part of
   the configuration contributed the second source root.
+  **Command line comparison**.  The CLI interaction protocol supplied the
   usable development loop for these proofs because it loaded the intended
   tree and exposed its goals.  Batch checking remained the final gate.
   This report records a sibling loading failure, not a comparison of tool
   speeds.
