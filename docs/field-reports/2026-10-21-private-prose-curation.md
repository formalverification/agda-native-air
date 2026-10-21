<!-- File: docs/field-reports/2026-10-21-private-prose-curation.md -->

# 2026-10-21, a private repository: prose curation of a library's modules, with one small move of definitions

+  **Date**: 2026-10-21.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 1.

The session prepared a subset of a library's literate Agda modules for
publication: it rewrote prose lines in twenty modules, dropped four public
imports from a barrel module, and moved two definitions (a term and one decided
inequality about it) out of a module that takes about twelve seconds to check
into a new module that imports it.  No proof was written or changed.  The
library's whole-library gate (80 modules) passed before and after, and so did
the published subset checked on its own from fresh clones.

+  **Tools used**.  One `check_file` on the new module: success, exit 0,
   `checkedFromSource` true, 11.8 s, which covered the re-check of the edited
   twelve-second dependency in the same run.  Everything else ran through the
   project's `make check` on the command line (45.8 s for the 80 modules from
   an empty build directory).
+  **What worked**.  The single call answered the one question the session had
   about the new module (does it check, with no hole open, against the edited
   dependency) with a verdict and no output to read through, and its
   `project.root` confirmed that the server was resolving against the worktree
   the session was editing.
+  **What was awkward or missing**.  The project marks a module whose own check
   takes 3 s or more as heavy, so the new module's own cost had to be known.
   `check_file`'s `elapsedMs` includes the re-check of a stale dependency and
   the server's start, and the answer has no per-module time, so the session
   measured it on the command line instead: three runs of `agda` on the file
   after deleting only its interface file, 2.18 s to 2.33 s.  A per-module
   time (or a `--profile=modules` option) in `check_file`'s answer would have
   saved those runs.
+  **Command line comparison**.  For this work the command line was the more
   efficient loop.  Nearly every change was prose, and its only check was the
   whole-library gate, which the session ran through `make` anyway; the server
   was the right tool for the one new module, and saved no measurable time
   there.
