<!-- File: docs/field-reports/2026-11-01-private-worktree-checks.md -->

# 2026-11-01, a private repository: a server bound to the main checkout, and a new module in a worktree checked from the command line

+  **Date**: 2026-11-01.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Fable 5.1 (Anthropic), then Claude Opus 5.5
   (Anthropic) after a switch partway through; the one call below was made
   under Claude Fable 5.1.
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 1.

The session worked on a branch in a git worktree of a private Agda library,
the repository's practice being one worktree per branch beside the main
checkout.  It wrote one new module of about fifteen short lemmas (`--safe`,
no postulates), listed it in the library's barrel module, edited a few lines
of its prose later, and gated the whole library with the repository's own
`make check`.  The harness had been launched from the main checkout, and the
worktree was created as the session's first step, so the agda-mcp server it
had was the one registered for the main checkout.

+  **Tools used**.  One `check_file`, on an existing module in the
   worktree, as a first probe of the server before writing the new one.  It
   was refused at once, with a `rootMismatch` record and a message naming
   the file's nearest `.agda-lib`, the root that file declares, the
   different root the server's libraries file registers for the same
   library name, and why checking anyway would mislead: the file's imports
   would resolve against the other checkout, and a success would describe a
   tree the caller did not ask about.  No further calls were made.
+  **What worked**.  The refusal is the right behavior, and it cost nothing:
   no verdict came back about the wrong copy of the library, and the
   structured record (file, file root, libraries file, library name,
   registered root) said exactly what was wrong without reading the prose.
   The message also names a fix, restarting the server against the
   worktree, either through the matching root variable or through a
   libraries file whose entry points there.
+  **What was awkward or missing**.  The fix the message names is not one a
   session can carry out: the server is started by the harness from the
   project's MCP configuration when the session starts, and nothing in the
   session can restart it against another root.  The project's own
   guidance, launching the harness from the worktree's root after entering
   its dev shell once, has to be followed before the session begins, and a
   session that creates its worktree as its first step cannot follow it.
   A per-call root (or a tool that re-registers the server against a second
   checkout of the same library, given that checkout's own libraries file,
   which the dev shell writes at every checkout root) would have let this
   session use the server on its branch.  Short of that, the message could
   say that a restart means a new session launched from the worktree, so
   that the caller does not look for a way to restart from inside.
+  **Command line comparison**.  The command line was the only loop
   available, and for this work it was enough: inside the worktree's dev
   shell, a single-file check of the new module took about 3 seconds once
   the dependencies' interface files existed, and `make check` gated the
   library.  The module was small and its lemmas short, so goal-by-goal
   interaction would have saved little; the cost of the mismatch here was
   the one refused call, not lost work.  A longer development in a
   worktree, where `get_goal` and `fill_hole` earn their keep, would lose
   the server entirely unless the session is launched from that worktree.
