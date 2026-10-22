<!-- File: docs/field-reports/2026-10-22-polynomial-decision-table.md -->

# 2026-10-22, a private repository: a second decision procedure, written as a table and measured

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 5.

The session wrote a small Agda module (one indexed data type, nine helper
definitions and a parameterized module of about forty lines) that decides a
relation the library already decides by a direct recursion, this time by a
table of subproblems, and then measured the two procedures against each other:
on a family where the recursion's cost doubles with a parameter, and on the
decisions of the library's heaviest example module, which the table brought
from about fourteen seconds to under four.  Every module typechecks under
`--safe`.  The work was mostly measurement, not proof: the module checked on
the first try, and the day went to timing runs, which the server does not do.

+  **Tools used**.  `check_file` on the new module twice (2.3 s and 2.5 s,
   the second after a change to its evaluation strategy), once on an existing
   module at the start to confirm the server could see the worktree (4.7 s,
   `checkedFromSource:false`), and twice on the finished example modules at
   the end (2.1 s and 2.3 s, both `checkedFromSource:false`, since the batch
   build had just written their interfaces).  Every call answered
   `success:true`, and every call named the worktree as its project root,
   which mattered: the session ran in a fresh git worktree whose toolchain
   directory did not exist until the session entered the dev shell once, as
   the project's instructions say.
+  **What worked**.  The verdict was exactly the batch build's: the module
   that passed `check_file` passed `make check` unchanged.  Nothing needed a
   hole: the definitions were small enough to write whole, and the indexed
   type carried the shapes, so the coverage checker, not a goal display, was
   the instrument that confirmed the case analysis.
+  **What was awkward or missing**.  The session's real question was
   evaluation cost, which no tool measures.  The first version of the module
   typechecked and was exponential anyway: the type checker's evaluator
   recomputed a record field at every projection, which only a timing run on
   the doubling family showed (two seconds at one size, four minutes at the
   next).  `check_file` reports its own elapsed time, but that is the cost of
   checking the module, not of evaluating one decision it defines; a
   `normalize` call on one decision would report the evaluation's
   `elapsedMs`, and the session did not try it, since each decision had to be
   timed under the build's RTS flags, pinned to one core, as the project's
   skill requires, which is a shell job.  Twenty-one scratch modules were
   timed that way, in batches run in the background from the shell, with
   `/usr/bin/time` and `taskset`; a `check_file` option to pass RTS flags and
   report peak memory would have covered about half of them.
+  **Command line comparison**.  For this session the command line was the
   more efficient loop: the proofs were trivial and the measurements were
   everything, and the measurements needed the RTS flags, core pinning,
   repeated alternating runs, and `--profile=definitions`, none of which the
   server offers.  The server's five calls were a convenience (a quick verdict
   without leaving the conversation), not a saving.
