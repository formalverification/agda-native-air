<!-- File: docs/proof-search/overview.md -->

# Proof search on agda-mcp: an overview

This note explains the proof-search component of `agda-native-air` for a collaborator who knows Agda and wants to understand what the search is, how it works, how to run it, and how to read what it writes.  It is the explanatory companion to [ADR 0001](../adr/0001-proof-search-on-agda-mcp.md), which records the design decisions and the measurements that earned them; this note repeats neither the decision log nor the numbers, and points there for both.  The code lives in `strux-driver/src/main/scala/struxdriver/search/`, and every file there opens with a header comment that says what it is for and how it fits.

## 1.  What it is

A theorem with a hole in its proof is a proof obligation.  The searcher takes an Agda module with one such hole, proposes candidate terms for the hole, asks Agda whether each candidate typechecks, keeps the ones that do, and repeats on whatever holes those candidates leave behind, until the module has no holes left and Agda accepts the whole file.  Agda is the only judge: the searcher never decides on its own that a candidate is right, and it never trusts its own bookkeeping over what the checker reports.

The searcher talks to Agda through the `agda-mcp` server ([ADR 0002](../adr/0002-agda-mcp.md)) as any other client would: it spawns the server over stdio and calls the same tools an interactive agent calls (`check_file`, `get_goal`, `fill_hole`, `type_of`, and the corpus search tools).  It is written in Scala, in the `strux-driver` subproject, beside the benchmark runner it is scored with.

It is scored on the repository's benchmark suite (`data/benchmarks/`): 55 obligations with committed gold solutions, 34 from the Agda standard library (the frozen tier of 22 and the haystack tier of 12) and 21 from agda-algebras, each tagged with a difficulty tier.  Every run writes its results in the same JSON Lines schema the project's other evaluators use, so a search result can sit in a table beside a language model's.

## 2.  Vocabulary

The rest of this note, and the ADR, use the following terms with the following meanings.

