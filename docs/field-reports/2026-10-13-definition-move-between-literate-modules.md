<!-- File: docs/field-reports/2026-10-13-definition-move-between-literate-modules.md -->

# 2026-10-13, a private project: one definition replaces another across two literate modules (Claude Fable 5.1)

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 5, check_project 1.

A session that retired a defective definition in favor of its repaired form:
three definitions and a two-line lemma moved from one literate module
(`.lagda.md`) into another, the imports of both followed, and the prose of
five more files followed the names.  No new proof was written beyond one
trivial converse, so no hole was ever opened; the server's work was the
verdict on each touched module, and the final gate.  The branch had been
created before the toolchain moved (Agda 2.8.0 to a pre-release 2.9.0, with a
new pin of the dependency library), so the session first fast-forwarded it
and re-entered the Nix dev shell in the background, which rewrote the
per-checkout Agda wrapper the server runs; the server, started before that,
picked up the new Agda on its next call with no restart, since `check_file`
runs a cold agda through the wrapper each time.  Three commits, one pull
request; the Agda gates green at every step, and the project's Python test
suite green at the baseline and on its rerun, after one failure on a
wall-clock field while other commands loaded the machine, nothing the
server was involved in.

+  **Tools used**.  `check_file` on the module that received the definitions
   (7.2 s, cold, `checkedFromSource: true`), then on the module that lost them
   (29.6 s; it re-checked the first as a dependency), then on two modules whose
   only change was prose (9.3 s and 11.6 s), then on the first again after a
   prose edit (6.4 s).  `check_project` once for the whole-library gate at the
   end: exit 0 in 15.4 s warm, with `modulesChecked: 24`, the downstream
   closure of the edited module.  The cold baseline of the same gate from the
   shell, before any edit, took 167 s, including the 179 interfaces of the
   dependency library that the fresh worktree had to build.
+  **What worked**.  One call per touched module, each a structured verdict
   with agda's own exit code and an empty diagnostics list, was all this edit
   needed; `modulesChecked` on the gate and the per-call times gave the numbers
   the session's account asked for without a second measurement.  The
   per-checkout wrapper indirection meant a toolchain change under a running
   server cost nothing.
+  **What was awkward or missing**.  Nothing blocked.  Two small things: the
   gate call blocks for its whole run, so the two long baselines (the cold
   check and a nine-minute Python test suite) went to the shell in the
   background instead; and a `check_file` on a module whose dependency had
   just changed re-checked the dependency silently, which is right, but the
   time (29.6 s against 7.2 s) is explicable only to someone who knows the
   import graph, so a line naming the dependencies re-checked would help.
+  **Command line comparison**.  Neither loop was more efficient for this
   work, which had no holes to fill.  The server saved composing the
   `nix develop --command agda <file>` lines from a shell that was not inside
   the dev shell, and returned verdicts as data rather than as text to grep;
   the command line was needed for every run longer than a couple of minutes,
   because those are better detached and read back from a file.  For a
   session that moves proved code, the server's unit of work (a verdict per
   file, a verdict per gate) is the right size.
