<!-- File: docs/field-reports/2026-11-06-fls-generrors-memory-probe.md -->

# 2026-11-06, formal-ledger-specifications: measuring an error-message macro's cost

+  **Date**: 2026-11-06.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: not named.
+  **Tools called**: none.

The session picked up a draft pull request whose earlier work ran in another
harness, confirmed that its branch typechecks (the whole closure from cache in
26 s, no module rechecked) and merges cleanly with `master` (77 modules
rechecked in 4 min 45 s, no warnings), and then tested a reviewer's suggestion:
re-enable a reflection macro that builds failure messages at one call site,
where it had been commented out because CI could not finish the module.  With
the branch's rewrite of the macro, the module checked in 41.5 s of CPU at a
4.5 GB peak, against 19.8 s and 2.2 GB without the macro; on `master`, with the
old macro, the same edit was killed by the OOM killer at a 24 GB cgroup cap
after 2.5 min of CPU.

+  **Tools used**.  None.  The agda-mcp tools were available all session, but
   every question was a cost (CPU seconds, peak resident memory, whether a
   check finishes under a memory bound), not a goal or a type.
+  **What worked**.  The pinned Agda the server runs had been rebuilt earlier
   the same day, so it matched the project's flake; the command-line checks ran
   that same wrapper, and it accepted the interfaces the other harness's session
   had written (no module rechecked).
+  **What was awkward or missing**.  `check_file` returns a verdict and
   diagnostics, but neither peak memory nor a way to bound it, and the
   question here was exactly that bound.  The pinned Agda is linked without
   `-rtsopts`, so `+RTS -M24G` is refused at startup; the cap had to come from
   `systemd-run --user --scope -p MemoryMax=24G -p MemorySwapMax=0`.  The
   comparison on `master` ran in a scratch worktree, which `check_file` cannot
   serve (a sibling tree resolves every module twice).  `fill_hole`'s
   splice, check, and restore is the right shape for "does this one-line change
   still check", but it needs a hole at the site and reports no cost.
+  **Command line comparison**.  The command line was the more efficient loop
   for this work: each probe was one `sed` edit and one `/usr/bin/time -v` run
   in the background, five probes in all, and GNU time's peak RSS and the
   cgroup's `oom-kill` record were the findings.  A `check_file` that reported
   CPU time and peak RSS, and took an optional memory cap enforced outside the
   Agda runtime, would have answered every question here.
