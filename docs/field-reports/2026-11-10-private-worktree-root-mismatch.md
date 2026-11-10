<!-- File: docs/field-reports/2026-11-10-private-worktree-root-mismatch.md -->

# 2026-11-10, a private repository: new modules in a worktree the server could not serve

+  **Date**: 2026-11-10.
+  **Harness**: Claude Code 2.1.322.
+  **Model**: Claude Fable 5.2 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 1.

The session wrote five literate Agda modules (about 1,500 lines with their
prose) in a private library that depends on a public one, on a branch
worktree that the session created itself, and brought the library's gate to
green at 18 modules.  It called agda-mcp once.  The session had been launched
from the repository's main checkout, where the server is registered; its
first call, `check_file` on a file of the new worktree, was refused with a
`rootMismatch`, and every Agda step after that went through the command line.

+  **Tools used**.  One `ToolSearch` call loaded the thirteen tool schemas.
   `check_file`, once, on an existing file of the worktree: refused at once,
   with no check started, as an `isError` whose JSON carried `rootMismatch
   {filePath, fileRoot, librariesFile, libraryName, registeredRoot}` and whose
   prose named both roots, the reason ("would resolve this file's imports
   against" the registered root "and report success about a tree you did not
   ask about"), and the fix (restart the server against the file's root).
+  **What worked**.  The refusal.  It cost one call and no cold check, it said
   which registry it had read and where that registry puts the library, and it
   could not be mistaken for a verdict.  The alternative would have been
   worse in both cases the session was about to meet: for an existing file, a
   green answer about the main checkout's copy; for a new file, a missing
   module that reads like the session's own mistake.  In this session the two
   checkouts also pinned different revisions of the dependency, so an answer
   from the registered root would have been about the wrong library as well.
+  **What was awkward or missing**.  A running session cannot act on the fix
   the message names.  The server's root is fixed when the harness starts it,
   the harness started it where the session was launched, and the worktree
   did not exist until the session made it.  So a session whose first step is
   "create the branch's worktree" gets no agda-mcp at all, although the
   worktree was fully prepared (the dev shell had written its registry and
   its wrapper).  The knowledge tools went with the verdict tools: `type_of`
   and `definition_of` in the scope of the main checkout's copy of a file
   would have answered about the dependency at the other pin, so the session
   did not ask.  Two things would have served.  First, a way to point a
   running server at a sibling checkout of the same library that has its own
   registry: per call, or by a second registration keyed by root.  Second,
   short of that, one more fact in the refusal: whether the file's own root
   has a registry and a wrapper ready (`<fileRoot>/.agda/libraries` exists),
   which tells the reader that the remedy is a relaunch from that root and
   not a missing dev-shell step.
+  **Command line comparison**.  The command line was the only loop, and for
   this work it was adequate.  Each module was written whole, from a plan
   made by reading the dependency's sources, and checked by the worktree's
   own wrapper under the library's heap flags: 1.6 to 2.0 s a module with
   warm interfaces, about a dozen single-module runs and six runs of the
   whole gate (16 s from source).  Two runs failed, with a `ParseError` (a
   code fence left open by a scripted edit of a literate file) and a
   `NotInScope` (a private name inside an anonymous parameterized module,
   used after it);
   each was fixed from the diagnostic in one edit.  No hole was opened, so
   `get_goal` and `fill_hole` had nothing to do.  What the session did by
   hand that the lane does better was name lookup: about ten searches of the
   dependency's sources for a definition's module, its exact type, and the
   order of its arguments, each of which is one `type_of` or
   `definition_of`.  That is an estimate, not a measurement: a few minutes in
   all.
