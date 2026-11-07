<!-- File: docs/field-reports/2026-11-07-fls-toolchain-rows-agda-29.md -->

# 2026-11-07, formal-ledger-specifications: measuring a move to agda-stdlib 2.4 and Agda 2.9

+  **Date**: 2026-11-07.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: none.
+  **Tools called**: none.

The session measured what moving the specification's toolchain takes: from
Agda 2.8.0 with agda-stdlib 2.3 to agda-stdlib 2.4 on Agda 2.8.0, and then to
Agda 2.9.0-rc3.  It type-checked the five dependency libraries and the whole
closure from source under two Agda binaries and four library stacks, each row
with its own libraries file, and edited about 60 files of the specification.
Result: the stdlib 2.4 move works on Agda 2.8.0 with four small code changes
and a 16-name rename (also in the flake's own build); under the release
candidate the closure checks after five patterns of change driven by 2.9's new
instance search, and a fix to a reflection library's deriving (names made
inside `runSpeculative` were reused by later fresh names).

+  **Tools used**.  None.  The tools were loaded at the start; no call was
   made.
+  **What worked**.  Not exercised.
+  **What was awkward or missing**.  The server answers about a file with the
   one Agda and the one libraries file the project's registration names
   (here the 2.8.0 toolchain of the checkout's lock).  Every question in this
   session was about another toolchain: whether a configuration checks under
   Agda 2.9.0-rc3, or under 2.8.0 with a different standard library, from
   source, with nothing reused from another configuration's interfaces.  A
   lane bound to the registered toolchain would have answered a different
   question.  A per-call override of the Agda binary and the libraries file
   (on `check_file` and `check_project`), with the interfaces kept apart by
   configuration, would have let the server run these rows.  The minimal
   reproductions of 2.8 against 2.9 behavior (single files with
   `--no-libraries`) also needed a second binary per call.
+  **Command line comparison**.  The command line was the right loop: one
   wrapper script per row (binary plus libraries file plus a throwaway
   `AGDA_DIR`) and one runner that recorded exit code, wall time, peak memory
   and warning counts.  A failing row resumed from the interfaces of the
   modules before the error, so most iterations took 15 s to 4 min; the
   from-scratch closure under 2.9.0-rc3 took 7 min against about 20 under
   2.8.0.
