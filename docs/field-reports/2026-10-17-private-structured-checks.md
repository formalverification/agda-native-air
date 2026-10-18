<!-- File: docs/field-reports/2026-10-17-private-structured-checks.md -->

# 2026-10-17, structured checks in a private repository

+  **Date**: 2026-10-17.
+  **Harness**: Codex CLI 0.163.0.
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 16, get_goal 1.

The session used Agda 2.9.0 through the checkout's Nix wrapper.  Structured
checks supported incremental development; command-line checks covered the
whole library and measured the cost of checking from source.

+  **Tools used**.  `check_file` usually returned in about two seconds.
   One slower call took 4.9 seconds.  `get_goal` returned the goal and
   context in 2.25 seconds.  A cached initial check correctly reported
   `checkedFromSource: false`; subsequent changed files were checked from
   source.
+  **What worked**.  Diagnostic codes distinguished scope errors, argument
   hiding errors, unequal types, and unresolved metavariables.  Source
   locations made the next edits direct.  The server resolved dependencies
   against the intended checkout.
+  **What was awkward or missing**.  Checking individual files did not
   exercise the library's barrel.  A later whole-library check exposed an
   exported-name collision, which was resolved by narrowing the exports.
   This was a gap in test coverage, not an incorrect tool verdict.
+  **Command line comparison**.  The CLI was more efficient for profiling,
   heap-capped runs, and the full-library gate.  The structured tool was
   convenient for short edit-and-check cycles and inspecting a goal.  No
   overall timing comparison between the two development loops was made.
