<!-- File: docs/field-reports/2026-10-15-private-goal-candidates.md -->

# 2026-10-15, goal queries and candidate checks in a private repository

+  **Date**: 2026-10-15.
+  **Harness**: Codex; version not recorded.
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 2, get_goal 3, fill_hole 2.

The session added a module in a dedicated worktree.  The server accepted the
worktree, checked successive portions, exposed the final goal and its
context, and checked a candidate for that goal.  The completed file was
then checked through the project's command-line build and profiler.

+  **Tools used**.  The two `check_file` calls took 3473 and 3741 ms.  The
   first returned no diagnostics; the second reported `UselessPrivate`
   while accepting the file.  The successful `get_goal` call took 3381 ms,
   including 3339 ms for the interaction lane's first load.  It returned
   the expected type and seven context entries.  The two `fill_hole`
   calls took 60 and 3530 ms: the first rejected a parse error, the second
   accepted the candidate with no remaining holes.
+  **What worked**.  A goal query with no address selected the sole hole.
   The diagnostic identified a redundant visibility declaration, which
   was removed.  Candidate checking restored the source after both the
   failed and successful probes; reading the file confirmed that the
   original hole remained.  The accepted candidate was then applied as
   an ordinary file edit.
+  **What was awkward or missing**.  An initial call used `file` rather
   than `filePath`; the validation message named the required key.  A
   subsequent query on a complete file correctly explained that there
   were no holes and how to address one.  A multiline candidate's `let`
   declarations were not aligned with the insertion column and produced
   `ParseError`.  Putting the same candidate on one line with explicit
   separators passed.  The final source was formatted separately.
+  **Command line comparison**.  The CLI was not the more efficient
   development loop here: structured diagnostics and the interaction
   context were useful, and the short checks had similar startup cost.
   The CLI remained the right tool for the final whole-library check,
   per-module profiling, and peak-memory measurement.
