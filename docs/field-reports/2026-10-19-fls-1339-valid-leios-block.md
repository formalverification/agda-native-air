<!-- File: docs/field-reports/2026-10-19-fls-1339-valid-leios-block.md -->

# 2026-10-19, formal-ledger-specifications: a predicate reshaped by instance-search probes

+  **Date**: 2026-10-19.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: pull request 1339, pull request 1346, pull
   request 1355, pull request 1360, pull request 1361.
+  **Tools called**: type_of 5, check_file 1.

The session reworked a block-validity predicate in one pull request to answer
review comments (a helper inside the definition to be replaced by a disjoint
union, with the hope that the hand-written decider would then go), restacked a
dependent pull request around a restructured relation, rebased a third, and
typechecked two colleagues' pull requests for review.  Every edit was in a
worktree other than the server's own checkout.  agda-mcp served the design
question; batch agda from the command line served every gate.

+  **Tools used**.  `type_of` five times, against a file in a sibling
   worktree.  The first call loaded the module after a rebase onto a `master`
   that had changed both eras' spines, and took 489 s, all of it the load.  The
   next three took 123, 269 and 431 ms: each asked for the type of `λ b → ¿ … ¿`
   over a candidate formulation of the predicate, so the answer said whether
   instance search could decide it.  The fifth, with `reload: true` on a
   dependent module after editing the predicate's module, took 557 s and stood
   in for that module's typecheck.  `check_file` once, on the same sibling
   worktree, refused in 177 ms.
+  **What worked**.  The three probes settled the design in about a second in
   total.  A union of `Is-nothing`, `Is-just` and Boolean equalities was
   decided by instance search; `ts ≡ []` was not, and the in-band error named
   the reason exactly (`InstanceNoCandidate`, no `DecEq` for the transaction
   type); `length ts ≡ 0` was.  So the predicate became a disjoint union with
   no hand-written decider, as the reviewer had hoped, and the reason for the
   one unusual conjunct went straight into the reply to the review.  The
   interaction lane resolved the sibling worktree's own `.agda-lib` as the
   project root (`rootSource: nearest-agda-lib`) and loaded that tree, not the
   server's checkout.
+  **What was awkward or missing**.  `check_file` on the same file failed with
   `AmbiguousTopLevelModuleName`, naming the server's checkout and the worktree
   as the two candidates, although its own `project.root` named the worktree:
   the batch run evidently resolves modules from the server's working directory
   while the lane uses the resolved root.  A session that trusts `project.root`
   is misled; the batch run should use the same root, or the answer should say
   which directory it searched from.  The first lane load after a rebase cost
   as much as a cold batch check (8 minutes here), with nothing reported in
   between; a progress line naming the module being checked would help decide
   whether to wait.  The idle lane held about 7.5 GB resident, which matters
   when three batch gates run beside it.
+  **Command line comparison**.  For the design question the lane was
   decisively better: three edit-and-check cycles of minutes each became three
   sub-second probes, and the probe that failed explained itself.  For
   everything else the command line was the right loop: mechanical rebase
   conflicts, prose, and the whole-project gates (the closure, the instance
   listing, and a test library that needs its own library file), which ran
   detached and in parallel in three worktrees, a shape no single agda-mcp
   project root offers.
