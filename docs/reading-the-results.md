<!-- File: docs/reading-the-results.md -->

# Reading the results

+  **What this is**: the reader's guide to every measured number in this
   repository.  It names the instrument that produced each one, defines the
   words the tables use, says which tools are which, and states for each
   number whether it is a win or a loss for `agda-mcp` and against what.
+  **Why it exists**: the tables in [ADR 0001] § 9 and the README put the
   deterministic search loop's numbers beside the agent's numbers, and a reader
   takes the first as a baseline for the second.  It is not.  Until
   2026-09-21 **no measurement in this repository compared the tools with
   their absence**; the only such comparison is [#162], and this page is
   written so that nobody has to discover that by re-reading.
+  **Rule for quoting**: a number quoted from here travels with its instrument
   and its run id.  "46 of 55" on its own is not a result.

## 1.  The four instruments

Everything measured here comes from one of four instruments.  The first has no
model in it at all; the other three are one model under three configurations.

### 1.1  The loop

`strux-driver`'s proof search ([ADR 0001], [`proof-search/overview.md`]).  A
deterministic beam search, written in Scala, **with no language model**.  It
uses the server as an oracle: `get_goal` to read the open hole, `type_of` on
the interaction lane to peek at a candidate's type before spending a judgment,
and `fill_hole` to judge the candidate.  Its candidates come from a *proposer*
(§ 3 below): either a fixed vocabulary or corpus retrieval.

**What "solved" means for the loop**: the loop's obligation set is empty (every
hole the search opened has been closed) **and** a final batch `agda` check of
the working copy passed.  A per-goal success counts for nothing; the claim is
granted only through that final check ([ADR 0001] § 3).

**What a number like 6/22 means**: of the 22 obligations in the standard-library
tier, the loop solved 6 within its budget.  The other 16 ended `exhausted`
(the search space was emptied to the depth bound) or `budget_exceeded` (the
probe budget ran out with work remaining), and the report says which.

The loop measures **the searcher and the proposer**, not a model.  Its numbers
say how far a fixed vocabulary or a ranker can get with Agda as the only
judge.  They are not a baseline for an agent.

### 1.2  The agent with the server: the `mcp` arm

