<!-- File: docs/field-reports/2026-10-22-with-abstraction-cost-and-lossy-unification.md -->

# 2026-10-22, a private repository: four new modules, a theorem both ways and a finite decision procedure

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 10, exports_of 1.

The session wrote four literate Agda modules from scratch (about 1,450 lines
in all) over a library of setoid algebras: a construction of a substructure as
a structure of the same kind, a module of predicates with their lemmas and
finite decision procedures, a theorem module in two directions, and an
examples module that runs the decisions on small finite instances.  The
server was connected from the start and answered for the worktree the session
ran in (`project.root` named it, loaded through the nearest `.agda-lib`), on
Agda 2.9.0.  Every module was written whole and then checked with
`check_file`; no holes were used, and no candidate was tried with
`fill_hole`.  Eleven calls in all; the final gate was the project's `make
check`, run cold from an empty build (77 s, within noise of the baseline) and
once more warm on the final text.

+  **Tools used**.  `exports_of` once, on an existing module, as the
   connectivity probe (1.8 s, a first load).  `check_file` ten times: the
   first module passed first time (1.9 s); the second took four rounds
   (a `ParseError` from a top-level definition placed before indented code
   that still belonged to a module block, 51 ms; an `UnequalTerms` whose
   `expected`/`actual` named exactly the wrong absorption step, 2.2 s; an
   `UnequalTypes` on universe levels of a hand-written composition
   operator, 2.3 s; then success, 6.9 s including dependencies); the third
   took four rounds too (`UnequalTerms` on a homomorphism's compatibility,
   where the diagnostic showed `pair (a 0F) (a 1F) x` against `a x` and so
   named the missing rewriting step; `UnsolvedConstraints` listing the
   stuck metas with their blocked equations, which showed that the
   congruence lemma on the product side had nothing to solve against and was
   not needed; `UnsolvedMetaVariables` with three source ranges, which were
   the implicit arguments to give explicitly; then success, 2.2 s).  The
   tenth `check_file`, on the examples module, never returned: the harness
   moved it to the background at 120 s, `ps` showed the batch agda at 37 GB
   and climbing, and the session stopped the task and killed the process by
   hand.  The cause was found with capped command-line probes (below), and
   the fix was the `--lossy-unification` pragma.
+  **What worked**.  The diagnostics decided every fix on the first reading:
   the `involved.expected`/`involved.actual` pair for a wrong lemma, the
   per-meta blocked equations for unsolved constraints, and the source
   ranges for unsolved metas each pointed at the one line to change.  A
   cold `check_file` on a module with a dozen library imports came back in
   about two seconds against warm interfaces, so the write-whole-then-check
   loop cost little per round.  The verdict's `exitCode` was all the session
   read; the message text was never needed to decide success.
+  **What was awkward or missing**.  Two things, both about cost rather than
   correctness.  (1) A `check_file` that blows up has no memory bound: the
   tool reported nothing until the harness's 120 s limit, and the agda it
   had started kept running after the task was stopped, at 43 GB when it was
   killed by hand.  A heap or RSS cap on the batch agda, and a `check_file`
   that kills its child when the call is cancelled, would have turned a
   43 GB incident into a 20 s refusal.  (2) The server gives no
   per-definition timing; to find that one `with`-abstraction on a decision
   procedure cost 3.8 s of a 4.8 s module, and that two applications of a
   generic theorem to concrete finite structures were the whole cost of the
   examples module (17 s and 1.6 GB at four elements, out of memory under
   an 8 GB cap at six, without `--lossy-unification`; 0.15 s with it), the
   session ran `agda --profile=definitions` and `--profile=modules` from the
   shell, and bisected the examples module by truncating a renamed copy
   under `ulimit -v`.  A profile option on `check_file`, or a hint in the
   result when a single definition dominates, would have saved the detour.
+  **Command line comparison**.  For the three theory modules the server was
   the more efficient loop: a structured diagnostic per round, no wrapper or
   library-file handling, and the worktree resolved correctly without any
   setup beyond entering the dev shell once.  For the cost work the command
   line was necessary, not merely more efficient: the memory cap, the
   timeout, the profiles and the truncation probes are all things the server
   does not offer.  Roughly half the session's checking was through the
   server and half through the shell, and the split fell exactly along that
   line.
