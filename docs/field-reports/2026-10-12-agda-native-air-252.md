<!-- File: docs/field-reports/2026-10-12-agda-native-air-252.md -->

# 2026-10-12, agda-native-air issue 252: field reports, one file per session

+  **Date**: 2026-10-12.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: formalverification/agda-native-air.
+  **Issue or pull request**: issue 252.
+  **Tools called**: none.

This session built the path this report travels by: the directory
`docs/field-reports/`, the commands `new`, `submit`, and `index` of
`scripts/python/field_report.py`, and the freeze of
`docs/mcp-field-reports.md`.  The work was Python and Markdown; no Agda was
written or checked, and the server was never called.  This is the first report
submitted through `submit`, written in the worktree that `new` made when run by
absolute path from inside a checkout of agda-algebras.

+  **Tools used**.  None.  The `agda` server was listed as failed to connect
   (`CONNECTION_CLOSED`) when the session started.  The session ran in a fresh
   worktree, and a fresh worktree has no built server (`dist-newstyle/` is
   gitignored); this repository's `CLAUDE.md` names that as the cause of this
   message.  Nothing in the work needed Agda, so the server was not built.
+  **What worked**.  Nothing to say about the server.  On the path itself,
   `submit` refused the unfilled template, naming each of its twelve `FILL`
   lines, and committed nothing.  It then refused the first draft of this
   report for one line, the one quoting `FILL` in a code span: a report about
   the template could not name its placeholder.  The check now ignores code
   spans (the same pull request), and the report went through as written here.
+  **What was awkward or missing**.  The client says only
   `CONNECTION_CLOSED`.  The launcher's standard error names the missing build,
   but a session never sees it, so a session that needed the server in a fresh
   worktree would have to know the cause from the project's instructions.
+  **Command line comparison**.  No Agda was checked by either route, so there
   is nothing to compare.
