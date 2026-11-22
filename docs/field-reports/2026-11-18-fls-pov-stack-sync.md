<!-- File: docs/field-reports/2026-11-18-fls-pov-stack-sync.md -->

# 2026-11-18, fls: checking separate branches of the PoV stack

+  **Date**: 2026-11-18.
+  **Harness**: Codex CLI 0.170.0, source cli.
+  **Model**: gpt-6.1-sol (OpenAI).
+  **Effort**: xhigh.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: pull request 1210, pull request 1278, pull request 1326.
+  **Tools called**: type_of 1, check_project 2.

The session synchronized a published PR stack by merging each updated parent
into its child.  It preserved the certificate and governance PRs as separate
diffs, and retired the batch follow-up after an independent source audit and
whole-tree equality established that its work was inherited.  The two retained
heads passed their library, wiring, test-library, and strict documentation
checks before publication.

+  **Tools used**.  `type_of` queried a certificate lemma in a sibling
   worktree in 44.264 seconds, with a forced lane load of 44.140 seconds.
   `check_project` checked the certificate worktree in 605.153 seconds,
   rechecking 233 modules from source.  The same tool checked the governance
   worktree in 52.470 seconds, rechecking seven modules after seeding its cache
   from the completed parent check.  Both gates exited zero with no
   diagnostics.
+  **What worked**.  Absolute `projectPath` arguments selected the intended
   sibling roots for the whole-project gates.  The verbose certificate result
   named the correct command working directory, and a process inspection
   confirmed it.  The knowledge query also identified the sibling root
   correctly.  Temporary safe wiring modules, checked from each worktree
   through the pinned command-line launcher, accepted exactly seven and five
   residual consumer parameters.  Both test aggregators imported all 50 test
   modules against their working copies, and both strict docs builds passed.
+  **What was awkward or missing**.  The long project gate returned its
   output tail only on completion.  Verbose project metadata echoed the
   server-level library registry; the configured gate instead ran the
   project's launcher.  The command working directory and equivalent-command
   fields made that distinction checkable.  The source-library gate needed
   separate test-library and docs stages.
+  **Command line comparison**.  The command line handled the parent merges,
   sequential per-worktree wiring checks, explicit test-library registries,
   and documentation builds.  MCP supplied the type query and both complete
   source-library verdicts.  The proofs already existed, so there was no
   hole-driven drafting.  No comparative timing experiment was run, and this
   session does not establish that either interface is faster.

The harness, model, and effort were read from the current session transcript.
