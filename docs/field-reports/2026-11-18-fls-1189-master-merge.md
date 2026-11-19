<!-- File: docs/field-reports/2026-11-18-fls-1189-master-merge.md -->

# 2026-11-18, fls: checking a master merge into the UTxO PoV branch

+  **Date**: 2026-11-18.
+  **Harness**: Codex CLI 0.170.0, source cli, originator codex-tui.
+  **Model**: gpt-6.1-sol (OpenAI).
+  **Effort**: xhigh.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: pull request 1189.
+  **Tools called**: check_project 1, check_file 1.

The session merged current master into the published UTxO PoV branch and
checked the merged source before pushing.  The merge was clean.  Master
changed shared computational code and both ledger eras, so the acceptance
gate rechecked the full library closure.  A separate safe wiring module
checked the preservation-of-value consumer against its remaining module
parameters.  The test library was checked against the working copy through
the command line.

+  **Tools used**.  `check_project` passed in 613.378 seconds,
   rechecking 245 modules from source with no diagnostics.  `check_file` accepted the
   safe wiring module in 13.031 seconds with no diagnostics or open holes.
+  **What worked**.  The project gate used the merged worktree's pinned
   compiler and checked the complete source-library import closure.  The
   wiring module still matched the consumer's parameter block verbatim and
   was deleted after its check.
+  **What was awkward or missing**.  The long batch gate supplied its result
   and output tail only when it completed.  Its configured command covered
   the source library; the separate test library needed an explicit registry
   naming the working copy.
+  **Command line comparison**.  The command line handled the merge and the
   test-library registry.  MCP supplied the whole-project and wiring verdicts.
   The source came from a clean merge of existing proofs, so there was no
   hole-driven drafting in this task.  No timing comparison between the two
   interfaces was run.

The harness, version, model, and effort above were read from the current
session's transcript metadata.
