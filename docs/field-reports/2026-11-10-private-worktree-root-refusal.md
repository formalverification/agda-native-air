<!-- File: docs/field-reports/2026-11-10-private-worktree-root-refusal.md -->

# 2026-11-10, a private repository: three new modules in a worktree, checked from the command line

+  **Date**: 2026-11-10.
+  **Harness**: Claude Code 2.1.322.
+  **Model**: Claude Fable 5.2 (Anthropic), then Claude Opus 5.5 (Anthropic)
   for the end of the session.
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 1.

The session wrote three new literate Agda modules, about 1,200 lines in all,
and edited the prose of a fourth, in a git worktree of a private repository
that the session created in its first minutes, stacked on an unmerged branch.
All four check under `--safe`, each in under a second of its own, and the
library's full check passes.  The server was not used for any of it: its one
call was refused, correctly, because the server had been started from the
repository's main checkout and the files lived in the worktree.  Every check
went through the command line instead.

+  **Tools used**.  One `check_file` on the first new module, refused at once
   (no Agda run) with a `rootMismatch` that named the file's root (the
   worktree), the registry the server was using (the main checkout's
   libraries file), the root that registry gives the library (the main
   checkout), and the fix: restart the server against the worktree, or pass a
   libraries file whose entry for the library points there.
+  **What worked**.  The refusal.  The worktree's branch held modules that the
   main checkout does not have (the unmerged base's), so a check resolved
   against the main checkout could only have failed on a missing import or
   answered about other sources; the server said so instead of doing either,
   and the message was enough to decide what to do without reading any
   documentation.
+  **What was awkward or missing**.  The server is bound at launch to the
   checkout the session starts in, and the usual flow of a kickoff in this
   repository creates the worktree after launch, so the server cannot serve
   the session's own files unless the session is relaunched from the worktree
   root.  The kickoff asked for that relaunch, and this session did not do it,
   having started from the main checkout.  A way to re-root the running server
   (a call that takes a libraries file, or a root per call) would have let the
   session keep the server; so would a line in the refusal saying that the
   restart means relaunching the session.  The refusal's "set the matching
   `*_ROOT` variable" names no variable, so it is not actionable as written.
+  **Command line comparison**.  No comparison was possible, since the server
   could not serve these files.  The command-line loop was adequate for this
   work: the dev shell's wrapper checked a single module in 2.4 to 2.8 s with
   its dependencies built, about a dozen times, and `--profile=modules` from a
   fresh interface gave each new module's own cost (0.17 s to 0.55 s).  The
   errors met were two `UnsolvedMetaVariables`, each from a function with
   implicit arguments passed where a field expected them eta-expanded, and one
   `CoverageNoExactSplit` warning; the command line printed the unsolved
   constraints in full, which located each at once.  With the server,
   `get_diagnostics` would have given the same codes and the metas' types; for
   checks of this size the server's warm lane would have saved little.
