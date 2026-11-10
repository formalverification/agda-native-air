<!-- File: docs/field-reports/2026-11-09-private-capped-memory-probes.md -->

# 2026-11-09, a private repository: memory probes under a heap cap, and a hand-off to a second library

+  **Date**: 2026-11-09.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: none.

The session answered a review, rebased a pull request over a merged sibling,
and measured where one large emitted module's memory goes, to decide a change
to a decision procedure that a public library provides.  Its Agda work was
three checks of scratch copies of that module, two runs of the project's
heavy lane, and two whole-library gates (the branch and its base, each from no
interfaces of the library), all from the shell.  It called no agda-mcp tool.

+  **Tools used**.  None.  Each measurement needed a heap cap and the
   runtime's statistics (`+RTS -M14G -A128M -s`, or the gate's `-M6G`):
   maximum residency, total memory in use, and time, compared across three
   arms of one module (3.67 GB, 1.01 GB and 1.01 GB maximum residency; 53 s,
   20 s and 22 s).  `check_file` runs Agda without a cap and reports neither
   figure, and it writes interfaces, which would have let the capped gate
   skip the module afterward (the trap this session's first report records).
+  **What worked**.  Each arm was a scratch copy of the module made by a
   script of exact-once replacements, checked alone and cold, then deleted
   with its interface.  The probes waited for the whole-library gate (11 min
   34 s, 2.89 GB maximum residency) to finish, since two Agda processes
   building the same interfaces at once would race.
+  **What was awkward or missing**.  A verdict that carried the run's
   maximum residency, or a call that accepted RTS options and returned the
   `-s` summary, would have made these probes server calls.  The follow-up
   work belongs to a second library, and the server is registered per
   checkout; as documented, it refuses another checkout's files with
   `rootMismatch` (not tried this time).  So the session wrote a brief for a
   fresh session to be started in that library's worktree, rather than
   developing there itself.
+  **Command line comparison**.  For this work the command line was the
   only instrument, not merely the faster one: the server has no capped mode
   and reports no memory.  The per-checkout binding cost a hand-off: a
   brief instead of a pull request in the same session.
