<!-- File: docs/field-reports/2026-10-25-fls-leios-four-pr-review.md -->

# 2026-10-25, fls: semantic probes during four PR reviews

+  **Date**: 2026-10-25.
+  **Harness**: Codex CLI 0.164.0.
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: pull request 1346, pull request 1355,
   pull request 1363, pull request 1364.
+  **Tools called**: normalize 5, get_goal 1.

This session reviewed four changes to the Dijkstra specification.  It used
agda-mcp to evaluate a quorum predicate and inspect a scratch proof's goal.
Separate command-line runs checked the reviewed sources and executed the
extracted Haskell interface.  No agda-mcp defect was observed in this sample.
The running server's version and revision were not recorded.

+  **Tools used**.  Five `normalize` calls evaluated the quorum predicate.
   At a 75 percent threshold, keyed weights of 74, 75, and 76 percent gave
   false, true, and true.  A keyless seat of full weight gave false; two
   keyed seats of weights one-half and one-quarter gave true.  One
   `get_goal` call inspected a hole in a scratch chain-rejection proof.
+  **What worked**.  The interaction process served both an existing sibling
   worktree and a detached scratch worktree.  Responses identified the
   expected worktrees through the response's `project.root`, with
   `rootSource: nearest-agda-lib`.  The first normalization reported
   `lane.load: first` and `loadElapsedMs: 15633`; the next four reported
   `lane.load: reused`, with total call times of 81 to 154 milliseconds.
   `get_goal` reported `source: interaction-lane`, `lane.load: first`, and
   `loadElapsedMs: 19541`.  It returned the expected equality and the three
   local variables `cs`, `b`, and `cert`.
+  **What was awkward or missing**.  No tool failure occurred in these six
   calls.  This was a small sample: it exercised neither hole filling nor
   project-check tools, and it does not establish their behavior.
+  **Command line comparison**.  Persistent normalization was convenient
   for several small semantic questions in one scope.  The command line
   supplied independent build verdicts and compiled and drove the exported
   Haskell function.  This session did not compare those checks with the
   server's batch tools, so it does not establish a speed advantage over
   those tools.

The normalization scope was
`src/Ledger/Dijkstra/Specification/Leios.lagda.md` at PR 1355's reviewed
head, `9c94ea99c51b836b62ee758ec93c177b92f8461b`.  The equality case used
the following expression; `gs` is the governance structure, `pp` the
protocol parameters, `kh` a pool hash, and `vk` a voting key:

```agda
λ gs pp kh vk → does (¿ certifiable gs (record pp { leiosQuorumStakeThreshold = clamp (ℚ.normalize 3 4) }) (record { pool = kh ; weight = clamp (ℚ.normalize 3 4) ; key = just vk } ∷ []) ¿)
```

The adjacent cases replaced the seat weight with `ℚ.normalize 74 100`
and `ℚ.normalize 76 100`.  The keyless case used `ℚ.normalize 1 1`
and `key = nothing`, omitting `vk` from the lambda.  The two-seat case
used weights `ℚ.normalize 1 2` and `ℚ.normalize 1 4`, both with
`key = just vk`.  A keyless seat is a committee entry whose optional
voting-key field is `nothing`.  These were arithmetic and filtering
probes, not complete committees constructed by the selection procedure.