One fresh, non-interactive `claude -p` session per obligation, given the
thirteen (since PR [#161], fourteen) `agda-mcp` tools plus Read and Edit on a
single staged file, **no shell**, under caps of 30 turns, 900 s, and USD 3.00
per subject ([#154], [`reports/agent-bench/README.md`]).  Every agent number
published before 2026-09-21 is this arm.

### 1.3  The agent with a shell: the `shell` arm

The same session, prompts, caps, and judge, given Bash, Read, and Edit, the
pinned `agda` 2.8.0 on `PATH` with the same libraries the server resolves
against, the row's corpus JSONL on disk to `grep`, and **no server** ([#162]).
This is the control: the tools' absence.

### 1.4  The agent with both: the `both` arm

Both instruments at once.  It answers a question the other two cannot: offered
a choice, which does the model reach for, and for what.

### 1.5  One judge for all four

Every verdict about a final file, on every instrument, is the same batch
`agda` invocation (`GoldVerifier.agdaCommand`, with `--safe`), plus the
`agda-strux` extractor for the statement and the references.  So "batch
`agda`" appears in two roles: it is always the **judge**, and in the shell
arms it is also the model's **tool**.  The judge favors no arm.

## 2.  Vocabulary

+  **Obligation**: one benchmark module with exactly one hole `{!!}`; 55 of
   them, under `data/benchmarks/`.  Its **gold** is the same module with the
   hole filled, and every gold type-checks under the pinned toolchain.
+  **Tier (difficulty)**: `routine`, `compositional`, `non-obvious`
   ([`benchmarks/taxonomy.md`]).  16, 25, and 14 obligations.
+  **Stratum (library slice)**, which is what the tables are cut by:
   +  `agda-stdlib`, 22 rows: statements that are standard-library lemmas, with
      the key lemmas handed over in the fixture's `using` lists;
   +  `agda-stdlib/haystack`, 12 rows: golds that apply **one** lemma the
      fixture imports but does **not** name in a `using` list, so the fixed
      space cannot reach it by construction ([#129]);
   +  `agda-algebras/using`, 11 rows: mined from agda-algebras, pieces named
      in `using` lists;
   +  `agda-algebras/wholesale`, 10 rows: mined from agda-algebras, whole
      modules imported and nothing named, so the searcher has to find the
      pieces.
+  **Solved**: the file passed every gate *and* the definition does not refer
   to the library's own lemma for the statement.
+  **Restated**: the file passed every gate but the definition refers to the
   library's own lemma for the statement it was asked to prove
   (`kercon′ h = kercon h`).  It type-checks and proves nothing new.  **Never
   counted as solved**; reported in its own column.  The agent-side twin of
   the loop's target exclusion.
+  **Gate**: one of the judge's named refusals (`preservation`, `escape`,
   `holes`, `typecheck`, `isolation`); a row that fails one is neither solved
   nor restated, and the outcome names the gate.
+  **Anomaly**: a row the harness could not measure (a crash, a rate-limit
   rejection, a tool presented that should not have been); never a solve,
   never a restatement, counted separately.  Every quoted run has zero.
+  **Probe**: one `fill_hole` judgment in the loop.  The loop's **budget** is
   counted in probes (60 per obligation), because the batch `agda` process
   behind a probe is 99.79 % of the loop's time.
+  **Peek**: a `type_of` question on the interaction lane, 1 to 3 ms, that
   lets the loop skip a probe whose candidate cannot fit the goal.  A peek
   only ever skips; it never substitutes for a judgment.
+  **Fixed space**: the loop's non-learned candidate vocabulary (§ 3.1).
+  **Retrieval**: candidates drawn from a corpus through the server's search
   tools, ranked by a **scorer**, and rendered into candidate shapes (§ 3.2).
+  **Target exclusion**: the answer key removed from the retrieval pool
   (§ 3.2).  A measurement "under exclusion" is fair; one "with exclusion off"
   is a labeled control that shows the machinery works.
+  **Needle**: on the haystack tier, the one lemma the gold needs.

## 3.  The tools, in two classes

`agda-mcp` offers fourteen tools ([`agda-mcp/README.md`]).  For reading
results, what matters is what each one runs and what it returns.

**Verdict tools** run a batch `agda` process and answer with its exit code.
They are the only tools whose answer is a verdict about a file.

| tool | runs | returns |
|---|---|---|
| `check_file` | batch `agda` on the file | `success` iff exit 0, diagnostics, holes |
| `fill_hole` | batch `agda` on a copy with the candidate spliced in | `status` ok / type_error / timeout / crash |
| `get_diagnostics` | the same batch check, summarized | counts and hole positions |
| `check_project` | the project's own gate | its exit code, unaltered |

**Knowledge tools** answer questions and produce no verdict.  Two kinds, by
what answers them:

| tool | answered by | returns |
|---|---|---|
| `get_goal` | the interaction lane | the hole's goal type and context |
| `type_of`, `normalize` | the lane | a type, a normal form |
| `resolve_name`, `definition_of`, `exports_of` | the lane | candidates; **the file and position** of a definition; a module's surface |
| `search_by_name`, `search_by_type`, `get_dependencies` | the corpus JSONL | matching rows |
| `search_in_scope` | corpus plus lane | rows the file can name, typed |

Two facts about this split that the results turn on.  The **loop** uses one
verdict tool (`fill_hole`, plus `check_file` for the final claim) and three
knowledge tools (`get_goal`, `type_of` for the peek, and `search_by_name` /
`search_by_type` for retrieval).  And `definition_of` returns *where* a
definition is, not what it says; § 5 is where that matters.

### 3.1  The fixed space

The loop's P1 proposer ([ADR 0001] § 5), in proposal order: the closers
`refl` and `tt`; the goal context's assumptions by name; and an application of
every name the fixture imports through a `using` list, with one `{!!}` per
remaining visible binder, parenthesized.  Nothing else.  It cannot case-split
and cannot write a `with`, so any gold that restructures the clause is
unreachable by construction: on the standard-library tier that is 16 of the 22
golds (13 two-clause inductions, 2 case splits, one `≡-Reasoning` chain), which
is why the fixed space's 6/22 there is called the **term-mode ceiling**.

### 3.2  Retrieval, and what its numbers test

The P2 proposer ([ADR 0001] § 7, `Retrieve.scala`) is composed *around* the
fixed space, so its candidate set is a superset and any change is
attributable to retrieval.  For each open goal it does the following:

1.  **Pool**: asks the server's `search_by_name` / `search_by_type` over the
    corpus loaded with `--corpus`, and keeps the rows the fixture can name (a
    row's module is imported, or extends an imported module at a dot
    boundary).
2.  **Exclusion**: removes the answer key: any row whose bare name equals the
    hole's name, and any row whose statement normalizes to the target's.
    Every exclusion is named in the run's ledger.
3.  **Ranking**: orders the pool with a named **scorer**.  `token-overlap`, the
    placeholder every sweep before PR [#152] ranked with, scores token overlap
    between the goal display and the row's type.  `idf-unfold`, since
    PR [#152], adds IDF weighting over the pool, the goal's hypotheses, and up
    to three definitional unfoldings.
4.  **Cut**: takes the top `k` rows, 8 by default.
5.  **Shapes**: renders each into three candidate shapes (the `_`-form
    `(+-comm _ _)`, argument-saturated forms over the context, and the
    `{!!}`-refinement form), peeks each, and probes the survivors.

So a retrieval number tests **the scorer's ability to rank the needle into
the top 8 of a pool it is not allowed to contain the answer key of**, plus the
loop's ability to commit it.  It does not test a model.

## 4.  The numbers, each with its line back

Every run below reported zero anomalies.  Run ids are the harness's own;
"recorded" says where the table lives.

### 4.1  The loop

| what | number | instrument and knobs | run id | recorded |
|---|---|---|---|---|
| Fixed space, stdlib tier, no peek | **6/22** (routine 6/7, compositional 0/10, non-obvious 0/5), 435 probes | loop, P1 proposer, beam 4, depth 6, budget 60 | PR [#126]'s sweep | [ADR 0001] § 9, P1 table |
| The same with the peek on | 6/22, byte-identical scripts, 50 probes | loop, peek on | PR [#126] | same |
| Fixed space, 43-suite | **8/43** (stdlib 6/22, algebras `using` 2/11, `wholesale` 0/10) | loop, peek on, closers exempt | `run-127-repin-full-peek-on-1` | [ADR 0001] § 9, 43-suite table |
| Retrieval, stdlib tier, exclusion on | 6/22, the same six, 526 probes | loop, retrieval, `token-overlap`, k 8 | `p2fix-b` | § 9, P2 stage-one table |
| Retrieval, stdlib tier, **exclusion off** (control) | 9/22 | loop, retrieval, exclusion off | `p2fix-d` | same |
| Retrieval, 43-suite, exclusion on | **8/43**, the fixed space's set exactly | loop, retrieval, `token-overlap` | `p2s2-a` | § 9, P2 stage-two table |
| Fixed space, 43-suite (attribution control) | 8/43 | loop | `p2s2-b` | same |
| Retrieval, 43-suite, exclusion off (control) | 9/43 | loop | `p2s2-c` | same |
| Fixed space, haystack tier | **0/12**, 30 probes, every row exhausted at depth 0 | loop | `hay-fixed-final` | § 9, haystack table |
| Retrieval, haystack tier, exclusion on | **6/12** (routine 2/3, compositional 4/5, non-obvious 0/4), 317 probes | loop, retrieval, `token-overlap`, k 8 | `hay-retrieval-final` | same |
| Retrieval, haystack, k 32 | 6/12, the same set | loop, k 32 | `hay-retrieval-k32` | same |
| `idf-unfold`, 43-suite, exclusion on | **9/43** (`using` 3/11) | loop, retrieval, `idf-unfold` | `k19r2-idf-unfold-a` | § 9, idf-unfold table |
| `idf-unfold`, exclusion off (control) | 10/43 | loop | `k19r2-idf-unfold-b` | same |
| Ranking recall, offline | targets in top 8: `token-overlap` **1/33**, `idf-unfold` **9/33** | recall instrument, no server | `recall-ctx1-r2` | § 9, scorer table |

**How "8 of 55 and 14 of 55" are composed**.  The two loop columns in the
agent table are sums over strata: fixed space 8/43 + 0/12 = **8/55**;
retrieval 8/43 + 6/12 = **14/55**.  So the whole of retrieval's gain, all six
rows, is the haystack tier.  On the other 43 obligations retrieval added
**zero** solves under exclusion.

**What the haystack six mean**.  Before that tier, retrieval had never solved
a row under exclusion.  The tier was built so that the fixed space cannot
reach the needle (it is not `using`-listed) and retrieval can; on six rows it
did, each as one saturated application of the needle, with the exclusion
ledger empty, so each is attributable to retrieval by construction.  That is
the sentence "the first solves under exclusion": a win for retrieval **inside
the loop**, on a tier designed to need it.  The six nulls each pin one
limitation of the ranker or the peek ([ADR 0001] § 9).

**Reading the loop's numbers as wins or losses**.  They are wins or losses for
a *proposer*, never for the tools against a shell.  The peek is a win (probes
435 to 50 for the same six solves).  `idf-unfold` is a win over the
placeholder (1/33 to 9/33 targets in the top 8; 8/43 to 9/43).  Retrieval
under exclusion on the 43-suite is a null result whose cause is measured
(ranking at scale).  The 6/22 ceiling is not a loss; it is the vocabulary's
edge, stated.

### 4.2  The agent with the server

| what | number | instrument | run id | recorded |
|---|---|---|---|---|
| Sonnet 5, `mcp` arm | **46 solved, 8 restated**, 1 preservation gate; 327 turns, 272 calls, USD 4.62 | § 1.2, 13 tools | `agent-sonnet5-1` | [ADR 0001] § 9, [`reports/agent-bench/`] |
| Opus 5, `mcp` arm | **54 solved, 1 restated**; 325 turns, 270 calls, USD 9.14 | same | `agent-opus5-1` | same |
| Opus 5, second seed | 54 solved, 1 restated, the same rows; 338 turns, 283 calls | same | `agent-opus5-2` | same |

Per stratum (Sonnet, then Opus): stdlib 21 and 22 of 22; haystack 12 and 12 of
12; `using` 9 (2 restated) and 11 of 11; `wholesale` 4 (6 restated) and 9
(1 restated) of 10.  Per tier: routine 15 and 16 of 16; compositional 20 and
24 of 25; non-obvious 11 and 14 of 14.

Per tool (Sonnet, then Opus): `check_file` 56 and 55; `type_of` 24 and 21;
`fill_hole` 12 and 41; `get_goal` 10 and 17; `search_by_name` 15 and 8;
`definition_of` 13 and 4; `exports_of` 12 and 4; `get_dependencies` 4 and 2;
`search_by_type` 2 and 1; `normalize` 0 and 3; `resolve_name` 0 and 1;
`get_diagnostics` and `check_project` never.

**Reading these**.  They say what a frontier model does *with* the server.
**They say nothing about the server's value**, because no arm without it
existed when they were made.  Two readings that do hold: the haystack tier is
12/12 for both models, eleven of Sonnet's rows in four turns with no query at
all, so that tier measures a ranker and not a model; and the restated column
is where the models differ (8 against 1), all of it on the agda-algebras
tiers.

### 4.3  The control, and the comparison

[#162], PR [#175].  Sonnet 5, 2026-09-21, one arm at a time at one protocol
version, the same caps and judge, the libraries' sources readable on every
arm.  Three Sonnet arms cost USD 12.41 together.

| stratum | n | archive `mcp` | `shell` | `mcp` | `both` |
|---|---|---|---|---|---|
| agda-stdlib | 22 | 21 | 20 | 21 | 20 |
| agda-stdlib/haystack | 12 | 12 | 12 | 12 | 12 |
| agda-algebras/using | 11 | 9 (2 restated) | 9 | 9 (1 restated) | 11 |
| agda-algebras/wholesale | 10 | 4 (6 restated) | **9** | 5 (5 restated) | 8 (2 restated) |
| **total solved / restated** | 55 | 46 / 8 | **50 / 0** | 47 / 6 | **51 / 2** |

| arm | run id | turns | tool calls | USD | output tokens | bytes returned by tools |
|---|---|---|---|---|---|---|
| `shell` | `arm162-shell-1` | 308 | 253 | **2.88** | 70,403 | 259,520 |
| `mcp` | `arm162-mcp-1` | 342 | 287 | 5.28 | 76,732 | **929,386** |
| `both` | `arm162-both-1` | 327 | 272 | 4.25 | 67,269 | |

The `both` arm's per-tool counts against the `mcp` arm's: `check_file` 57
and 56; `type_of` 11 and 34; `definition_of` **0** and 19; `search_by_name`
**1** and 18; `exports_of` 2 and 11.  Bash in the `both` arm: 65 calls, every
one a library-source read; `agda` run on the shell: **never**.

**Reading this, number by number**.

+  **Solved, tools against no tools: a loss**.  50 with a shell, 47 with the
   server.  Three rows, on one seed of one model, which is within the
   run-to-run variance the two Opus seeds showed (0 rows, 13 turns); the
   direction is credible because the mechanism is identified below, but the
   magnitude is not.
+  **Restated, tools against no tools: a loss, and the robust one**.  0 with a
   shell, 6 with the server, 8 in the archive.  A subject that reads a
   lemma's source writes the construction (`IsMon.HomReduct (proj₂ m)`); one
   that learns its name from a tool cites it (`mon→hom _ _ m`).
+  **Cost, tools against no tools: a loss, diagnosed**.  USD 5.28 against
   2.88 with **equal output tokens**: the model wrote the same amount and
   read 3.6 times more, because the tools' answers carry echo and boilerplate
   (a `type_of` answer is 3 KB for one line of type; `exports_of` averages
   23 KB).  Tracked as [#184]; a lean re-run is the test.
+  **The verdict tool: a win, by revealed preference**.  Offered both, the
   model took **every one of its 55 verdicts from `check_file`** and never
   ran `agda` by hand.
+  **The knowledge tools, as built: a loss**.  Beside a shell they collapse,
   because `grep` over the source needs no prior knowledge of where a thing is
   while `definition_of` answers where and not what.  Tracked as [#185].
+  **`both` beats `shell` by one row**: within noise; not a claim.

### 4.4  The lane parity

[#163], PR [#174].  `Cmd_give` on the persistent interaction lane against the
batch `fill_hole`, over 80 distinct (obligation, candidate) pairs drawn from
the archived agent probes and the golds, with and without `--safe`:
**0 disagreements**; 2 on the 19 deliberate cases, both explained; rows under
[`reports/lane-give-parity/`], which land with PR [#174].  A give answers in 1.4 to 4.6 ms and the reload
that puts the hole back in about 220 ms, against 2.6 s for a batch judgment.
This measures the server's own machinery; it says nothing about agents, and
it is a win for a lane judgment on the record.  One fact from it to carry:
for 16 of the 55 obligations the committed gold is a multi-clause strategy,
not a term, so no hole-filling judgment of any kind can express it.

## 5.  How to tell a win from a loss

| question | look at | it is a win for the tools when |
|---|---|---|
| Does the server help a frontier model solve more? | § 4.3, `shell` against `mcp`, solved | `mcp` is higher by more than one seed's noise.  **Today: no**. |
| Does it help it prove rather than cite? | § 4.3, restated | `mcp` restates fewer.  **Today: the reverse**. |
| Does it make a session cheaper? | § 4.3, USD and bytes | `mcp` costs less.  **Today: no; cause measured, [#184]**. |
| Which tools does a model want? | § 4.3, `both` arm per tool | a tool is used when a shell is available too.  **`check_file`: yes.  Knowledge tools: no**. |
| Does retrieval help the loop? | § 4.1, haystack and 43-suite | solves appear under exclusion.  **Haystack: yes, 0 to 6.  Elsewhere: no**. |
| Is the loop a baseline for the agents? | nothing | **never**; a different instrument |
| Is a lane judgment as trustworthy as batch? | § 4.4 | parity holds.  **Yes, on 80 of 80**. |
| Is the fixed space's 6/22 a failure? | § 3.1 | it is the vocabulary's ceiling, stated; not a loss |

## 6.  What is not measured

+  **Problems a shell-only model fails**.  Every arm is at or near ceiling on
   this suite (a shell-only Sonnet solves 91 %), so the suite cannot show a
   tool's upside on hard, novel, multi-lemma work.  That is the original
   question, and it is untested: the composition tier ([#160]) and the
   agda-algebras case study ([#23]) are the instruments.
+  **The tools with lean answers** ([#184]) and **knowledge tools that return
   content** ([#185]): the two measured defects, each with a re-run that
   settles it.
+  **Small and local models** ([#27], [#28], [#29]), where a shell is least
   usable and structured verdicts plausibly matter most.
+  **Opus with a shell**.  The control was run on Sonnet only.

## References

+  [ADR 0001]: the decisions and every loop table, § 9.
+  [ADR 0002]: the server's design; decision 1 is the two-lane policy.
+  [`proof-search/overview.md`]: how the loop works, in prose.
+  [`reports/agent-bench/README.md`]: the agent protocol, the judge's gates,
   and the run table.
+  [`reports/lane-give-parity/`]: the parity rows, on PR [#174] until it
   merges.
+  [`benchmarks/taxonomy.md`] and [`data/benchmarks/README.md`]: the tiers and
   the obligations.
+  [`agda-mcp/README.md`]: the tool contracts.
+  Make targets: `make proof-search-loop` (knobs `PROOF_SEARCH_PROPOSER`,
   `PROOF_SEARCH_CORPUS`, `PROOF_SEARCH_RETRIEVE_K`, `PROOF_SEARCH_EXCLUDE`,
   `PROOF_SEARCH_SCORER`), `make proof-search-recall`, `make agent-bench`
   (`AGENT_BENCH_MODEL`, `AGENT_BENCH_ARM=shell|mcp|both`),
   `make agent-bench-rejudge`, `make lane-give-parity`.

[ADR 0001]: adr/0001-proof-search-on-agda-mcp.md
[ADR 0002]: adr/0002-agda-mcp.md
[`proof-search/overview.md`]: proof-search/overview.md
[`benchmarks/taxonomy.md`]: benchmarks/taxonomy.md
[`data/benchmarks/README.md`]: ../data/benchmarks/README.md
[`agda-mcp/README.md`]: ../agda-mcp/README.md
[`reports/agent-bench/README.md`]: ../reports/agent-bench/README.md
[`reports/agent-bench/`]: ../reports/agent-bench/README.md
[`reports/lane-give-parity/`]: https://github.com/formalverification/agda-native-air/pull/174
[#23]: https://github.com/formalverification/agda-native-air/issues/23
[#27]: https://github.com/formalverification/agda-native-air/issues/27
[#28]: https://github.com/formalverification/agda-native-air/issues/28
[#29]: https://github.com/formalverification/agda-native-air/issues/29
[#126]: https://github.com/formalverification/agda-native-air/pull/126
[#129]: https://github.com/formalverification/agda-native-air/issues/129
[#152]: https://github.com/formalverification/agda-native-air/pull/152
[#154]: https://github.com/formalverification/agda-native-air/issues/154
[#160]: https://github.com/formalverification/agda-native-air/issues/160
[#161]: https://github.com/formalverification/agda-native-air/pull/161
[#162]: https://github.com/formalverification/agda-native-air/issues/162
[#163]: https://github.com/formalverification/agda-native-air/issues/163
[#174]: https://github.com/formalverification/agda-native-air/pull/174
[#175]: https://github.com/formalverification/agda-native-air/pull/175
[#184]: https://github.com/formalverification/agda-native-air/issues/184
[#185]: https://github.com/formalverification/agda-native-air/issues/185
