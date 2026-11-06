<!-- File: docs/field-reports/2026-11-06-agda-native-air-342-setup-by-lock.md -->

# 2026-11-06, agda-native-air: verifying registrations for two projects' own Agda

+  **Date**: 2026-11-06.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: formalverification/agda-native-air.
+  **Issue or pull request**: issue 342, pull request 344.
+  **Tools called**: check_file 14, type_of 11 (all sent over JSON-RPC by
   scripts standing in for a client; the session's own agda server never
   connected).

The session wrote a launcher that builds the Agda a project's flake exports
once per lock, a startup line for a pinned Agda that has fallen behind its
flake, and a setup guide, then verified the guide by registering
formal-ledger-specifications (through the launcher) and ualib/agda-algebras
(through the binary its dev shell writes) and driving each server as a
client would.  Both answered from their own checkouts, and a
formal-ledger-specifications worktree on an older lock got that lock's Agda.
The same probes reproduced every failure signature the guide lists.

+  **Tools used**.  `type_of` on each project's prelude module as the smoke
   test: 14.4 s for the first load on formal-ledger-specifications, and
   94 ms on agda-algebras, whose interfaces were current.  `check_file` in
   pairs, one server per worktree started the way Claude Code starts them,
   to show each answered from its own root; and on files of sibling
   worktrees and of misconfigured registrations, to record what each failure
   looks like.
+  **What worked**.  The `verbose` answer says exactly which Agda answered
   and where (`lane.agdaVersion`, `command.binary`, `project.root`), so a
   registration can be verified from one call without a harness.  The stale
   pin reproduced the field's signature to the line (`NotInScope` at
   `Axiom/Set/Map/Extra.agda:127`), and the server's `rootMismatch` refusal
   named both roots and the libraries file, as designed.
+  **What was awkward or missing**.  The session's own agda server showed
   `CONNECTION_CLOSED` from the start: the worktree was fresh, with no server
   built, the known issue the setup page lists.  When the program named as
   `--agda-bin` fails before Agda runs, `check_file` answers `success: false`,
   exit 69, and no diagnostics, with the program's one-line reason left in the
   server's log; the lane tools return it in `stderrTail`.  Any Agda failure
   the diagnostics parser does not recognize reaches a model the same way.
   And a lane tool asked about a sibling worktree on another lock loads it
   with the session's Agda and fails inside a dependency
   (`ClashingDefinition`), which reads like the stale-pin failure.
+  **Command line comparison**.  For verifying registrations the server was
   the only loop that answers the question, since the question is what the
   server does; scripted JSON-RPC calls, not a harness, were the efficient
   way to make them.