+  **Obligation**.  One open hole in the working copy: its position (line and column, as Agda reports them) and the goal type Agda printed for it.  A module starts with one obligation; filling a hole with a term that itself contains holes replaces the one obligation with several.
+  **Candidate**.  A term the searcher proposes for an obligation, as text: `refl`, `n`, `(s≤s {!!})`, `(Data.Nat.Properties.+-comm m n)`.  A candidate may contain fresh holes, written `{!!}`.
+  **Probe**.  Asking Agda whether a candidate typechecks at an obligation, through `fill_hole`.  The server splices the candidate into the file, runs a batch `agda` over it, reports the result, and restores the file, so a probe changes nothing; it is a question.  Its answer is `ok` (the candidate typechecks, possibly leaving new holes), `type_error`, `timeout`, or `crash`.
+  **Judgment**.  A probe's answer.  Each one costs a batch run of `agda`, which is the search's only real expense (§ 4).
+  **Move**, or **commit**.  Adopting an `ok` candidate: the searcher splices it into its own working copy of the file and takes the hole list the server returned with the answer as the new set of obligations.  A probe is not a move; the searcher can probe ten candidates and commit one.
+  **Script**.  The sequence of moves that led to a state.  Peeks and probes never enter it.
+  **State**.  The working copy's content, the obligations still open in it, and the script that produced it.  A state is solved only when its obligation set is empty *and* a final whole-file `check_file` on its content comes back green.
+  **Working copy**.  Each obligation is copied into a per-run directory before anything touches it, so a crash can never dirty a committed benchmark file.  The searcher rewrites its working copy to a state's content before probing that state.
+  **The oracle**.  The searcher's name for `agda-mcp` as a source of answers.  It has two lanes, in the server's own vocabulary: the *batch lane* (`check_file`, `fill_hole`), which spawns a fresh `agda` per call and whose verdict is that process's exit code, and the *interaction lane* (`get_goal`, `type_of`), a persistent `agda --interaction-json` process that answers questions about a loaded file in milliseconds but never decides a verdict.
+  **Proposer**.  The component that produces candidates for one obligation of one state.  It is an interface (`Proposer` in `Propose.scala`) with three implementations planned and two landed: the *fixed space* (P1) and *retrieval* (P2); a learned *policy* (P3) is direction.
+  **Action space**.  What a proposer can propose.  The fixed space is three kinds of candidate, in this order: the *closers* `refl` and `tt`; the *assumptions* in the goal's local context, by name; and *applications* of every lemma the fixture imports through a `using` list, each with one `{!!}` per visible argument the lemma still needs.
+  **Binders**.  The arguments a lemma takes, read off its type as the interaction lane prints it: `(x y : ℕ) → x + y ≡ y + x` has two visible binders.  Hidden (`{x : A}`) and instance (`⦃ x : A ⦄`) binders are neither supplied nor given holes; Agda infers them or rejects the candidate.
+  **Frontier**, **beam**, **depth**.  The search is a beam search.  A *level* is the set of states reached by the same number of moves; expanding a level probes candidates at each of its states; of the resulting children, only the best *beam width* (default 4) survive to form the next level, the *frontier*; and no level beyond the *depth bound* (default 6) is expanded.
+  **Budget**.  The number of probes a fixture may spend (default 60).  Only probes that actually run `agda` count; answers replayed from the memo are free.
+  **Memo**.  A cache of judgments keyed by the content of the working copy, the hole position, and the candidate.  The same question is never asked of `agda` twice within one fixture's search.
+  **Dedup**.  A second cache, of states: a child whose state has been enqueued before is dropped rather than expanded again.  Keyed by content plus script (the ADR records why the script is included).
+  **Peek**.  Before spending a probe on a candidate, the searcher may ask the interaction lane to infer the candidate's type at the goal, with each `{!!}` replaced by `_`, and skip the probe when the inferred type cannot fit the goal.  A peek can only ever skip a probe; it never decides anything, and if the lane fails the candidate is probed anyway.
+  **Term mode**.  The searcher fills holes with terms and nothing else: it cannot split a definition into cases, add a `with` clause, or restructure the clause it is working in.  A gold proof that needs any of those is out of reach whatever the proposer, and that boundary is the *term-mode ceiling*.
+  **Tier** and **stratum**.  Each benchmark obligation carries a difficulty tier from `docs/benchmarks/taxonomy.md`: *routine* (the term is essentially determined by the goal type and the immediate context), *compositional* (two to five known lemmas or standard steps have to be composed), or *non-obvious* (lemmas from outside the immediate context, or an idea).  The agda-algebras obligations additionally carry an import *stratum*: `using` (the fixture imports its lemmas through narrow `using` lists, which the fixed space can read) or `wholesale` (it opens modules with no `using` list, which starves the fixed space on purpose so that any solve there is attributable to retrieval).  The standard-library haystack tier (Issue [#129]) carries a third stratum, `haystack`: the fixture opens a `Properties` module with a narrow `using` list of decoys, and the one lemma its gold applies is reachable only by qualified name, so a solve there is a needle found in the imported module.  A run report groups its outcomes by stratum (`perStratum`) as well as by difficulty.
+  **Corpus**.  A JSON Lines extraction of a whole library by `agda-strux`, one row per definition with its qualified name, printed type, module, and dependencies; `agda-mcp --corpus` loads one and serves `search_by_name`, `search_by_type`, and `get_dependencies` over it.  Two are published: the standard library (55,576 rows, `docs/corpora/agda-stdlib-v0.md`) and agda-algebras (13,123 rows, `docs/corpora/agda-algebras-v0.1.md`).

## 3.  The loop, on a real obligation

`stdlib-nat-zero-lt-suc` is a routine obligation from the standard-library tier.  Its module imports `Data.Nat.Base using ( ℕ ; zero ; suc ; _<_ ; _≤_ ; z≤n ; s≤s )` and states the following.

```agda
0<1+n : ∀ {n : ℕ} → 0 < suc n
0<1+n = {!!}
```

The gold solution is `s≤s z≤n`, and the loop finds it in two moves.  What happens, step by step, is the following.

1.  **Stage**.  The obligation file is copied to the run's `work/` directory and `check_file` is called on the copy.  The response's hole list has exactly one entry, at the position of `{!!}`; that entry is the initial state's one obligation.  (A fixture presenting any other number of holes is an anomaly, reported and skipped.)
2.  **Expand the root**.  The loop writes the state's content to the working copy and calls `get_goal` at the obligation.  The goal displays as `1 ≤ suc n` (Agda unfolds `0 < suc n` and folds `suc 0` to `1`), and the local context holds `n : ℕ`.
3.  **Propose**.  The fixed proposer returns, in order: the closers `refl` and `tt`; the assumption `n`; then applications of the names in the `using` list whose type the lane can infer, cheapest first.  `z≤n` needs no visible argument, so it is proposed as itself; `s≤s` needs one, so it is proposed as `(s≤s {!!})`; the other names in the list (`ℕ`, `zero`, `suc`, `_<_`, `_≤_`) are proposed the same way, and the oracle sorts them out.
4.  **Peek**.  For each candidate other than the two closers, the loop asks `type_of` at the goal for the candidate with `_` in place of each hole.  `s≤s _` infers `suc _m ≤ suc _n`, which matches `1 ≤ suc n` once the searcher expands the numeral `1` to `suc 0`, so that candidate survives.  `n` infers `ℕ`, which cannot match, so its probe is skipped.  Each peek takes milliseconds.
5.  **Probe**.  Surviving candidates are sent to `fill_hole` in proposal order.  `refl` and `tt` are refused.  `(s≤s {!!})` answers `ok`, with a hole list containing one new hole, inside the parentheses, whose goal displays as `0 ≤ n`.
6.  **Commit and rank**.  The `ok` probe becomes a move: the candidate is spliced into the working copy, and the new hole list becomes the child state's obligations.  Children are ranked with fewer remaining obligations first, and the best four form the next level.  Here there is one child.
7.  **Expand the child**.  The same steps at the new obligation.  `z≤n` survives its peek and answers `ok` with an empty hole list.
8.  **Claim**.  A probe that leaves no obligation is not yet a proof.  The loop writes the child's content, runs a final `check_file` on the whole file, and only if that returns success with exit code 0 does it construct the `SolvedClaim` that the report counts as `solved`.  The solved file is copied to the run's `solved/` directory, and its script is `(s≤s {!!}) ; z≤n`.

Three things in that walk-through are the whole design in miniature.  The searcher never inspected a proof term's meaning; it only asked Agda.  Every hole position came from the server's own hole list, never from client-side arithmetic.  And the expensive step, the probe, was gated by everything cheap that could be tried first: a memo lookup, then a peek.

The other multi-step solve on the standard-library tier is `stdlib-prod-mk-pair`, where the goal `A × B` is closed by `(_,_ {!!} {!!})` followed by the assumptions `a` and `b`, one per sub-hole: three moves, the first of which leaves two obligations, which is exactly the situation the old search got wrong (§ 5).

## 4.  Why it is shaped the way it is: the cost of a judgment

Every design choice above follows from one measurement (Issue [#113], PR [#121]).  A probe spawns a batch `agda` that spends about 2.6 s loading the standard library's interfaces before it checks anything, and about 3.5 s on average across the suite once the agda-algebras tier is included; the interaction lane answers a question about a loaded file in 1–3 ms; transport and server handling add about 6 ms per call, 0.21 % of oracle time.  Proposal itself costs microseconds.  So the searcher optimizes one quantity, the number of batch judgments, and treats everything that can reduce that number as nearly free: budgets are counted in probes, judgments are memoized, and a millisecond peek is worth trying before a probe whenever it can reject anything at all.  The same number decided where the searcher lives: since no host language can avoid the `agda` subprocess, an in-process Haskell rewrite could recover at most 0.21 %, so the client stays in Scala beside the benchmark and corpus machinery.

## 5.  What the old search got wrong

The project's first searcher, `search.py`, was a small Python beam search that carried a single goal per state and declared success as soon as *any* subgoal closed, so a lemma with two obligations counted as proved when one was discharged.  Its post-mortem ([#112]) recorded that defect and four lessons worth keeping: report actions are peeks, not moves; supplying `k` arguments to a lemma consumes its first `k` visible binders and no hidden ones; there are two caches, because the oracle is the cost center; and children are ordered by remaining obligations.  The new searcher encodes all five as types and tests: a state's obligations are a set that must empty, `SolvedClaim` cannot be constructed without both the empty set and the final green check, and a regression test pins the two-obligation trap both in isolation and against the live server.

## 6.  The proposers

### 6.1  The fixed space (P1)

Described in § 2 under *action space*.  Two details are easy to miss and cost real solves before they were pinned in tests.  Applications are always parenthesized, `(s≤s {!!})` rather than `s≤s {!!}`, because a hole is as often an argument position as a right-hand side, and splicing `s≤s {!!}` verbatim into a sub-hole of `f {!!}` reads as `f s≤s {!!}`, a different term.  And the binder counts come from a small splitter over the type as the lane prints it; the splitter is a proposal device only, since an overcount is refused by Agda as a type error and an undercount leaves a partial application that the goal then has to accept.

### 6.2  Retrieval (P2)

Retrieval widens what is proposed without changing how anything is judged.  The `RetrievalProposer` wraps the fixed proposer, so everything above is still proposed, and adds lemmas found in a corpus.  For one goal it does the following.

1.  **Query**.  It asks the corpus tools for every row in each module the fixture imports (a `search_by_name` on the module prefix) and for rows whose type mentions the goal's distinctive tokens (a `search_by_type` per token: operators and long identifiers, not bound variables or numerals).  Queries ask wide (limit 5000), because the server truncates at its own default of 20, and a query that returns exactly the limit is counted as truncated rather than passed off as complete.
2.  **Scope**.  A candidate must resolve in the fixture's module.  The fact that makes retrieval possible without editing any fixture is that `open import M using (xs)` grants *qualified* access to all of `M`, not only to `xs`: in a fixture whose `using` list names only `+-suc`, the name `Data.Nat.Properties.+-comm` still resolves.  So the legal pool is every corpus row whose module the fixture imports, or whose module extends an imported one at a dot boundary (nested record modules, and the `Core` modules a stdlib module re-exports).  Rows from anywhere else are dropped and counted.
3.  **Target exclusion**.  Every standard-library obligation *is* a standard-library lemma, so the corpus contains the answers verbatim, and a wholesale-stratum agda-algebras obligation opens the module that holds its original.  A row whose bare name equals the hole's name is excluded (this also catches the record-field projections of a record-typed target), and so is a row whose statement normalizes to the target's (the comparison is made on the lane's own printing of both, since corpus text and index prose never agree); a differently stated but convertible lemma is legitimately in the space, because using it is a real proof step.  Every exclusion is named in the run report.  The policy has an off switch, `--exclude-target off`, used only for the labeled control sweep that proves the machinery can find a needle when one exists.
4.  **Rank**.  The surviving rows are sorted by a deterministic score: token overlap between the goal display and the row's type (with the corpus's qualified tokens reduced to bare segments, since the corpus writes `Agda.Builtin.Nat._+_` where a goal shows `+`), plus one point when the row's name contains a goal token, minus one per operator in the row's type that the goal never mentions; ties break cheap-before-expensive on approximate arity, then by name.  The scorer is its own interface, `CandidateScorer`, so a premise-selection model can replace it without touching the rest.
5.  **Render and resolve**.  The top-ranked rows are turned into names the fixture can actually use, trying in order the bare name (when the `using` list already opens it), the row's qualified name, and the importing module qualifying the bare name; the interaction lane arbitrates, and the first rendering `type_of` can type wins, with its binder telescope read off the lane's answer.  A row the lane cannot type stays out.  The cut to the top eight lemmas is taken *after* this step, so a row that fails to render does not consume a slot.
6.  **Shape**.  Each accepted lemma becomes up to three candidates: a hole-free `_`-form such as `(+-comm _ _)`, which closes the goal in one probe when unification can solve the arguments; *saturated* forms that apply the lemma to tuples of the context's assumptions, `(+-comm m n)`, `(+-comm n m)`, and so on, bounded at three arguments and twenty-seven tuples; and the `{!!}`-refinement form `(+-comm {!!} {!!})` that the fixed space also uses.  The saturated forms exist because of a fact probed on the wire during P2: `fill_hole` refuses a candidate whose sub-holes or `_` metas carry blocked constraints, and `(+-comm {!!} {!!})` at `m + n ≡ n + m` is exactly that (the metas are blocked under the non-injective `_+_`), so an equational lemma of that class can only ever be committed fully applied.  The peek prunes wrong tuples cheaply, since a hole-free candidate's inferred type has no metas in it.

The whole pipeline is memoized per goal display, because the loop meets the same goal in many states, and every cut it makes is counted in a per-fixture *honesty ledger* (queries, truncations, hits, in-scope rows, named exclusions, non-function rows dropped, lane rejections, and the lemmas finally proposed), so that a gamed run and a fair run are distinguishable from the report alone.

### 6.3  The peek, in more detail

The interaction lane answers `type_of` for an expression that is not in the file, with metas left where the expression is under-determined: `sym _` infers `_y_8 ≡ _x_7`, and bare `refl` infers `_x_9 ≡ _x_9`.  The peek turns that into a filter: the inferred type must be able to match the goal display when every meta is read as a wildcard, with the *same* meta standing for the *same* text, so `refl`'s `_x_9 ≡ _x_9` is rejected at `m + n ≡ n + m` and kept at `n ≡ n`.  An in-body error from the lane (`NotInScope`, `CannotApply`, `UnequalTerms`) rejects outright.  One rendering difference had to be bridged: Agda folds closed naturals to numerals in goal displays (`1 ≤ suc n`) but a meta blocks the folding in inferred types (`suc _m ≤ suc _n`), so small numerals are expanded to `suc` towers before comparison; without that the peek rejects `(s≤s {!!})` in the walk-through above.  The two closers are exempt from the peek: a closer's probe costs no more than its peek, and on agda-algebras goals whose two sides are definitionally equal but textually different (`lift ∘ lower ≡ 𝑖𝑑 (Lift b A)` closes by `refl`) the textual test rejects a correct `refl`.

## 7.  Running it

Everything runs from the repository root inside `nix develop .#backend`.  `AGDA_MCP_BIN`, when set, names a prebuilt server binary and skips the build.  The targets, each with a `make help` line, are the following.

+  `make proof-search-loop`: the beam search over the whole suite, or over a subset with `PROOF_SEARCH_LOOP_IDS="--ids id1,id2"`.  Knobs, with their defaults: `PROOF_SEARCH_BEAM=4`, `PROOF_SEARCH_DEPTH=6`, `PROOF_SEARCH_BUDGET=60`, `PROOF_SEARCH_DEDUP=script`, `PROOF_SEARCH_PEEK=on`, `PROOF_SEARCH_PROPOSER=fixed`.  For retrieval, `PROOF_SEARCH_PROPOSER=retrieval PROOF_SEARCH_CORPUS=<corpus.jsonl>`, with `PROOF_SEARCH_RETRIEVE_K=8`, `PROOF_SEARCH_EXCLUDE=on`, and `PROOF_SEARCH_EXPAND_DEPS=off`.  `PROOF_SEARCH_RUN_ID` names the output directory.
+  `make proof-search-single-step`: the P0 harness on one obligation (`PROOF_SEARCH_ID`), six stub candidates, which of them close it.
+  `make proof-search-split`: the P0 measurement, the whole standard-library tier twice against one server, reporting the oracle-versus-proposal timing split from the warm pass.
+  `make proof-search-it`, `make proof-search-loop-it`, and `make proof-search-retrieval-it`: the live regression tests against the real server (the two-obligation trap, a full search, and the corpus-tool transport).  `make test` runs the pure suites without a server.

A full sweep with the peek on takes about 20 minutes on a quiet machine.  Timings are only comparable machine-quiet: a live session on the same box inflated one run's wall clock more than twofold without changing a single solve or probe count, so the solve set, the scripts, and the probe counts are the columns to compare across runs.

## 8.  Reading a run

A run writes to `data/benchmarks/reports/proof-search/<run-id>/` (gitignored).  Its files are the following.

| file | one row or entry per | what to read from it |
|---|---|---|
| `results.jsonl` | judged candidate (a probe that ran or was replayed; a peek-rejected candidate was never judged and has no row) | `fixtureId` (the module stem), `benchmarkId` (the index id), `holeIndex` (the depth, as the position in the solving sequence), `candidateRank` (the 1-based rank in that expansion's proposal list), `candidate`, `status` (`ok`, `type_error`, `timeout`, or `crash`, the server's own vocabulary), `rc` (the verdict's exit code), `elapsedMs` (the client-observed wall clock), `logPath` (the raw reply) |
| `fixtures.jsonl` | fixture | `holesTotal` (1 per obligation), `holesSolved` (the committed moves of the winning script), `fullySolved` (the final strict check passed), `finalStatus`, `solvedPath` (the artifact under `solved/`), `searchStatus` (`solved`, `exhausted`, or `budget_exceeded`) |
| `timing.jsonl` | oracle call, plus one row per proposal | `phase` (`check_file`, `get_goal`, `fill_hole`, `type_of`, `peek`, `retrieval`, `proposal`, `final_check`), `clientMs`, `serverElapsedMs` (the `agda` subprocess, as the server reports it), `overheadMs` (their difference), `checkedFromSource`, `cached` (a memo replay, which spends no oracle time) |
| `report.json` | the run | `config` (every knob), `corpus` (path and provenance digest, for retrieval runs), `perTier` (solved, exhausted, budget-exceeded, anomalies, probes, peeks, and wall per difficulty tier), `split` (batch, knowledge, retrieval, and proposal time, and the batch share of oracle time), and `outcomes`, one per fixture with its status, script, counters, anomaly if any, and the retrieval honesty ledger |
| `solved/` | solved fixture | the typecheckable module with the found proof spliced in |
| `work/`, `logs/` | fixture; probe | the working copies; the raw server replies |

`results.jsonl` and `fixtures.jsonl` are on the `eval-proof-completion.v0` schema (`agda-dojang/README.md`), the same rows the policy-backend evaluator writes, so the ETL under `ml-pipeline/` consumes them unchanged; `timing.jsonl` is on `proof-search-timing.v0`.  Two conventions in the timing ledger matter when reading a split: a memo hit is a row with `cached: true` and no server time, so saved calls are never counted as oracle time; and a `proposal` row carries the proposer's *own* time, with any oracle calls the proposer made through the seam subtracted, since the ledger already holds those as rows of their own.

A fixture's `searchStatus` says how its search ended: `solved` (the final check passed), `exhausted` (every state was expanded, or the depth bound cut a live frontier, and the outcome says which), or `budget_exceeded` (the probe budget ran out with work remaining).  The distinction is the difference between "this configuration's search space holds no proof within this depth" and "we stopped looking".  Exhaustion is always relative to the proposer and the beam, either of which may have omitted or discarded the winning candidate, so it never shows that no term-mode proof exists; the measurements in the ADR lean on the distinction with that limit stated.

## 9.  Where it stands, in one paragraph

On the standard-library tier the fixed space solves 6 of 22 obligations, and those are exactly the six whose gold proofs are single terms expressible from the fixture's own imports; the other sixteen need an induction, a case split, or a reasoning block, none of which term mode can express, so the number is a ceiling, not a shortfall.  Retrieval over the standard-library corpus adds no solve under target exclusion on that tier, for the same reason, while a labeled control with exclusion off finds and commits every one of the five standard-library lemmas the exclusion had removed, which proves the retrieval machinery works.  On the agda-algebras tier, built so that every gold is a single term, the fixed space solves 2 of 21 and retrieval again adds nothing under exclusion; there the control commits one wholesale-stratum lemma end to end, and the ledgers show that the binding constraint is ranking at scale: wholesale imports flood the legal pool with thousands of rows, and token overlap cannot find the needle.  The numbers, the tables, and the decisions taken from them are in [ADR 0001](../adr/0001-proof-search-on-agda-mcp.md) § 9; the hand-off to a learned ranker is Issue [#19] ([M2-5]).

## 10.  Where to read more

+  [ADR 0001](../adr/0001-proof-search-on-agda-mcp.md): the decisions, their evidence, and the measured record.
+  [ADR 0002](../adr/0002-agda-mcp.md): the server the search drives, and why its verdicts can be trusted.
+  Issue [#113]: the tracking issue; its comments hold every measurement in full, with the run identifiers.
+  The file headers under `strux-driver/src/main/scala/struxdriver/search/`, and the tests beside them under `src/test/scala/struxdriver/search/`, whose names state the invariants (`"#112 regression: two obligations, one discharged, is NOT solved"`).
+  [`data/benchmarks/README.md`](../../data/benchmarks/README.md) and [`docs/benchmarks/taxonomy.md`](../benchmarks/taxonomy.md): the suite and its tiers.

<!-- GitHub references: one definition per issue or PR cited above; PRs resolve to /pull/, issues to /issues/. -->
[#19]: https://github.com/formalverification/agda-native-air/issues/19
[#112]: https://github.com/formalverification/agda-native-air/issues/112
[#113]: https://github.com/formalverification/agda-native-air/issues/113
[#121]: https://github.com/formalverification/agda-native-air/pull/121
[#129]: https://github.com/formalverification/agda-native-air/issues/129
