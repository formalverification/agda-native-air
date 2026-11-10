<!-- File: docs/field-reports/2026-11-10-private-worktree-refusal.md -->

# 2026-11-10, a private repository: a session whose files lived in a worktree the server was not started for

+  **Date**: 2026-11-10.
+  **Harness**: Claude Code 2.1.322.
+  **Model**: Claude Opus 5.5, then Claude Fable 5.2 (Anthropic).
+  **Effort**: not set.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 1, type_of 1, search_by_name 1.

The session added a second library dependency to a library's Nix dev shell,
then wrote five literate Agda modules (about 1,300 lines, several with
decisions over a small finite carrier evaluated at check time) and edited
four more.  Every module checks, and the project's gate passes from source.
None of that went through agda-mcp: the server refused the session's files,
correctly, and the whole loop ran on the command line.

+  **Tools used**.  `check_file` once and `type_of` once, both on a file of
   the session's own worktree, both refused at once (below).
   `search_by_name` once against the corpus, with no file, which answered.
+  **What worked**.  The refusal.  The session was launched from the
   library's main checkout, so the server was started for that checkout's
   registry; the session then created a git worktree for its branch and
   wrote every file there.  Asked to check a file of the worktree, the
   server answered with a `rootMismatch`: the file's nearest `.agda-lib`
   declares the library at one root, the registry the server holds declares
   the same library at another, and checking would "report success about a
   tree you did not ask about".  It named both roots, the registry file, and
   the fix (restart against the other root).  That was the right answer and
   not a formality here: the worktree's registry had one more library than
   the main checkout's, so a check resolved against the main checkout would
   have failed on the first import of the new dependency, or, for the
   modules that did not import it, passed for a tree with different
   dependency pins.  `type_of` refused the same way, so the knowledge lane
   and the verdict lane agree on which tree a file belongs to.
+  **What was awkward or missing**.  A session cannot apply the fix the
   refusal names.  The server is started by the harness, once, from the
   directory the session was launched in; a session that makes its own
   worktree (the ordinary case under a one-branch-per-worktree convention,
   where the worktree does not exist until the session creates it) cannot
   restart the server against it, and no tool takes a root.  The
   instructions the session was given said to launch from the worktree's
   root, which nobody could have done before the session ran.  Two things
   would have let the tools serve this session: a per-call root or registry
   (refused unless that root has its own registry and wrapper, which this
   project's dev shell writes at every checkout root), or a server that,
   when a file's nearest `.agda-lib` sits in a checkout carrying its own
   `.agda/libraries` and `.agda/bin/agda`, uses those for that file and
   says so in `project {root, rootSource}`.  The refusal already computes
   everything such a call would need.  Without either, the report for this
   kind of session will always read as this one does.
+  **Command line comparison**.  The command line was the only loop, and
   for this work it was enough.  The modules were written whole from a
   proof worked out on paper, and four of the five checked on the first
   run; the fifth failed once on a name not in scope.  One check of one
   module through the checkout's own wrapper took 0.4 to 2 s against built
   interfaces, and the whole library 16 to 19 s from source, so there was
   no closure for `check_file` to save.  What the lane would have saved is
   two scratch modules: one to learn whether a dependency's operations on a
   small finite carrier reduce on closed terms (a `normalize` call), and one
   to confirm from a client module that a statement in `Setω` applies with
   no unsolved metas (a `type_of` call).  A deliberately false decision was
   also checked from the shell, to see that `from-yes` of a swept decision
   fails when the statement is false; that control needs a file edit either
   way.
