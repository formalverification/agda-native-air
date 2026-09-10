<!-- File: docs/adr/0001-proof-search-on-agda-mcp.md -->

# ADR 0001: Proof search on agda-mcp

File: `agda-native-air/docs/adr/0001-proof-search-on-agda-mcp.md`

+  **Status**: Accepted through P2.  P0, P1, and P2 are landed on `main` and measured; P3 is direction.  Rewritten 2026-09-09 as a decision record; the explanatory companion is [`proof-search/overview.md`], which defines the vocabulary both documents use.
+  **Date**: 2026-08-22 (P0 and P1); 2026-08-27 (P2, first measurement); 2026-09-08 (P2 re-measured after review, and measured on the agda-algebras tier).
+  **Tracking**: [#113] ([M2-9]); phases [#119] (P0, PR [#121]), [#122] (P1, PR [#126]), [#123] (P2, [M2-10], PR [#130] and the stage-two measurement in its comments), [#124] (P3, direction); the benchmark instruments [#127] (the agda-algebras tier, PR [#132]), [#129], and [#142]; the hand-off [#19] ([M2-5]).
+  **Ancestry**: [#112], the post-mortem of the retired `search.py`, whose four lessons this design encodes as types and tests, and whose one defect it makes unrepresentable.

## Executive summary

We are building a machine that proves Agda theorems by search, with Agda itself as the only judge of every step.  This document records what was decided, the evidence that earned each decision, and the measured state of the work; [`proof-search/overview.md`] explains how the search works, with a worked example.

**The idea in six sentences**.

+  A theorem with a hole in its proof is an *obligation*.
+  The searcher keeps a set of unfinished obligations for the file it is working on, and repeatedly plays a simple move: pick the first open obligation, propose a handful of candidate terms that might fill it, and ask Agda, through the `agda-mcp` server's `fill_hole` tool, whether each candidate typechecks there.
+  A candidate that typechecks is *committed*: it is spliced into the working copy of the file, and any fresh holes it contains (a candidate may be a partial application like `(_,_ {!!} {!!})`, whose two holes become two new obligations) replace the obligation it discharged.
+  The search fans out over these states in a beam: at each depth it keeps only the few most promising states and expands those.
+  A proof is *claimed* only when a state has no obligations left AND a final, strict, whole-file check by Agda comes back green.
+  Nothing the searcher believes is ever trusted: Agda's exit code is the sole source of truth, at every step and again at the end.

**Why this shape**.  One measured fact: the oracle is the entire cost.  Each `fill_hole` judgment spawns a batch Agda process that spends about 2.6 s loading the standard library's interfaces before it checks anything (about 3.5 s averaged over the suite once the agda-algebras tier is included), while everything else the searcher does costs microseconds, and the server's interaction lane answers questions about a loaded file in 1–3 ms.  So the design optimizes one quantity, the number of batch judgments, and treats everything that can reduce it as nearly free: judgments are memoized, budgets are counted in judgments, and a millisecond `type_of` peek filters candidates before they cost one.  The same fact chose the host language: transport is 0.21 % of oracle time, so no rewrite of the client can matter, and the client lives in Scala beside the benchmark and corpus machinery.

**The defect designed out**.  The retired `search.py` carried a single goal per state and declared victory when *any* subgoal closed, so a lemma with two obligations counted as proved when one was discharged.  Here the state *is* the obligation set, "done" is emptiness of the whole set, and the only way to construct the `SolvedClaim` type is through a factory that demands both the empty set and the final green check.  A regression test pins exactly the two-obligation trap, both in isolation and against the live server.

### Where it stands

+  **P0** landed the state model, the oracle client, and the single-step harness, and measured the economics above.
+  **P1** landed the beam loop with a fixed, non-learned action space (the closers `refl` and `tt`, the goal context's assumptions, and applications of the lemmas the fixture imports) and measured the baseline on the standard-library tier: **6 of 22 obligations** (routine 6/7, compositional 0/10, non-obvious 0/5).  That is exactly the set whose gold proofs are single terms expressible from the fixture's imports, so the number is the term-mode ceiling of the suite, not a shortfall of the loop.  The `type_of` peek cut probes by 88 % and wall time by 4.5× with the same six solves.
+  **P2** landed retrieval over real corpora (the standard library, 55,576 rows; agda-algebras, 13,123 rows) behind the same proposer interface, and measured the honest result twice.  On the standard-library tier retrieval adds **zero** solves under target exclusion, because the ceiling binds any term-mode proposer, while the labeled control with exclusion off retrieves and commits all five admissible standard-library lemmas.  On the agda-algebras tier, built so that every gold is a single term, the fixed space solves 2 of 21, retrieval again adds zero under exclusion, and the control commits one wholesale-stratum lemma end to end; the ledgers locate the binding constraint in ranking at scale, not in the move vocabulary.  The suite-wide baseline is **8 of 43**, byte-stable across four reproductions.

### Where it goes

P3 replaces the deterministic ranker with a learned policy behind the existing policy-backend contract.  The stage-two ledgers are the quantitative demand for premise selection ([#19], [M2-5]), which slots into the scorer seam the retrieval proposer already exposes.  Two benchmark instruments sharpen attribution ([#129], [#142]).  Raising the ceiling itself needs case-split moves, which is deliberately outside P1–P3.

## 1.  Context: why proof search, and why now

(See also [#112] and [#113].)

The project's north star is AI agents that work effectively with Agda.  Retrieval and representation (`docs/PLAN.md` Phase 2) tell an agent *what might help*; proof search is the part that *does mathematics*: propose a step, submit it to the checker, iterate.  Its one prior implementation, `agda-dojang/python/tools/search.py`, had been dead since 2026-03-10 and was archived under [#112].

Three things had changed by mid-2026 ([#113]).  The oracle became native: `agda-mcp` exposes `fill_hole`, `get_goal`, and `check_file` directly and, since the [#68] hardening wave, answers scope, type, and definition questions from a persistent interaction lane ([#75], [#107], [#108]), which is precisely the information a proposer needs.  The corpus exists: `agda-strux` extraction plus `search_by_name` and `search_by_type` can supply candidate lemmas at scale.  And the measurement exists: `data/benchmarks/` is the suite, 43 obligations across two libraries with difficulty tiers, and the proof-completion evaluator already emits versioned JSONL (`eval-proof-completion.v0`), so search results sit beside the policy-backend baseline with no new apparatus.

Four lessons from [#112] are load-bearing and reappear as decisions below: report actions are peeks, not moves; partial application consumes visible binders only; there are two caches because the oracle is the cost center; and children are ordered by remaining obligations.  The fifth inheritance is the defect: the old search was disjunctive where obligations are conjunctive.

## 2.  The oracle and its economics

(See also [#119], PR [#121], and [`agda-mcp/agda-mcp-interaction-lane.md`].)

**Decision**.  The searcher drives `agda-mcp` as a client over its public tool contract, from Scala in `strux-driver`; verdicts come only from the batch lane, knowledge only from the interaction lane, and the boundary is absolute.

+  **Batch lane, verdicts**.  `check_file` and `fill_hole` derive success from a one-shot `agda` process's exit code.  This lane is the only judge: probe outcomes, commits, and the final claim all come from it.
+  **Interaction lane, knowledge**.  A persistent `agda --interaction-json` child answers `get_goal` and `type_of` about a loaded file in milliseconds.  Knowledge informs proposals and pre-filters; it never decides anything.
+  **Consequences, all of them code**.  The budget is denominated in batch judgments; judgments are memoized; knowledge calls are unbudgeted but ledgered; and any pre-filter cheaper than a judgment that rejects even a small fraction of candidates pays for itself.

**Evidence**.  P0's measurement ([#113], run `split-m15`, 180 oracle calls per pass over the 22 standard-library obligations): oracle calls are effectively 100 % of wall time and proposal is 2.3 ms in total; the `agda` subprocess is 99.79 % of oracle time and transport plus server handling 0.21 % (about 6 ms per call), which is all an in-process Haskell rewrite could ever recover; each batch call costs 2.6–2.9 s on standard-library fixtures, and the cost is per-spawn import loading rather than checking, since a builtins-only fixture answers in about 0.2 s.  P1 added the lane's side: switching the lane to a new file costs about 220 ms and a question about a loaded file 1–3 ms, two to three orders of magnitude below a judgment.  At the agda-algebras tier's prices a batch call averages 3.52 s against the flake-pinned library with prebuilt interfaces.

**Status**.  Adopted (P0).  The host-language fork the tracking issue posed is closed on evidence rather than taste.

## 3.  The state model

(See also PR [#121] and `Model.scala`.)

**Decision**.  A state is an obligation set, a working-copy content, and a script; solved means the whole set is empty and a final batch check passed; and the model makes the wrong reading unrepresentable rather than merely avoided.

+  **Conjunctive by construction**.  `SearchState(content, obligations, script)`; there is no per-goal success anywhere in the model.
+  **Probes are not moves**.  `fill_hole` restores the file server-side, so every probe is a peek; `ProbeOutcome` (what the oracle said) and `Move` (an action committed to the working copy) are distinct types, and the script has type `Vector[Move]`.
+  **States are unforgeable**.  `SearchState` and `SolvedClaim` are `sealed abstract case class`es with private constructors (the Scala 2 idiom that suppresses the synthetic `apply` and `copy`), so a state is born only through `initial` or `commit`, and a claim only through `fromFinalCheck`, which refuses an inhabited obligation set, a failed check, and internally inconsistent evidence (success reported beside a non-zero exit).
+  **The obligation set is the oracle's, not ours**.  Every `fill_hole` response carries the re-anchored hole list describing the file as that candidate would leave it (issue [#79]); `commit` adopts that list wholesale, so client-side hole arithmetic can never drift from Agda's.
+  **Two caches, two key types**.  `OracleKey(contentFingerprint, line, col, candidate)` memoizes judgments; `StateKey(contentFingerprint, script)` identifies states for frontier dedup.  Conflating them either re-runs Agda or wrongly prunes the frontier ([#112]'s lesson), so they are distinct case classes; the memo is scoped to one fixture's search, the timing ledger to the run.
+  **Strict wire decoders**.  The response fields the search acts on (`holes`, counts, `elapsedMs`, `context`) are required, and counts are cross-checked against lists, so a drifted server shape fails the decode visibly instead of bending ranking or measurement.  Every decoder is pinned against responses captured verbatim from the live server.
+  **Splice columns are codepoints**.  Agda counts columns in codepoints and Scala strings index UTF-16 units; on lines carrying astral-plane glyphs (`𝑨`, `𝒾𝒹`, everywhere in agda-algebras and nowhere in the standard-library tier) a naive index refused commits or spliced at a shifted offset.  Found and fixed by the agda-algebras tier ([#127]).

**Evidence**.  `ModelSpec` pins the two-obligation regression, the probe/move separation, the splice, the key types, and the ranking; `SingleStepIntegrationSpec` and `LoopIntegrationSpec` pin the trap against the live server, where every intermediate `fill_hole` answers `ok` and the state still refuses the claim; `WireSpec` pins the decoders on the live captures under `src/test/resources/search/`.

**Status**.  Adopted (P0); the codepoint fix landed with PR [#132].

## 4.  The loop

(See also [#122], PR [#126], and `BeamLoop.scala`.)

**Decision**.  Level-synchronous beam search over states, with a budget counted in probes, three distinct termination statuses, and anomalies that redden a run without stopping it.

+  **Expansion**.  Each frontier state is expanded at its *first open obligation*, a fixed selection policy stated and pinned as a deliberate simplification: because the set is conjunctive and every commit re-anchors from the oracle, selection order affects which proofs are found under budget, never whether a found proof is real.  Expansion writes the state's content to the working file, reads the goal, asks the proposer for candidates, peeks each unless it is a closer, and probes the survivors.
+  **Children and the beam**.  Ok probes commit to children; children are deduped against every state ever enqueued, ranked with fewer remaining obligations first, and the best `beamWidth` become the next level.  A probe that closes every obligation is claimed immediately through the final batch gate, since search work after a proof would be budget spent for nothing.
+  **Termination** is a distinct per-fixture status: `solved` (the claim was granted), `exhausted` (the frontier emptied, or the depth bound cut a live frontier, and the outcome says which), or `budget_exceeded` (the probe budget ran out with work remaining).  The distinction is what lets a measurement say "no term-mode proof exists within depth 6" rather than "we stopped".
+  **The budget** counts `fill_hole` probes that miss the memo.  Memo hits are free and stay free at the cap, because the loop consults the memo before the budget gate.  The baseline `check_file`, the final strict checks, and the knowledge calls are ledgered but not gated; they are bounded structurally (one `get_goal` per expansion, expansions at most beam × depth, final checks at most closing probes).
+  **Dedup keys on content plus script**.  Content-only dedup would merge two histories that reach one content, which is safe in principle; the conservative key can never wrongly prune two live states, and measurement found the two identical (§ 9).
+  **Defaults**: beam 4, depth 6, budget 60, dedup by script, peek on; all tunable on the Make target.
+  **Anomalies are loud and non-fatal**.  A commit the state refuses, a wire drift, or a closing probe whose final check disagrees raises out of that fixture; the sweep continues, every artifact is written (an anomalous fixture keeps its attempt rows, wall clock, and probe counts), and the run exits non-zero.  This is inherited from [#112]'s own failure mode: a harness that exits 0 while writing broken rows lets breakage sit silent for months.

**Evidence**.  `BeamLoopSpec` pins the multi-obligation solve, first-open-obligation order, the budget semantics including a memo hit served at the cap, frontier exhaustion, the depth cap, both dedup policies and the adopted default, and that a beam-cut child does not poison a later path to the same state; `LoopHarnessSpec` pins what an anomalous fixture keeps.  The dedup A/B was measured on the standard-library tier at P1 and re-measured at P2 with hole-free compound candidates present, the stated trigger: identical sweeps both times, zero skips under either key.

**Status**.  Adopted (P1); the dedup decision re-confirmed (P2).

## 5.  The action space and the proposer seam

(See also [#122], PR [#126], and `Propose.scala`.)

**Decision**.  Proposals go through one interface, `Proposer.propose(state, target, goal)`, which every phase plugs into; P1's implementation is fixed and non-learned, and the ceiling it implies is stated beside every number it produces.

+  **The fixed space**, in proposal order: the closers `refl` and `tt`; the goal context's assumptions by name; and applications of every name the fixture imports through `using` lists, one `{!!}` per remaining visible binder, ordered cheap-before-expensive because the budget can run out mid-expansion.  Binder counts come from lane `type_of` answers through a deliberately small pi-type splitter (arrows at bracket depth 0).
+  **Applications are parenthesized**, `(s≤s {!!})`, because a hole is an argument position as often as a right-hand side, and a verbatim splice of `s≤s {!!}` into a sub-hole reads as `s≤s sym {!!}`, a different term.  The first P1 sweep measured every depth-1 application dying exactly this way.
+  **The splitter is a proposal device, not an authority**.  It reads printed types well enough to count visible binders; the oracle polices what it gets wrong, since an overcount is refused as a type error and an undercount leaves a partial application the goal must then accept.
+  **The term-mode ceiling**.  No case splits and no `with` means clause-restructuring golds are unreachable by any proposer.  On the standard-library tier that is 16 of 22 (13 two-clause inductions, 2 case splits, and one `≡-Reasoning` chain whose imports the obligation lacks); the six with expressible single-term golds are exactly the six solves.  The agda-algebras tier ([#127]) was mined for single-term golds so that this ceiling cannot bind it (21 of 21 are term-expressible by construction), which moves the whole gap onto the action space: its `using` stratum is reachable by the fixed space in principle, and its wholesale stratum is starved of `using` lists by design, so that uplift there is attributable to retrieval and nothing else.

**Evidence**.  `ProposeSpec` pins the imports parser, the splitter on live-captured renderings, the proposal order, and the lane-rejection rule; the P1 baseline in § 9 saturates the ceiling exactly.

**Status**.  Adopted (P1); the seam survived P2 unchanged.

## 6.  The `type_of` peek

(See also [#122], [#127], and `Propose.scala`.)

**Decision**.  Before spending a judgment on a candidate, ask the interaction lane to infer its type at the goal with `_` in place of each hole, and skip the judgment when the answer cannot fit.  A peek only ever skips a probe, never substitutes for one; any failure to peek keeps the candidate; and the two closers are exempt.

+  **What the wire established**.  Under-determined metas are answered, not errored (`sym _` infers `_y_8 ≡ _x_7`), and bad expressions come back as in-body errors (`NotInScope`, `CannotApply`, `UnequalTerms`) in 1–3 ms.  The filter rejects on a lane error, or when the inferred type cannot textually match the goal display with every meta read as a wildcard and the same meta as the same wildcard, so `refl`'s `_x_9 ≡ _x_9` is rejected at `m + n ≡ n + m` and kept at `n ≡ n`.
+  **One canonicalization**.  Agda folds closed naturals to numerals in goal displays (`1 ≤ suc n`) but a meta blocks the folding in inferred types (`suc _m_5 ≤ suc _n_6`), so small numerals are expanded to `suc` towers before comparison; without it the peek falsely rejects `(s≤s {!!})` and costs a solve.
+  **Default and exemption**.  Opt-in through P1; default ON since P2 re-validated it on retrieval candidates.  The closers are exempt since [#127]: on agda-algebras goals whose two sides are definitionally equal but textually distinct (`lift ∘ lower ≡ 𝑖𝑑 (Lift b A)` closes by `refl`) the textual test rejects a correct closer, and a closer's probe costs no more than its peek.  Only the closers: exempting every hole-free candidate re-probed the context assumptions at every expansion and gave the peek's entire savings back.

**Evidence**.  P1, the same six solves with byte-identical scripts: probes 435 → 50 (−88.5 %), batch oracle time 1227 s → 209 s, wall 21.5 min → 4.7 min (4.5×), probe precision 6.7 % → 70 %, and the budget-burners converted to honest depth-capped exhaustion (plus-comm from 60 probes to 6).  P2, post-review: two budget-ordering losses recovered (4/22 → 6/22), 3,734 of 4,262 judgments skipped, zero solves lost.  The agda-algebras tier: the P1 policy lost `lift∼lower` (1/21 against the peek-off control's 2/21); with the closers exempt the peek keeps 2/21 at a 5.5× probe and 3.9× wall advantage over the control (119 probes and 745 s against 651 and 2,911 s), while exempting all hole-free candidates measured 833 probes and 3,086 s, within noise of no peek at all.

**Status**.  Adopted (P1); default flipped (P2); closers exempt (PR [#132]).

## 7.  Retrieval proposals

(See also [#123], PR [#130], `Retrieve.scala`, and § 6.2 of [`proof-search/overview.md`].)

**Decision**.  Retrieval widens *what* is proposed, not how anything is judged: a `RetrievalProposer` behind the same seam, composed around the fixed space, whose candidate pool is scoped to what the fixture can name, purged of the answer key, ranked by a replaceable scorer, and rendered into three candidate shapes.

+  **Composition**.  The fixed space stays (it carries the constructors the corpus does not row), so the P2 space is a superset of P1's by construction and any measured delta is attributable to retrieval.
+  **Scope**.  A candidate must resolve in the fixture's module, and `open import M using (xs)` still grants qualified access to all of `M` (verified against the pinned toolchain), so the legal pool is every corpus row whose module the fixture imports or whose module extends an imported one at a dot boundary.  A whole-module `open import M` enters the scope with no lemma names, which is what the wholesale stratum depends on.  Renderings walk a ladder (bare when `using`-listed, the row's qualified name, the importing module qualifying the bare name) and the lane arbitrates: the first rendering `type_of` can type wins, a name the lane cannot type stays out, and the cut to the top eight lemmas is taken after resolution, so a rejected rendering does not consume a slot.  Widening a fixture's import surface (committing `import` lines as moves) is out of scope: a new move vocabulary, and a change to what the benchmark states.
+  **Target exclusion**.  Every standard-library obligation *is* a standard-library lemma, and a wholesale-stratum obligation opens the module holding its original, so the corpus contains the answers.  A row whose bare name equals the hole's name is excluded (record-field projections of the target included), and so is a row whose statement normalizes to the target's, compared on the lane's own printing of both; a differently stated but convertible lemma stays in, because using it is a real proof step.  Exclusions are named per fixture in `report.json`, and the policy has one labeled off switch, `--exclude-target off`, for the mechanism-control sweep only, so a null headline is distinguishable from broken machinery.
+  **Ranking** is deterministic and stated as the placeholder it is: token overlap between the goal display and the corpus type (corpus tokens reduced to bare segments), a name bonus capped at one, a penalty for operators the goal never mentions (without it the `+` goal ranks the `*`-and-`+` semiring bundles above the `+` lemmas), ties broken cheap-before-expensive on approximate arity and then on the name.  The scorer is its own interface, `CandidateScorer`; premise-selection scores replace it and nothing else moves.
+  **Three candidate shapes** per lemma: the hole-free `_`-form (`(+-comm _ _)`, one probe when unification solves the arguments), argument-saturated forms over the goal context's assumptions (every tuple, arity at most 3 and at most 27 tuples), and the `{!!}`-refinement form.  The saturated forms are forced by a wire fact this phase probed and pinned (captures `wire-fill-hole-blocked-{subholes,metas}.json`): `fill_hole` refuses a candidate whose sub-holes or metas carry blocked constraints, so `(+-comm {!!} {!!})` at `m + n ≡ n + m` is a `type_error`, and the alias-stated equational class can only ever be committed fully applied.  Binder counts still come from the lane, which expands alias types on qualified names (`Data.Nat.Properties.+-comm` infers `(x y : ℕ) → x + y ≡ y + x`); the corpus type string ranks, never counts.
+  **The honesty ledger**.  Every cut is counted and every exclusion named, per fixture, in `report.json`, so the report alone distinguishes a gamed run from a fair one.

**Evidence**.  `RetrieveSpec`, on a canned corpus of real extraction rows, pins scope, both exclusion rules and the off switch, ranking determinism and each shakedown lesson, the rendering ladder, the shapes and their bounds, the post-resolution cut, and the ledger; `RetrievalIntegrationSpec` drives the real server with `--corpus`.  The two review rounds on PR [#130] found three defects that had shaped the first published sweeps (the top-eight cut fell before lane resolution, whole-module imports never entered the scope, and the statement exclusion compared notations that never agree on real data); all three are fixed and pinned, and § 9 quotes the re-measured record.

**Status**.  Adopted (P2); [#123] closed with the stage-two measurement.

## 8.  Reporting: one schema for every phase

(See also `LoopHarness.scala` and § 8 of [`proof-search/overview.md`].)

**Decision**.  Every run writes the shared evaluation schema, so search results sit beside the policy-backend evaluator's with no private format.  A run directory holds the following.

| file | one row or entry per | contents |
|---|---|---|
| `results.jsonl` | judged candidate | an `eval-proof-completion.v0` attempt row: `fixtureId`, `benchmarkId`, the hole's position, `candidateRank`, `candidate`, `status` in `fill_hole`'s own vocabulary, `rc`, the client-observed `elapsedMs`, `logPath` |
| `fixtures.jsonl` | fixture | the `eval-proof-completion.v0` summary row (`holesTotal`, `holesSolved`, `fullySolved`, `solvedPath`) plus the additive `searchStatus` |
| `timing.jsonl` | oracle call, and one per proposal | the `proof-search-timing.v0` ledger: `phase`, `clientMs`, `serverElapsedMs`, `overheadMs`, `checkedFromSource`, `cached` |
| `report.json` | run | the config, the corpus provenance for retrieval runs, per-tier solve counts, the batch/knowledge/retrieval/proposal split, and per-fixture outcomes with scripts, counters, and the retrieval honesty ledger |
| `solved/` | solved fixture | the typecheckable module with the proof spliced in |

Two ledger conventions keep the split honest: a memo hit is a row with `cached: true` and no server time, so saved calls never count as oracle time; and a proposal row carries the proposer's own time with any oracle calls it made through the seam subtracted, since the ledger already holds those.

**Evidence**.  [#113]'s acceptance ("no private formats"); the rows are consumed by the existing ETL unchanged.

**Status**.  Adopted (P0/P1); the `retrieval` phase and the provenance block added at P2.

## 9.  Where it stands: the numbers

Every sweep below used the same knobs (beam 4, depth 6, probe budget 60, dedup by script), ran serially against one server on an otherwise quiet machine, and reported zero anomalies; run identifiers and the full tables are in [#113]'s comments.

**P0** ([#113], the measurement that settled the fork).  180 oracle calls per pass at 2.6–2.9 s each; 99.79 % of oracle time in the `agda` subprocess, 0.21 % transport; proposal 2.3 ms in total; 4 of 22 solved by the six-candidate stub.

**P1** ([#122], PR [#126]; the standard-library tier).

| configuration | solved | probes | wall |
|---|---|---|---|
| baseline (dedup by script, no peek) | 6/22: routine 6/7, compositional 0/10, non-obvious 0/5 | 435 | 21.5 min |
| dedup content-only, no peek | identical to the baseline, per fixture | 435 | 21.6 min |
| dedup by script, peek on | 6/22, byte-identical scripts | 50 | 4.7 min |

The six proofs: `refl` three times, `tt` once, `(_,_ {!!} {!!}) ; a ; b` at depth 2, and `(s≤s {!!}) ; z≤n` at depth 1; the last two are what the loop adds over P0's single step.  Four fixtures exhausted the budget without the peek, all of them chains that refine forever without progress (`sym`-flipping on plus-comm, mul-comm, and mul-distrib-r; `id`-wrapping on list-map-id); with the peek they become honest depth-capped exhaustion.  Decisions taken from these numbers: dedup stays script-inclusive; the peek is a validated cost lever; and the baseline every later phase must beat is 6/22.

**The 43-obligation suite** ([#127], PR [#132]; the fixed space with the peek on and the closers exempt; run `run-127-repin-full-peek-on-1`, byte-stable across four reproductions).

| library and tier | solved | probes | wall |
|---|---|---|---|
| stdlib routine | 6/7 | 22 | 116 s |
| stdlib compositional | 0/10 | 65 | 239 s |
| stdlib non-obvious | 0/5 | 50 | 173 s |
| agda-algebras routine | 2/6 | 11 | 73 s |
| agda-algebras compositional | 0/10 | 43 | 293 s |
| agda-algebras non-obvious | 0/5 | 65 | 402 s |

8/43 in 21 m 39 s: the stdlib rows reproduce the P1 baseline exactly, and the two agda-algebras solves (`lift∼lower`, `lower∼lift`) are `refl` in one probe each.  By stratum, `using` 2/11 and `wholesale` 0/10, the wholesale zero being the intended control surface for retrieval.  Economics at this pin: 307 batch calls in 1,080.7 s (3.52 s average), 1,411 knowledge calls in 214.1 s, and 1,039 peeks skipping 946 probes.

**P2, stage one** ([#123], PR [#130]; the standard-library tier, retrieval composed around the fixed space, top eight lemmas per goal, exclusion on unless stated).  Measured twice: at the initial code, and re-measured after the review fixes changed the real pool composition.  The table is the post-fix record (runs `p2fix-{a,b,c,d}`); those wall clocks ran on a loaded machine, so probe counts are the comparable column.

| configuration | solved | probes |
|---|---|---|
| A: retrieval, no peek | 4/22, the P1 set minus prod-mk-pair and zero-lt-suc (17 of 22 fixtures exhaust the budget against full eight-lemma pools) | 1,064 |
| B: retrieval, peek on | **6/22, the P1 set with identical scripts** | 526 |
| C: A with content-only dedup | identical to A, probe for probe; zero skips either way | 1,064 |
| D: A with exclusion off (the labeled control) | 9/22, A's four plus all five admissible targets, each a one-shot saturated application | 943 |

The reading: **the suite's term-mode ceiling binds any term-mode proposer**.  Retrieval widened the legal pool from `using`-list handfuls to thousands of in-scope rows (plus-comm alone draws 22,610 raw hits and 4,012 in-scope rows) and still adds zero solves under exclusion, while the control commits every needle the exclusion had removed, in both measurement rounds.  The oracle-dominance split holds at this scale: on sweep A, batch oracle 3,019 s against retrieval 7.9 s plus knowledge 66.5 s.

**P2, stage two** ([#123]; the whole suite with the agda-algebras v0.1 corpus, digest-verified; runs `p2s2-{a,b,c}`, 2026-09-08).

| sweep | stdlib | agda-algebras `using` | agda-algebras `wholesale` | total |
|---|---|---|---|---|
| A: retrieval, peek on, exclusion on | 6/22 (137 probes) | 2/11 | 0/10 | 8/43 |
| B: fixed space (the attribution control) | 6/22 (137 probes) | 2/11 | 0/10 | 8/43 |
| C: retrieval, exclusion off (the labeled control) | 6/22 (137 probes) | 2/11 | 1/10 | 9/43 |

Three findings.  The mechanism is proven on this corpus: the control's one new solve is a wholesale needle committed end to end, `algebras-inverses-range-to-image` closed by `(Setoid.Functions.IsInRange→IsInImage w)`, retrieved from a 79-row in-scope pool, ranked in the top three, rendered through the qualified rung of the ladder, saturated with the context assumption, and committed in five probes.  Zero uplift under exclusion, and this time the binding constraint is measured to be ranking at scale rather than the move vocabulary: wholesale opens flood the legal pools (up to 24,566 raw hits and 3,025 in-scope rows on one fixture, against `using`-stratum pools of 16–79), the token-overlap ranker drowns the targets under the library's generic projections (`Overture.ℓ₁`, `∣_∣`, `∥_∥`, `𝑖𝑑`), and eight fixtures burn the full budget on ranked-but-wrong candidates.  And the measurement existed at all because of the review round: every wholesale pool flows through the whole-module scope fix, without which this sweep would have reported a false zero.

## 10.  Where it is going

+  **Premise selection** ([#19], [M2-5]).  The `CandidateScorer` seam inside the retrieval proposer now has a measured reason to exist: token overlap fails at 3,000-row pools where the needles are in scope.  Two cheap knob experiments are recorded as options before any learned model: a retrieve-k above eight, and a larger probe budget on wholesale rows.
+  **P3, policy proposals** ([#124]).  A learned policy behind the existing contract (`policy_contract.py`, mirrored by `AgdaMCP.Types`; `policy_fixture.py` as the deterministic stand-in), compared against policy-alone top-k and both earlier baselines: the closed propose, check, and learn loop the project has been building toward.
+  **Benchmark instruments** ([#129], [#142]).  Obligations whose single-term golds require a non-`using`-listed, non-target lemma from an imported haystack, and style-paired obligations, so retrieval's ranking value becomes measurable without gaming.
+  **Raising the ceiling** (unscheduled, the largest known win).  Term mode caps the standard-library tier at 6/22, and 13 of the 16 unreachable golds are structural inductions of a single shape (`f zero … = refl; f (suc n) … = cong g (f n …)`).  Reaching them needs case-split moves, plausibly via the interaction protocol's `Cmd_make_case`, which changes the state model's move vocabulary and is deliberately outside P1–P3.
+  **Recorded options, taken only if measurement demands**: parallel oracle workers (N servers over disjoint work copies) if wall time becomes the bottleneck; richer selection policies than first-open-obligation if multi-hole fixtures ever make selection order matter under budget.

## 11.  Decision log

| # | Decision | Status | Evidence |
|---|---|---|---|
| 1 | Obligation sets are conjunctive; `SolvedClaim` requires the empty set AND a final green batch check | Adopted (P0) | [#112] post-mortem; `ModelSpec`, live in `SingleStepIntegrationSpec` and `LoopIntegrationSpec` |
| 2 | The client lives in Scala (`strux-driver`), driving `agda-mcp` over its public contract; no in-process Haskell rewrite | Adopted (P0) | Transport is 0.21 % of oracle time ([#113]) |
| 3 | Budgets are denominated in batch judgments, not seconds | Adopted (P1) | A batch call's import loading dominates all else ([#113]) |
| 4 | Judgments memoized on `OracleKey`, scoped per fixture; hits free, including at the budget cap | Adopted (P1) | `OracleMemoSpec`; `BeamLoopSpec` cap test |
| 5 | Frontier dedup keys on content plus script | Adopted (P1); re-measured with hole-free compounds present (P2): stands | Both A/Bs identical, zero skips either way; `BeamLoopSpec` |
| 6 | First-open-obligation selection | Adopted (P1), a stated simplification | Sound under conjunctive re-anchoring; `BeamLoopSpec` |
| 7 | Application candidates parenthesized | Adopted (P1) | First sweep: every depth-1 application died unparenthesized |
| 8 | The `type_of` peek informs only, never decides; default ON since P2; the two closers exempt since the agda-algebras tier | Adopted (P1); default flipped (P2); exemption ([#127]) | P1: −88.5 % probes at zero solve cost; P2: two losses recovered; [#127]: `lift∼lower` |
| 9 | Anomalies never abort a sweep, always redden the run, and keep their diagnostics | Adopted (P0/P1) | [#112]'s silent-breakage failure mode; `LoopHarnessSpec` |
| 10 | All reporting on `eval-proof-completion.v0` beside the policy baseline | Adopted (P0/P1) | [#113] acceptance: no private formats |
| 11 | Retrieval is composed around the fixed space, so the P2 space is a superset of P1's | Adopted (P2) | Stage-one sweep B reproduces P1's solve set and scripts |
| 12 | Retrieval scope is the fixture's imported modules with qualified access, lane-arbitrated; import-widening is out of scope | Adopted (P2) | Qualified access toolchain-verified; whole-module imports enter the scope (PR [#130] review); `RetrieveSpec` |
| 13 | Target exclusion by name and lane-form statement, named per fixture, with a labeled off switch for the control only | Adopted (P2) | The control commits all five stdlib targets in both rounds and the wholesale needle on agda-algebras; `RetrieveSpec` |
| 14 | Three candidate shapes: `_`-form, bounded saturation over the context, `{!!}`-refinement | Adopted (P2) | `fill_hole` refuses blocked-constraint sub-holes (captures `wire-fill-hole-blocked-*`); the control solves are saturated one-shots |
| 15 | The scorer is a seam; token overlap is the placeholder, premise selection the replacement | Adopted (P2); the demand now measured | Stage two: needles in scope, drowned at 3,000-row pools ([#19]) |
| 16 | Splice columns are codepoints, never UTF-16 units | Adopted ([#127]) | `ModelSpec` regression; astral glyphs throughout agda-algebras |

## References

+  **Issues**: [#112] (the post-mortem), [#113] (tracking; every measurement in its comments), [#119], [#122], [#123], and [#124] (the phases), [#127], [#129], and [#142] (the benchmark instruments), [#19] (premise selection), [#68], [#75], [#107], and [#108] (the server substrate), [#79] (re-anchored hole lists).
+  **PRs**: [#121] (P0), [#126] (P1), [#130] (P2), [#132] (the agda-algebras tier, with the codepoint and peek fixes).
+  **Docs**: [`proof-search/overview.md`] (how the search works, with a worked example, and the vocabulary), [`agda-mcp/agda-mcp-interaction-lane.md`] (the two-lane policy and the lane protocol), [`agda-mcp/README.md`] (tool contracts), [`data/benchmarks/README.md`] and [`benchmarks/taxonomy.md`] (the suite and its tiers), [`agda-dojang/README.md`] (the result schema), [`corpora/agda-stdlib-v0.md`] and [`corpora/agda-algebras-v0.1.md`] (the corpora).
+  **Code map** (`strux-driver/src/main/scala/struxdriver/search/`): `Model.scala` (state, claims, keys, splice), `Wire.scala` (strict decoders), `McpClient.scala` (transport), `Oracle.scala` (timed, memoized calls, the ledger), `Actions.scala` (application arithmetic, pi splitter), `Propose.scala` (proposer seam, fixed space, peek), `Retrieve.scala` (the retrieval proposer, scorer seam, exclusion), `BeamLoop.scala` (the loop), `Scaffold.scala` (shared fixture scaffolding), `SingleStepHarness.scala` (P0 entry), `LoopHarness.scala` (P1 and P2 entry); tests beside them in `src/test/scala/struxdriver/search/`, wire captures in `src/test/resources/search/`.

<!-- GitHub references: one definition per issue or PR cited above; PRs resolve to /pull/, issues to /issues/. -->
[#19]: https://github.com/formalverification/agda-native-air/issues/19
[#68]: https://github.com/formalverification/agda-native-air/issues/68
[#75]: https://github.com/formalverification/agda-native-air/issues/75
[#79]: https://github.com/formalverification/agda-native-air/issues/79
[#107]: https://github.com/formalverification/agda-native-air/pull/107
[#108]: https://github.com/formalverification/agda-native-air/issues/108
[#112]: https://github.com/formalverification/agda-native-air/issues/112
[#113]: https://github.com/formalverification/agda-native-air/issues/113
[#119]: https://github.com/formalverification/agda-native-air/issues/119
[#121]: https://github.com/formalverification/agda-native-air/pull/121
[#122]: https://github.com/formalverification/agda-native-air/issues/122
[#123]: https://github.com/formalverification/agda-native-air/issues/123
[#124]: https://github.com/formalverification/agda-native-air/issues/124
[#126]: https://github.com/formalverification/agda-native-air/pull/126
[#127]: https://github.com/formalverification/agda-native-air/issues/127
[#129]: https://github.com/formalverification/agda-native-air/issues/129
[#130]: https://github.com/formalverification/agda-native-air/pull/130
[#132]: https://github.com/formalverification/agda-native-air/pull/132
[#142]: https://github.com/formalverification/agda-native-air/issues/142

[`proof-search/overview.md`]: ../proof-search/overview.md
[`agda-mcp/agda-mcp-interaction-lane.md`]: ../agda-mcp/agda-mcp-interaction-lane.md
[`agda-mcp/README.md`]: ../../agda-mcp/README.md
[`data/benchmarks/README.md`]: ../../data/benchmarks/README.md
[`benchmarks/taxonomy.md`]: ../benchmarks/taxonomy.md
[`agda-dojang/README.md`]: ../../agda-dojang/README.md
[`corpora/agda-stdlib-v0.md`]: ../corpora/agda-stdlib-v0.md
[`corpora/agda-algebras-v0.1.md`]: ../corpora/agda-algebras-v0.1.md
