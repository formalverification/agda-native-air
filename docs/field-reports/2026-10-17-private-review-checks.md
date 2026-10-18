<!-- File: docs/field-reports/2026-10-17-private-review-checks.md -->

# 2026-10-17, checking a review claim in a private repository

+  **Date**: 2026-10-17.
+  **Harness**: Codex CLI 0.163.0.
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 2.

The session checked a reviewer's type-error claim with the checkout's
pinned Agda 2.9.0.  The unchanged source passed, and a command-line control
rejected the proposed replacement.

+  **Tools used**.  The first `check_file` returned exit 0 in 2.09 seconds
   with `checkedFromSource: false`.  After removing only the target's
   generated interface, the second returned exit 0 in 2.30 seconds with
   `checkedFromSource: true` and no diagnostics or holes.
+  **What worked**.  The cache flag distinguished a cached verdict from a
   fresh source check.  The reported project root matched the intended
   checkout.
+  **What was awkward or missing**.  No server defect was observed.  The
   review claim required inspecting the relevant branch's type; a passing
   cached check alone would have supplied less useful evidence.
+  **Command line comparison**.  The CLI was more efficient for checking
   three scratch copies of a complete module: the original and an explicit
   type annotation passed, while the suggested replacement failed with
   `UnequalTerms` and exit 42.  The real whole-library gate also passed.
   These controls did not change tracked source files.
