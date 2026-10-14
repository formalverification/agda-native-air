<!-- File: docs/field-reports/2026-10-13-private-worktree-cli-checks.md -->

# 2026-10-13, a private repository: new modules in a worktree, checked from the command line

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: exports_of 3, search_by_name 1, type_of 1.

The session wrote five new literate Agda modules and extended four existing
ones (two of them barrels) in a git worktree of a private library, about 2,000
lines, and closed with the project's full gate from source.  The agda-mcp
server had been launched from the repository's main checkout, not from the
worktree, so it refused every file of the worktree; all type checking ran
through the command line, and the server answered only questions about modules
that the worktree and the main checkout shared unchanged.

+  **Tools used**.  The first `exports_of` call named a worktree file and was
   refused in about a second.  The two later `exports_of` calls named the main
   checkout's copy of an unchanged module: the first, with `limit: 0`, loaded
   the file in 4.0 s and returned all 19 typed members; the second, on another
   file, took 2.7 s (`lane.load: "switch"`).  `type_of` on a library name
   answered in 0.13 s.  `search_by_name` with a pattern naming a standard
   library lemma about lists returned an empty list.
+  **What worked**.  The refusal was exact and actionable: a `rootMismatch`
   object naming the file's root, the registered root, the libraries file, and
   the fix ("restart the server against <worktree> (set the matching *_ROOT
   variable, or pass a --library-file ...)").  It refused rather than answering
   about the wrong tree, which is the right failure.  `exports_of` with
   `limit: 0` gave a module's whole surface with types in one call, which
   replaced reading the module.  `type_of` showed a relation unfolded to its
   definition, which settled how a bridge lemma's codomain was stated.
+  **What was awkward or missing**.  A session launched in one checkout cannot
   use the server on another without a restart, and a session cannot restart
   its own server; a worktree-per-branch workflow, which this project uses,
   therefore loses the verdict tools unless the session is launched from the
   worktree.  Reading through the main checkout's copies was safe only because
   the worktree branched from that checkout's head and the queried modules
   were unchanged; the server cannot know that.  The empty answer from
   `search_by_name` did not say what it had searched: whether the corpus
   includes the standard library, or the pattern simply matched nothing, was
   left for a grep of the library's sources to settle.
+  **Command line comparison**.  The command line was the only loop available
   for the new files, and it was efficient for this work: each module was
   written whole and checked in 3 to 26 s with `agda <file>` inside the dev
   shell, and five of the seven modules checked on their first run.  The three
   failing runs (an operator without a declared fixity parsing tighter than
   intended, an implicit-binder type escaping a pattern lambda, and an
   implicit argument not inferable through a non-injective function) were
   located and named by the command-line output; no hole-driven development
   was needed.  One command-line trap: filtering Agda's output to errors only
   also hid whether the target module was checked at all, and the interface
   file's timestamp had to confirm it.  A session launched from the worktree
   would have had `check_file` and `get_goal` for the three repairs, which
   would have saved little here.
