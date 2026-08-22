# ADR 0001: Proof search on agda-mcp — an oracle-first beam search over conjunctive obligation states

File: `agda-native-air/docs/adr/0001-proof-search-on-agda-mcp.md`

+  **Status**: Draft.
+  **Date**: 2026-08-22 (P0 and P1 landed; P2 and P3 are direction).
+  **Tracking**: [#113](https://github.com/formalverification/agda-native-air/issues/113); phases [#119](https://github.com/formalverification/agda-native-air/issues/119) (P0, PR [#121](https://github.com/formalverification/agda-native-air/pull/121)), [#122](https://github.com/formalverification/agda-native-air/issues/122) (P1, PR [#126](https://github.com/formalverification/agda-native-air/pull/126)), [#123](https://github.com/formalverification/agda-native-air/issues/123) (P2), [#124](https://github.com/formalverification/agda-native-air/issues/124) (P3).
+  **Ancestry**: issue #112 (post-mortem of the retired v0.3 `search.py`), whose four lessons this design encodes as types and tests rather than prose.

## Executive summary

We are building a machine that proves small Agda theorems by search, with Agda itself as the only judge of every step.  This document is the design record: what the search is, why it is shaped the way it is, what has been measured, and where it is going.

The idea in one paragraph.  A theorem with a hole in its proof is an *obligation*.  The searcher keeps a set of unfinished obligations for the file it is working on, and repeatedly plays a simple move: pick the first open obligation, propose a handful of candidate terms that might fill it, and ask Agda — through the `agda-mcp` server's `fill_hole` tool — whether each candidate typechecks there.  A candidate that typechecks is *committed*: it is spliced into the working copy of the file, and any fresh holes it contains (a candidate may be a partial application like `_,_ {!!} {!!}`, whose two holes become two new obligations) replace the obligation it discharged.  The search fans out over these states in a beam: at each depth it keeps only the few most promising states and expands those.  A proof is *claimed* only when a state has no obligations left AND a final, strict, whole-file check by Agda comes back green.  Nothing the searcher believes is ever trusted: Agda's exit code is the sole source of truth, at every step and again at the end.

Why this is the shape it is comes down to one measured fact: **the oracle is the entire cost**.  Each `fill_hole` judgement spawns a batch Agda process that spends ~2.6 seconds loading the standard library's interfaces before it checks anything; everything else the searcher does — building candidates, ranking states, bookkeeping — costs microseconds, and even the server's persistent "interaction lane" answers questions about a loaded file in 1–3 milliseconds.  So the design optimizes exactly one quantity, the *number of batch judgements*, and treats everything that can reduce that number as nearly free: judgements are memoised, budgets are denominated in judgements, and a millisecond-scale `type_of` "peek" can pre-filter candidates before they cost a judgement.  This is also why the searcher's host language is irrelevant and was chosen by measurement rather than taste (transport overhead is 0.21 % of oracle time; the client lives in Scala beside the benchmark and corpus machinery).

The prior attempt's central defect is designed out at the type level.  The retired `search.py` carried a single goal per state and declared victory when *any* subgoal closed — a lemma with two obligations counted as proved when one was discharged.  Here the state *is* the obligation set, "done" is emptiness of the whole set, and the only way to construct the `SolvedClaim` type is through a factory that demands both the empty set and the final green check.  A regression test pins exactly the two-obligation trap, both purely and against the live server.

### Where it stands

P0 landed the substrate (state model, oracle client, single-step harness) and the measurement that fixed the economics.

P1 landed the loop with a fixed, non-learned action space — the P0 closers, the goal context's assumptions, and applications of the lemmas the fixture imports — and measured the baseline: **6 of 22 benchmark obligations solved (routine 6/7, compositional 0/10, non-obvious 0/5)**, which is *exactly* the ceiling of what that action space can express in term mode, so the number is saturated, not disappointing.  A measured `type_of` pre-filter cut oracle judgements by 88 % and end-to-end time by 4.5× at zero cost in solves.

### Where it goes

The action space is the bottleneck, by construction and now by measurement.

P2 replaces the fixed space with candidates retrieved from a real library corpus (the `agda-strux` extraction and its search tools), behind the same `Proposer` interface the fixed space already implements.

P3 replaces retrieval ranking with a learned policy over the existing policy-backend contract.

Every phase is scored on the same benchmark through the same JSONL schema, so the baselines stack: each phase must beat the last, on the same 22 obligations, in the same currency of oracle calls.

## 1.  Context: why proof search, and why now

The project's north star is AI agents that work effectively with Agda.

Retrieval and representation (`docs/PLAN.md` Phase 2) tell an agent *what might help*; proof search is the part that *does mathematics* — proposes a step, submits it to the checker, and iterates.  It had exactly one prior implementation, `agda-dojang/python/tools/search.py`, dead since 2026-03-10 and archived under #112.

Three things changed by mid-2026 that made a proper restart worthwhile (#113):

+  **The oracle is native**.  `agda-mcp` exposes `fill_hole`, `get_goal`, and `check_file` directly, and since the #68 hardening wave also answers scope, type, and definition questions mid-proof from a persistent interaction lane (#75, #107, #108) — precisely the information a proposer needs.
+  **The corpus exists**.  `agda-strux` extraction plus `search_by_name` / `search_by_type` can supply candidate lemmas at scale; the old search's action space was hardcoded to two candidates.
+  **The measurement exists**.  `data/benchmarks/` is the M1-5 suite (22 obligations, difficulty tiers `routine` / `compositional` / `non-obvious`), and the proof-completion evaluator already emits versioned JSONL (`eval-proof-completion.v0`), so search results sit beside the policy-backend baseline with no new measurement apparatus.

Four lessons from #112 are load-bearing and appear throughout: report actions are peeks, not moves; partial application consumes visible binders only; there are two caches because the oracle is the cost centre; and children are ordered by remaining obligations.  The fifth inheritance is the defect: the old search was disjunctive where obligations are conjunctive.

## 2.  The oracle and its economics

`agda-mcp` runs two lanes, and the search respects the boundary absolutely (docs/agda-mcp-interaction-lane.md):

+  **Batch lane** (verdicts).  `check_file` and `fill_hole` derive success from a one-shot `agda` process's exit code.  This lane is the only judge: probe outcomes, commits, and the final claim all come from it.
+  **Interaction lane** (knowledge).  A persistent `agda --interaction-json` child answers `get_goal`, `type_of` (and others) about a loaded file in milliseconds.  Knowledge informs proposals and pre-filters; it never decides anything.

P0's measurement (issue #113, run `split-m15`) fixed the numbers the design lives by:

+  Oracle calls are effectively 100 % of wall time; proposal time is milliseconds per fixture.
+  Each batch call costs ~2.6–2.9 s on stdlib fixtures, and the cost is per-spawn import-graph loading, not checking: a builtins-only fixture answers the same call in ~0.2 s.
+  Transport plus server handling is 0.21 % of oracle time (~6 ms/call), which killed the "rewrite the client in Haskell for latency" fork: no host language avoids the batch subprocess, so the client stays in Scala (`strux-driver`), beside the benchmark runner and the corpus.
+  P1 added a refinement: the interaction lane reuses loaded interfaces in memory, so switching it to a new file costs ~220 ms, and *questions* about a loaded file cost 1–3 ms.  Knowledge is two to three orders of magnitude cheaper than judgement.

Consequences, all of which are now code: the budget is denominated in batch judgements; judgements are memoised; knowledge calls are unbudgeted but ledgered; and any pre-filter cheaper than ~2.6 s that rejects even a small fraction of candidates pays for itself.

## 3.  The state model (P0, `Model.scala`)

+  **A state is an obligation set, a working-copy content, and a script.**  `SearchState(content, obligations, script)` with conjunctive semantics: solved means the *whole set* is empty.  There is no per-goal success anywhere in the model, so #112's disjunctive defect is unrepresentable.
+  **Probes are not moves.**  `fill_hole` restores the file server-side, so every probe is a peek; `ProbeOutcome` (what the oracle said) and `Move` (an action committed to the working copy) are distinct types, and the script has type `Vector[Move]`.
+  **States are unforgeable.**  `SearchState` and `SolvedClaim` are `sealed abstract case class`es with private constructors — the Scala 2 idiom that suppresses the synthetic `apply` and `copy` — so a state is born only through `initial` or `commit`, and a claim only through `fromFinalCheck`, which refuses an inhabited obligation set, a failed check, and even internally inconsistent evidence (success reported beside a non-zero exit).
+  **The obligation set is the oracle's, not ours.**  Every `fill_hole` response carries the re-anchored hole list describing the file as that candidate would leave it (issue #79); `commit` adopts that list wholesale, so client-side hole arithmetic can never drift from Agda's.
+  **Two caches, two key types.**  `OracleKey(contentFingerprint, line, col, candidate)` memoises judgements — same content, same hole, same candidate is one Agda call per fixture run, by construction.  `StateKey(contentFingerprint, script)` identifies states for frontier dedup.  Conflating them either re-runs Agda or wrongly prunes the frontier (#112's lesson), so they are distinct case classes.
+  **Strict wire decoders.**  The response fields the search acts on (`holes`, counts, `elapsedMs`, `context`) are required, and counts are cross-checked against lists: a drifted server shape fails the decode visibly instead of bending ranking or measurement.  Every decoder is pinned against responses captured verbatim from the live server.

## 4.  The loop (P1, `BeamLoop.scala`)

Level-synchronous beam search.  Each frontier state is expanded at its **first open obligation** — a fixed selection policy, stated and pinned as a deliberate simplification, sound because the set is conjunctive and every commit re-anchors from the oracle (selection order affects which proofs are found under budget, never whether a found proof is real).  Expansion writes the state's content to the working file, reads the goal (`get_goal`), asks the proposer for candidates, optionally peeks each, and probes the survivors.  Ok probes commit to children; children are deduped against every state ever enqueued, ranked by the landed `Rank` on their creating probe (fewer remaining obligations first), and the best `beamWidth` become the next level.  A probe that closes every obligation is claimed immediately through the final batch gate: search work after a proof would be budget spent for nothing.

+  **Termination is a distinct per-fixture status**: `solved` (the claim was granted), `exhausted` (the frontier emptied, or the depth bound cut a live frontier), `budget_exceeded` (the probe budget ran out with work remaining).
+  **The budget counts fill_hole probes that miss the memo** — the ~2.6 s coin.  Memo hits are free and stay free at the cap (the loop consults the memo before the budget gate).  The baseline `check_file`, the final strict checks, and the knowledge calls are ledgered but not gated; they are bounded structurally (one `get_goal` per expansion, expansions ≤ beam × depth, final checks ≤ closing probes).
+  **Defaults**: beam 4, depth 6, budget 60 — tunables on the Make target (`PROOF_SEARCH_BEAM/DEPTH/BUDGET/DEDUP/PEEK`).
+  **Anomalies are loud and non-fatal.**  A commit the state refuses, a wire drift, or a closing probe whose final check disagrees raises out of that fixture; the sweep continues, every artifact is written (an anomalous fixture keeps its attempt rows, wall clock, and probe counts), and the run exits non-zero.  This is P0's discipline, inherited from #112's own failure mode: a harness that exits 0 while writing broken rows lets breakage sit silent for months.

## 5.  The action space and the proposer seam (P1, `Propose.scala`)

Proposals go through one interface, which is the seam every later phase plugs into:

```scala
trait Proposer {
  def propose(state: SearchState, target: Obligation, goal: GoalView): IO[Vector[String]]
}
```

P1's implementation is deliberately fixed and non-learned, in proposal order: the P0 closers (`refl`, `tt`); the goal context's assumptions by name (from `get_goal`'s context, decoded strictly); and applications of every name the fixture imports through `using` lists — one `{!!}` per remaining visible binder via the landed partial-application arithmetic, binder counts read from lane `type_of` answers through a deliberately small pi-type splitter (arrows at bracket depth 0), applications ordered cheap-before-expensive (#112's lesson four, applied to proposal order because the budget can run out mid-expansion).  Two hard-won details are pinned in tests:

+  **Applications are parenthesized** (`(s≤s {!!})`), because a hole is an argument position as often as a right-hand side, and a verbatim splice of `s≤s {!!}` into a sub-hole reads as `s≤s sym {!!}` — a different term.  The first P1 sweep measured every depth-1 lemma application dying exactly this way.
+  **The splitter is a proposal device, not an authority.**  It reads printed types (with their renamed binders, hidden groups, and newlines) well enough to count visible binders; the oracle polices what it gets wrong, because an overcount is refused as a type error and an undercount leaves a partial application the goal must then accept.

The term-mode ceiling is a property of this space and must accompany its numbers: no case splits and no `with` means clause-restructuring golds are unreachable.  On M1-5 that is 16 of 22 (14 inductions, 2 case splits, plus a chain needing imports the obligation lacks); the six with expressible single-term golds are exactly the six P1 solves.

## 6.  The `type_of` peek (P1's measured experiment)

The modern form of #112's "report actions are peeks": before spending ~2.6 s judging a candidate, ask the interaction lane to *infer the type* of the candidate with `_` metas in place of its holes, at the goal, in milliseconds — and skip the judgement when the answer cannot fit.

What the wire probes established (captures in `strux-driver/src/test/resources/search/`): under-determined metas are ANSWERED, not errored — the lane prints named metas (`sym _` infers `_y_8 ≡ _x_7`) — and bad expressions come back as in-body errors (`NotInScope`, `CannotApply`, `UnequalTerms`) in 1–3 ms.  The filter therefore rejects on a lane error, or when the inferred type cannot textually match the goal display with every meta read as a wildcard — the *same* meta being the *same* wildcard, so `refl`'s `_x_9 ≡ _x_9` is rejected at `m + n ≡ n + m` and kept at `n ≡ n`.  One rendering divergence needed canonicalization: Agda folds closed naturals to numerals in goal displays (`1 ≤ suc n`) but a meta blocks the folding in inferred types (`suc _m_5 ≤ suc _n_6`), so numeral tokens are expanded to `suc` towers before comparison; without this the peek falsely rejects `(s≤s {!!})` and costs a solve.

Measured end to end on M1-5: the same 6 solves with byte-identical scripts; probes 435 → 50 (−88.5 %); batch oracle time 1227 s → 209 s; wall 21.5 min → 4.7 min (4.5×); probe precision 6.7 % → 70 %; and the chain-burners stopped burning (budget-exceeded became honest depth-capped exhaustion).  Two rules keep it sound in spirit: a peek can only ever *skip* a judgement, never substitute for one, and any failure to peek keeps the candidate.  It ships opt-in (`--peek on`) until it re-validates on P2's retrieval candidates, whose types will exercise renderings this suite cannot.

## 7.  Reporting: one schema for every phase

Every run writes the shared eval schema, so search results sit beside the policy-backend evaluator's with no private format: `results.jsonl` (one `eval-proof-completion.v0` row per judged candidate; `fixtureId` is the module stem, `benchmarkId` the additive join key, `elapsedMs` client-observed wall clock), `fixtures.jsonl` (per-fixture summaries on the same schema, plus additive `searchStatus`), `timing.jsonl` (the `proof-search-timing.v0` ledger, per call, with `type_of` and `peek` phases beside P0's, cache hits marked, and proposal rows carrying the proposer's *own* time — nested oracle calls are subtracted, since the ledger already carries them), and `report.json` (config, per-tier solve counts, per-fixture outcomes, the batch/knowledge/proposal split).  Solved proofs land as typecheckable artifacts under the run's `solved/`.

## 8.  Where it stands: the numbers

P0 (issue #113, the measurement that settled the fork): oracle 180 calls per pass at ~2.6–2.9 s each, 99.79 % of oracle time in the Agda subprocess, transport 0.21 %, proposal 2.3 ms total.

P1 (issue #113, PR #126; beam 4, depth 6, budget 60):

| configuration | solved | probes | wall |
|---|---|---|---|
| baseline (dedup script, no peek) | 6/22 — routine 6/7, comp. 0/10, non-obv. 0/5 | 435 | 21.5 min |
| dedup content-only, no peek | identical to baseline, per fixture | 435 | 21.6 min |
| dedup script, peek on | 6/22, byte-identical scripts | 50 | 4.7 min |

Decisions taken from those numbers: `StateKey` dedup stays script-inclusive (content-only measured identical here and can only start mattering when a proposer emits hole-free compound candidates — re-measure in P2); the peek is a validated cost lever, opt-in for now; and the baseline every later phase must beat is **6/22, at 435 probes without the peek or 50 with it**.

## 9.  Where it is going

+  **P2 — retrieval proposals (#123).**  Replace the fixed lemma pool with candidates from `search_by_name` / `search_by_type` over a real `agda-strux` stdlib corpus, ranked by premise selection, behind the same `Proposer` seam.  Deliverables mirror P1's: uplift over 6/22, the proposal-vs-oracle split re-reported (retrieval makes proposal time real for the first time), the peek re-validated and possibly made default, and dedup re-measured if retrieval proposes hole-free compound terms.
+  **P3 — policy proposals (#124).**  A learned policy behind the existing contract (`policy_contract.py`, mirrored by `AgdaMCP.Types`; `policy_fixture.py` as the deterministic stand-in), compared against policy-alone top-k and both earlier baselines.  The closed propose–check–learn loop the project has been building toward.
+  **Raising the ceiling** (unscheduled, the largest known win): term mode caps the suite at 6/22, and 14 of the 16 unreachable golds are structural inductions of a single shape (`f zero … = refl; f (suc n) … = cong g (f n …)`).  Reaching them needs case-split moves — plausibly via the interaction protocol's `Cmd_make_case` — which would change the state model's move vocabulary and is deliberately out of P1–P3 scope.
+  **Recorded options, taken only if measurement demands**: parallel oracle workers (N servers over disjoint work copies) if wall time becomes the bottleneck; richer selection policies than first-open-obligation if multi-hole fixtures ever make selection order matter under budget.

## 10.  Decision log

| # | Decision | Status | Evidence |
|---|---|---|---|
| 1 | Obligation sets are conjunctive; `SolvedClaim` requires the empty set AND a final green batch check | Adopted (P0) | #112 post-mortem; pinned in ModelSpec and live in SingleStepIntegrationSpec |
| 2 | The client lives in Scala (`strux-driver`); no in-process Haskell rewrite | Adopted (P0) | Transport is 0.21 % of oracle time (#113 measurement) |
| 3 | Budgets are denominated in batch oracle calls, not seconds | Adopted (P1) | Batch call ≈ 2.6 s import loading dominates all else (#113) |
| 4 | Judgements memoised on `OracleKey`; hits free, including at the budget cap | Adopted (P1) | OracleMemoSpec; BeamLoopSpec cap test (PR #126 round 1) |
| 5 | Frontier dedup keys on content + script (script-inclusive) | Adopted (P1), revisit in P2 | A/B measured identical on M1-5; pinned in BeamLoopSpec |
| 6 | First-open-obligation selection | Adopted (P1), simplification | Sound under conjunctive re-anchoring; pinned in BeamLoopSpec |
| 7 | Application candidates parenthesized | Adopted (P1) | First sweep: every depth-1 application died unparenthesized |
| 8 | `type_of` peek: informs only, opt-in | Adopted (P1), default revisited in P2 | −88.5 % probes, 4.5× wall, zero solve cost on M1-5 |
| 9 | Anomalies never abort a sweep, always redden the run, and keep their diagnostics | Adopted (P0/P1) | #112's silent-breakage failure mode; LoopHarnessSpec |
| 10 | All reporting on `eval-proof-completion.v0` beside the policy baseline | Adopted (P0/P1) | #113 acceptance: no private formats |

## References

+  Issues: [#112](https://github.com/formalverification/agda-native-air/issues/112) (post-mortem), [#113](https://github.com/formalverification/agda-native-air/issues/113) (tracking, with the P0 and P1 measurement comments), [#119](https://github.com/formalverification/agda-native-air/issues/119)/[#122](https://github.com/formalverification/agda-native-air/issues/122)/[#123](https://github.com/formalverification/agda-native-air/issues/123)/[#124](https://github.com/formalverification/agda-native-air/issues/124) (phases); PRs [#121](https://github.com/formalverification/agda-native-air/pull/121) (P0), [#126](https://github.com/formalverification/agda-native-air/pull/126) (P1).
+  Docs: `docs/agda-mcp-interaction-lane.md` (the two-lane policy and the lane protocol), `agda-mcp/README.md` (tool contracts), `data/benchmarks/README.md` and `docs/benchmarks/taxonomy.md` (the suite), `agda-dojang/README.md` (the result schema).
+  Code map (`strux-driver/src/main/scala/struxdriver/search/`): `Model.scala` (state, claims, keys), `Wire.scala` (strict decoders), `McpClient.scala` (transport), `Oracle.scala` (timed, memoised calls), `Actions.scala` (application arithmetic, pi splitter), `Propose.scala` (proposer seam, fixed space, peek), `BeamLoop.scala` (the loop), `Scaffold.scala` (shared fixture scaffolding), `SingleStepHarness.scala` (P0 entry), `LoopHarness.scala` (P1 entry); tests beside them in `src/test/scala/struxdriver/search/`, wire captures in `src/test/resources/search/`.
