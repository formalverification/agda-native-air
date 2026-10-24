<!-- File: docs/field-reports/2026-10-23-private-module-move-batch-checks.md -->

# 2026-10-23, a private repository: moving modules between libraries, three batch checks

+  **Date**: 2026-10-23.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 3.

The session moved ten literate modules from one Agda library to another that
depends on it, with their git history, renamed them, re-pointed their
importers in four repositories, and wrote two short new lemmas (about forty
lines of equational reasoning).  Almost all of the work was git, Nix and prose;
Agda was needed for the new lemmas, for one module that absorbed another's
definitions, and for the whole-library gates of each repository.  Every check
passed: the server's three, and the four libraries' own gates on the command
line.

+  **Tools used**.  `check_file` three times, on the module that received the
   new lemmas (2.5 s, green on the first try), on the module that absorbed a
   second module's definitions (2.3 s, green), and on a moved example module
   (2.3 s, green).  Each answer named the project root it used and said
   `checkedFromSource: true`, which mattered because the worktree's
   interfaces for these modules did not yet exist.
+  **What worked**.  The per-file check was quick enough to confirm each edit
   before moving on, and the verdict was exactly Agda's exit code, so no
   reading of output was needed.  Writing the new lemmas whole and checking
   once was the right loop for code this small; no holes were needed.
+  **What was awkward or missing**.  Three of the four repositories the work
   touched are separate checkouts with their own registries, and the server,
   bound to the checkout the session was launched from, refuses their files
   by design (`rootMismatch`), so their checks ran on the command line.
   `check_project` was not used: the whole-library gate needed an environment
   variable pointing the dev shell at an already-built dependency copy, a
   `make clean` first for a from-source time, and `/usr/bin/time -v` for wall
   time and peak memory, none of which the tool's call can carry.  The gates
   took 1 to 10 minutes each and ran in the background while other work went
   on, which a blocking tool call would have prevented.
+  **Command line comparison**.  For this session the command line was the
   more efficient loop for every whole-library gate (timing, environment,
   other checkouts, running in the background), and the server was the more
   efficient loop for the three single-file checks, where it saved entering a
   dev shell and parsing output.  A session that is mostly moves and prose
   gains little from the server beyond those checks.
