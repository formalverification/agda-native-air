<!-- File: docs/field-reports/2026-11-24-agda-algebras-597.md -->

# 2026-11-24, agda-algebras: the move to the released Agda 2.9.0

+  **Date**: 2026-11-24.
+  **Harness**: Claude Code 2.1.332.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: ualib/agda-algebras.
+  **Issue or pull request**: issue 597, pull request 642.
+  **Tools called**: type_of 2, check_file 1.

The session moved agda-algebras' flake from a pre-release Agda 2.9.0 (the
`nightly` of 2026-10-05) and a patched standard-library 2.3 to the released
Agda 2.9.0 and standard-library 2.4.1, and renamed five names the new standard
library deprecates (105 textual replacements in 16 modules).  The evidence the
work needed was whole-library: `Checking` counts and warning positions by kind
from cold and warm `make check` runs, compared as sets against a baseline.  So
agda-mcp served only to confirm, at each stage, which Agda and which registry
it was running, and to check the one module edited after the last whole run.

+  **Tools used**.  `type_of` before the shell was re-entered on the new pins
   (128 ms): the worktree's wrapper still named standard-library 2.3, while
   `agda-algebras.agda-lib` already required `standard-library-2.4`, and the
   answer was the in-band `LibraryError` "Library 'standard-library-2.4' not
   found", with the installed libraries listed, which is the failure the
   flake's two-step upgrade is meant to produce.  `type_of` of `_×?_` after
   re-entry (1,544 ms, of which the lane's load was 1,505 ms): the lane had
   respawned on its own (`spawned: true`) and reported the registry's
   `standard-library-2.4` at the 2.4.1 store path, with the module loaded from
   interfaces (`checkedFromSource: false`).  `check_file` on the one module
   whose prose changed after the last cold run (487 ms, exit 0, no
   diagnostics).
+  **What worked**.  The lane follows a checkout's own toolchain without any
   change of configuration: the wrapper's content stamp (`agdaStamp`, an FNV
   hash of `.agda/bin/agda`) changed when `nix develop` rewrote it, and the
   next call started a new process on the new Agda.  The verbose echo
   (binary, registry, registered libraries with their store paths) answered
   "which Agda is this?" in one call, which is the question a toolchain move
   asks at every step.
+  **What was awkward or missing**.  Nothing in the calls made.  The tool
   that would have mattered is `check_project`, and it was not used because
   its answer lacks what this work measured: it reports `modulesChecked` and
   an output tail, but not the warnings by kind and position (Agda repeats
   them at the end of a run, so a raw count overstates them), nor a path to
   the full log, so two runs cannot be compared as sets of positions from its
   answers.  A `warnings` summary (distinct positions per kind) and the log's
   path in `check_project`'s answer would let a toolchain move be done
   through it.
+  **Command line comparison**.  For this work the command line was the more
   efficient loop, and not narrowly: each run was timed under GNU time, some
   pinned to one core with `taskset`, interleaved with runs of another
   checkout at the base commit, with the load average recorded around each;
   and the evidence was a `comm` of warning-position sets between logs.
   None of that fits a single blocking gate call.  Interactive tools would
   have been the right loop had the port needed real fixes; it needed only
   renames whose types the standard library's source settled.
