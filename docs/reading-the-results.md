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

Every solve count in this repository comes from one of four instruments.  The
first has no model in it at all; the other three are one model under three
configurations.  Two auxiliary instruments measure parts and never solves: the
recall instrument (§ 4.1), which scores a ranker against known targets, and
the lane parity replay (§ 4.4), which compares two judgments of one candidate.

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
published before 2026-09-21 is this arm.  Until 2026-09-29 the staged file
carried its fixture's header, and the header carried hints (§ 4.6); the
arm's current numbers are the header-free runs of that day.

### 1.3  The agent with a shell: the `shell` arm

The same session, prompts, caps, and judge, given Bash, Read, and Edit, the
pinned `agda` 2.8.0 on `PATH` with the same libraries the server resolves
against, the row's corpus JSONL on disk to `grep`, and **no server** ([#162]).
This is the control: the tools' absence.

### 1.4  The agent with both: the `both` arm

Both instruments at once.  It answers a question the other two cannot: offered
a choice, which does the model reach for, and for what.

### 1.5  One judge for the three arms, and the loop's own

Every verdict about an agent's final file, on all three arms, is the same
batch `agda` invocation (`GoldVerifier.agdaCommand`, with `--safe`), plus the
`agda-strux` extractor for the statement and the references.  The loop's
claim is its own: solved means the obligation set is empty *and* a final
batch `check_file` through the server passed, under the loop's server flags
rather than the judge's, with the target exclusion (§ 2) standing where the
restated rule stands for the agents, and with no statement gate because the
loop can only ever edit the hole ([ADR 0001] § 3).  So "batch `agda`" appears
in two roles: it is always the **judge**, and in the shell arms it is also
the model's **tool**.  The judge favors no arm; and the loop's numbers and
the agents' are not judged alike, one more reason the first is no baseline
for the second.

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
   the loop's target exclusion.  The rule reads the body's *references*, so
   it catches a body that cites the lemma and not one that transcribes the
   lemma's own proof; § 4.3 measures how often that happened.
+  **Original in view**: on a row whose index entry names the library lemma
   it restates (every agda-algebras row), a line of that lemma's own proof
   came back in one of the subject's tool answers before its last edit of
   the work file.  A call that names the lemma's file without showing its
   proof does not count.  The judge reports it per row (the `original` block
   of `outcome.json`, `null` on a row with no original) and per slice
   (`solvedOriginalInView`), and no verdict depends on it ([#188]).
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
+  **Header hints**: the comment lines at the top of a fixture that, until
   [#219], sketched the proof (`Strategy:`), named the needle (`Needle:`),
   or named the module holding the original (`Source:`).  A subject works
   on a byte-for-byte copy of its fixture, so every run before 2026-09-29
   had them in view; the runs of that day had none (§ 4.6).

## 3.  The tools, in two classes

`agda-mcp` offers fourteen tools ([`agda-mcp/README.md`]).  For reading
results, what matters is what each one runs and what it returns.

**Verdict tools** run a batch process (`agda`, or for `check_project` the
project's own gate) and answer from its exit code.  They are the only tools
whose answer is a verdict about a file or a project.

| tool | runs | returns |
|---|---|---|
| `check_file` | batch `agda` on the file | `success` iff exit 0, diagnostics, holes |
| `fill_hole` | batch `agda` on the file with the candidate spliced over the hole, patched in place and restored afterwards | `status` ok / type_error / timeout / crash |
| `get_diagnostics` | the same batch check, summarized | counts and hole positions |
| `check_project` | the project's gate: a named `make` target, `--check-command`, the nearest Makefile's `check`, or `agda` on `Everything` | `success` iff exit 0 *and* inside the bound *and* no failure evidence in the output (`maskedFailure`); the exit code echoed, never reinterpreted |

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
"recorded" says where the table lives.  Every agent run dated before
2026-09-29 had the fixture headers' hints in view; the runs of that day
(`suite219-*`, `hard219-*`, and the composition tier's `comp-*`) had none,
and where the two differ, the header-free number is the one quoted (§ 4.6).

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
| Sonnet 5, `mcp` arm, header-free | **44 solved, 9 restated**, 2 preservation gates; 347 turns, 292 calls, USD 3.99 | § 1.2, 14 tools | `suite219-sonnet5-mcp-1` | [ADR 0001] § 9, [`reports/agent-bench/`] |
| Opus 5, `mcp` arm, header-free | **55 solved, 0 restated**; 323 turns, 268 calls, USD 7.07 | same | `suite219-opus5-mcp-1` | same |
| Sonnet 5, `mcp` arm, hints in view | 46 solved, 8 restated, 1 preservation gate; 327 turns, 272 calls, USD 4.62 | § 1.2, 13 tools | `agent-sonnet5-1` | [ADR 0001] § 9, dated table |
| Opus 5, `mcp` arm, hints in view | 54 solved, 1 restated; 325 turns, 270 calls, USD 9.14 | same | `agent-opus5-1` | same |
| Opus 5, second seed, hints in view | 54 solved, 1 restated, the same rows; 338 turns, 283 calls | same | `agent-opus5-2` | same |

Header-free, per stratum (Sonnet, then Opus): stdlib 21 and 22 of
22; haystack 12 and 12 of 12; `using` 9 (1 restated) and
11 of 11; `wholesale` 2 (8 restated) and 10 of 10.  Per
tier: routine 15 and 16 of 16; compositional 20 and
25 of 25; non-obvious 9 and 14 of 14.

Header-free, per tool (Sonnet, then Opus): `check_file` 61 and 55; `fill_hole` 11 and 42; `type_of` 23 and 17; `exports_of` 23 and 0; `search_by_name` 21 and 7; `get_goal` 5 and 14; `definition_of` 11 and 10; `search_by_type` 2 and 0; `normalize` 0 and 2; `search_in_scope` 0 and 1; `get_dependencies`, `resolve_name`, `get_diagnostics`, and `check_project` never.

The header-free arms differ from the first ones in more than the headers:
the server has fourteen tools rather than thirteen, lean answers ([#184])
and a trimmed surface ([#191]); the libraries' sources are readable; the
subjects' servers carry the judge's `--safe`; and the client is 2.1.282
rather than 2.1.261.  For Sonnet the like-for-like runs with the hints in
view are the two [#191] seeds, `arm-surface-mcp-1` and `-2` (48 and 45
solved, 7 and 8 restated), and § 4.6 compares against them.

**Reading these**.  They say what a frontier model does *with* the server.
**They say nothing about the server's value**; the control (§ 4.3) does.  Two
readings that do hold.  The haystack tier is 12 of 12 for both models, and the
count separates nothing, but its route changed with the headers: Sonnet asked
before its final check on nine of the twelve rows (`search_by_name` on eight),
where in the two like-for-like runs with the header naming the needle it had
asked on one and two (§ 4.6).  And the restated column is where the models
differ (9 against 0), all of it on the agda-algebras tiers.

### 4.3  The control, and the comparison

[#162], PR [#175]; re-run without the header hints for [#219].  Sonnet 5,
one arm at a time at one protocol version, the same caps and judge, the
libraries' sources readable on every arm.

**Header-free, 2026-09-29**.  The three arms share their protocol with each
other and with § 4.2's header-free Opus arm, but for one deliberate
difference: the prompts of the two arms with a shell name each library's
source directory (PR [#200]).  USD 11.54 together.

| stratum | n | `shell` | `mcp` | `both` |
|---|---|---|---|---|
| agda-stdlib | 22 | 22 | 21 | 21 |
| agda-stdlib/haystack | 12 | 11 | 12 | 11 |
| agda-algebras/using | 11 | 10 | 9 (1 restated) | 11 |
| agda-algebras/wholesale | 10 | 4 (4 restated) | 2 (8 restated) | 5 (5 restated) |
| **total solved / restated** | 55 | **47 / 4** | 44 / 9 | **48 / 5** |

| arm | run id | turns | tool calls | USD | output tokens | bytes returned by tools |
|---|---|---|---|---|---|---|
| `shell` | `suite219-sonnet5-shell-1` | 345 | 290 | **3.42** | 92,135 | 260,271 |
| `mcp` | `suite219-sonnet5-mcp-1` | 347 | 292 | 3.99 | 87,335 | 414,106 |
| `both` | `suite219-sonnet5-both-1` | 353 | 298 | 4.13 | 81,546 | 274,106 |

Every row that failed a gate type-checks with its statement kept.  The
`shell` arm's four are two subjects that ran `find /` although the prompt
names the source directories, one `xargs` inside the roots (which the audit
does not model; that file also cites `kercon`), and one edited `using`
list; the `mcp` arm's two and the `both` arm's two are edited `using` lists,
one of them (`algebras-injective-comp-injective`, `mcp`) appending the
original it then cites.  So the files earned 50 solves and 5 restatements
with a shell, 45 and 10 with the server, and 50 and 5 with both.  The `both`
arm's per-tool counts against the `mcp` arm's: `check_file` 58 and 61;
`type_of` 7 and 23; `definition_of` **0** and 11; `search_by_name` **4**
and 21; `exports_of` 4 and 23.  Bash in the `both` arm: 84 calls, 83 of them
library-source reads and one a grep of the corpus; `agda` run on the shell:
**never**; all 55 verdicts from `check_file`.

**With the hints in view, 2026-09-21**.  The first control, whose arms had
the fixture headers' hints in view and whose shell prompts said only that
the sources were on disk; `archive mcp` is `agent-sonnet5-1`.  Three Sonnet
arms cost USD 12.41 together.

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
| `both` | `arm162-both-1` | 327 | 272 | 4.25 | 67,269 | 474,562 |
| `mcp`, lean answers | `arm184-mcp-1` | 359 | 304 | 4.63 | 82,831 | 534,272 |
| `both`, lean answers | `arm184-both-1` | 318 | 263 | 4.00 | 66,634 | 223,797 |
| `mcp`, trimmed surface | `arm-surface-mcp-1` | 345 | 290 | 3.83 | 76,583 | 436,247 |
| `mcp`, trimmed surface, second seed | `arm-surface-mcp-2` | 349 | 294 | 3.74 | 82,054 | 365,278 |
| `both`, trimmed surface | `arm-surface-both-1` | 318 | 263 | 3.55 | 70,780 | 222,638 |
| `mcp`, four tools exposed | `arm-verdict-mcp-1` | 458 | 403 | 3.78 | 118,006 | 291,366 |
| `mcp`, four tools, second seed | `arm-verdict-mcp-2` | 461 | 406 | 3.84 | 114,237 | 314,694 |

The `both` arm's per-tool counts against the `mcp` arm's: `check_file` 57
and 56; `type_of` 11 and 34; `definition_of` **0** and 19; `search_by_name`
**1** and 18; `exports_of` 2 and 11.  Bash in the `both` arm: 65 calls, every
one a library-source read; `agda` run on the shell: **never**.

**What the readable sources did**.  Every agda-algebras obligation restates
a lemma the library already proves, and [#162] made the libraries' sources
readable on every arm so that the arms would be comparable.  The archived
arms had refused those reads as a confinement side effect.  The judge's
`original` column (§ 2, [#188]) reads each transcript for the lemma's own
proof: whether a line of it came back in one of the subject's tool answers
before its last edit of the work file.  Over the 21 agda-algebras rows:

| arm | run id | solved | restated | solved with the original's proof in view | reads of the original refused |
|---|---|---|---|---|---|
| `shell`, header-free | `suite219-sonnet5-shell-1` | 14 | 4 | **12** | 0 |
| `mcp`, header-free | `suite219-sonnet5-mcp-1` | 11 | 9 | 4 | 0 |
| `both`, header-free | `suite219-sonnet5-both-1` | 16 | 5 | **11** | 0 |
| `mcp`, Opus, header-free | `suite219-opus5-mcp-1` | 21 | 0 | 4 | 0 |
| archive `mcp`, Sonnet | `agent-sonnet5-1` | 13 | 8 | **0** | 2 |
| archive `mcp`, Opus | `agent-opus5-1` | 20 | 1 | **0** | 2 |
| archive `mcp`, Opus | `agent-opus5-2` | 20 | 1 | **0** | 4 |
| `shell` | `arm162-shell-1` | 18 | 0 | **15** | 0 |
| `mcp` | `arm162-mcp-1` | 14 | 6 | 4 | 0 |
| `both` | `arm162-both-1` | 19 | 2 | **16** | 0 |
| `mcp`, lean answers | `arm184-mcp-1` | 12 | 8 | 3 | 0 |
| `both`, lean answers | `arm184-both-1` | 18 | 2 | **14** | 0 |
| `mcp`, trimmed surface | `arm-surface-mcp-1` | 14 | 7 | 6 | 0 |
| `mcp`, trimmed surface, second seed | `arm-surface-mcp-2` | 13 | 8 | 2 | 0 |
| `both`, trimmed surface | `arm-surface-both-1` | 14 | 4 | 8 | 0 |
| `mcp`, four tools exposed | `arm-verdict-mcp-1` | 20 | 1 | **9** | 0 |
| `mcp`, four tools, second seed | `arm-verdict-mcp-2` | 19 | 2 | 6 | 0 |

Header-free, the `shell` arm still had the original's proof in view for 12
of its 14 agda-algebras solves, and it now cites the original on four rows
where it used to write the proof out (§ 4.6).  With the hints in view, six
of the eight rows the archive restated are `shell` solves written with the
original in view.  The `shell` arm's three solves without it are the
three one-line proofs every arm writes the same way (`lift∼lower = refl`,
`lower∼lift = refl`, `π i = λ x → x i`); among the fifteen with it,
`⊙-hom′` and the two lines of `≤-trans-≅′` are the library's own bodies but
for the prime on the name, and `mon→hom′ m = IsMon.HomReduct (proj₂ m)` is
the library's `mon→hom h = IsMon.HomReduct (proj₂ h)`.  The restated rule
reads references, so a transcribed proof passes it.  The archived arms are
therefore the only construction measurements on these rows, and [#162]'s
agda-algebras columns measure, in part, access to the disk.

The column counts the proof shown, not the file opened.  A call that names
the original's file without showing the proof does not count: a
`definition_of` answer, which says where and not what; a Read of a range
that stops short of the proof; a grep for another name in the file.  That
is why the counts sit below the script readings they replace (16, 6, and 16
on the three [#162] arms, 5 and 15 on the two [#184] arms).  Six solves
differ, one `definition_of` answer on `arm162-mcp-1` and five reads that
stopped short of the proof, and each of the six bodies is either
`π i = λ x → x i` or built from the names the fixture's `using` list
supplies.  Whether a solve with the original in view should count as solved
at all is a decision not yet taken (§ 6).

**Reading this, number by number**.

+  **Solved, tools against no tools: a loss on the count, twice; not on
   construction**.  Header-free, 47 with a shell and 44 with the server;
   with the hints, 50 and 47.  Three rows each time, on one seed of one
   model each time.  The only Sonnet variance measurement is the two
   [#191] seeds of the `mcp` arm (48 and 45 solved), also three rows
   apart, so a three-row difference is within a seed's reach.  And on the
   agda-algebras rows, where the whole difference sits, the `shell` arm had
   the original's proof in view for 12 of its 14 solves (15 of 18 with the
   hints).
+  **Restated, tools against no tools: fewer with a shell; still no evidence
   of construction**.  Header-free, 4 with a shell and 9 with the server;
   with the hints, 0 and 6, and 8 in the archive.  The shell arm's zero did
   not survive the headers' removal (§ 4.6), and neither count was evidence
   of construction: the rule cannot see a transcription, and the `shell`
   arm had the original in view for most of its solves.  The honest
   comparison for this column is between arms that cannot read the
   original, and none has run.
+  **Cost, tools against no tools: still a loss, a smaller one**.
   Header-free, USD 3.99 against 3.42, 17 % more, where the first control
   cost 83 % more (5.28 against 2.88).  Most of the change is the server's:
   lean answers and a trimmed surface came between the two controls (the
   next three bullets).  The shell arm cost more than its first run (345
   turns against 308, 92 thousand output tokens against 70), and the
   headers' removal, the prompt that names the sources, and the seed each
   could account for that; one run cannot say which.  The tools still
   return more text (414,106 characters against 260,271).
+  **With the hints in view**, three measurements came between the two
   controls, each changing the server alone, and each is quoted here as it
   was measured.
+  **The lean re-run: answer size was not the cause** ([#184], PR [#190],
   `arm184-mcp-1` and `arm184-both-1`, Sonnet 5 at the same protocol).  With
   the echo cut, characters per call fell 46 % and 51 % and cost fell 12 %
   and 6 % (USD 4.63 and 4.00 against the shell's 2.88); beside a shell the
   knowledge tools stayed exactly as unused (`definition_of` 0,
   `search_by_name` 1, `exports_of` 2), every verdict again came from
   `check_file`, and solves stayed within variance (46 and 8 restated; 49
   and 2).  The cost that remains is per turn, not per answer: every server
   arm re-reads 22 to 25 thousand cached tokens a turn against the shell
   arm's 10 thousand, which is the fourteen tools' descriptions and schemas
   (68,391 characters before [#190], 77,603 after).  The tool surface was
   the next variable; its re-run is the next two bullets.  The judge's
   `original` column has the original in view for 3 of the `mcp` re-run's
   12 agda-algebras
   solves and 14 of the `both` re-run's 18, against 4 of 14 and 16 of 19 in
   [#162].
+  **The tool surface: a third of the context, and a truncation nobody
   knew about** ([#191], PR [#193], `arm-surface-mcp-1` and `-2`,
   `arm-surface-both-1`, Sonnet 5 at the same protocol).  Claude Code cuts
   every MCP tool description at 2,048 characters, so eleven of the fourteen
   contracts never fully reached a model in any earlier arm (27,808
   characters of them: `fill_hole`'s status rule, `check_file`'s hole
   listing, the wrong-tree refusal).  Stating what the tools share once, in
   the server's `initialize` instructions, and cutting each description to
   its own contract took `tools/list` from 77,603 characters to 24,094
   (plus 1,989 of instructions) and a server arm's per-turn context down by
   a third (22,407 cached tokens a turn to 15,503 and 14,293; the first
   turn 20,016 tokens to 13,037), and cost by 17 % and 19 % (USD 3.83 and
   3.74 against 4.63; `both` 3.55 against 4.00).  The tool mix stayed
   within the spread of the untrimmed runs, though the counts moved: the
   corpus and navigation tools 73 and 55 calls against 53 and 78 before
   (`search_by_name` 23 and 23 against 31; `exports_of` 20 and 12 against
   17), restated 7 and 8 against 6 and 8, and beside a shell those tools
   still unused (2 calls).  Two seeds are not enough to call a shift of
   that size a change in behavior, or to rule one out.  The gap to the
   shell's USD 2.88 did not close, and the trim is kept for what it repairs
   as much as for what it saves.
+  **Four tools: the count moves the route, not the proving** ([#191],
   `arm-verdict-mcp-1` and `-2`, only `check_file`, `fill_hole`, `get_goal`,
   and `type_of` exposed).  The context went below the shell arm's (7,405
   first-turn tokens against 8,263; about 9,600 cached a turn against
   10,060) and the arm still cost USD 3.78 and 3.84, because the subject
   spent 150 more turns (458 and 461 against 308) and 116 thousand output
   tokens against 70: without a search tool it guessed library paths, and
   111 and 97 of its 131 and 125 library reads failed.  It solved 52 and 53
   and restated 1 and 2, against 48 and 45 and 7 and 8 with the fourteen,
   and the five rows that flip in both seeds are rows where, with search
   tools, the subject finds the lemma by name and cites it (restated), and
   without them opens modules until it reaches the original and writes the
   proof out (solved; the original in view for 7 of those 10 subjects, 5 of
   the 10 proofs the library's verbatim).  On the 34 rows with no original
   every arm of every kind solves 31 to 34.  So on the mined rows the
   instrument decides whether a found answer is cited or copied, and the
   count cannot tell a better instrument from easier access; the comparison
   that can is the hard tier ([#189]).  The next cost lever is turns: a
   cheap way to find a definition's source ([#185]'s territory) would remove
   most of those failed reads.
+  **The verdict tool: a win, by revealed preference**.  Offered both, the
   model took **every one of its 55 verdicts from `check_file`** and never
   ran `agda` by hand, in each of the four `both` arms (header-free, and the
   three with the hints).
+  **The knowledge tools, as built: a loss**.  Beside a shell they collapse
   (header-free, `definition_of` 0 calls against 11 without a shell,
   `search_by_name` 4 against 21), because `grep` over the source needs no
   prior knowledge of where a thing is while `definition_of` answers where
   and not what.  Tracked as [#185].
+  **`both` beats `shell` by one row**, header-free (48 and 47) as with the
   hints (51 and 50): within noise; not a claim.

### 4.4  The lane parity

[#163], PR [#174].  `Cmd_give` on the persistent interaction lane against the
batch `fill_hole`, over 80 distinct (obligation, candidate) pairs drawn from
the archived agent probes and the golds, with and without `--safe`:
**0 disagreements**; 2 on the 19 deliberate cases, both explained; rows under
[`reports/lane-give-parity/`], which land with PR [#174].  In that run's
own session a give is 1.6 ms on a stdlib file and 9.7 ms on an agda-algebras
file; a give plus the reload an accepted candidate owes is 103 ms and 402 ms,
against 648 ms and 4,873 ms for the batch `fill_hole` on the same files: 6×
and 12× for an accepted candidate, 328× and 1,419× for a refused one, which
owes no reload.  The issue's earlier figures (1.4 to 4.6 ms, about 220 ms,
2.6 s) predate PR [#173]'s cut of the import closure, which moved both sides.
This measures the server's own machinery; it says nothing about agents, and
it is a win for a lane judgment on the record.  One fact from it to carry:
for 16 of the 55 obligations the committed gold is a multi-clause strategy,
not a term, so no hole-filling judgment of any kind can express it.

### 4.5  The hard tier

[#189], PR [#197].  Fourteen obligations posed for the purpose, in group
theory and universal algebra, with no proof on disk: six in the standard
library's `Algebra.Bundles.Group` vocabulary (`agda-stdlib/novel`) and eight
in agda-algebras' (`agda-algebras/novel`).  Their novelty checks, their
golds, and the four posed rows that were dropped (three proved in
agda-algebras' vocabulary, one not provable as posed) are in the two tiers'
own READMEs, beside the conventions they share in
[`data/benchmarks/README.md`].  Opus 5 ran each arm twice, once with the
fixture headers' hints in view (2026-09-27) and once without them
(2026-09-29, [#219]'s runs 2 and 3), at twice the mined tiers' caps (60
turns, 1,800 s, USD 6.00), each time from frozen server and extractor
binaries.  On this tier the headers carried a `Source:` line, sometimes
naming a lemma to use, and a `Strategy:` line sketching the proof ("one
direction is cong of g; the other is injectivity of g"); PR [#220] moved
both into the tiers' READMEs.  n is fourteen and there is one seed per arm
and per condition, so a difference of a row or two is not a finding.

| | `shell`, hints | `shell`, header-free | `mcp`, hints | `mcp`, header-free | `both`, hints | `both`, header-free |
|---|---:|---:|---:|---:|---:|---:|
| final file checks, statement kept | 14 | 14 | 14 | 14 | 14 | 14 |
| solved | 8 | 10 | 14 | 14 | 8 | 10 |
| lost to the isolation gate | 5 | 4 | 0 | 0 | 6 | 4 |
| lost to the preservation gate | 1 | 0 | 0 | 0 | 0 | 0 |
| turns | 174 | 148 | 143 | 139 | 162 | 174 |
| tool calls | 160 | 134 | 129 | 125 | 148 | 160 |
| USD (list) | 6.41 | 6.31 | 7.82 | 7.71 | 6.62 | 6.56 |

Runs `hard-opus5-shell-1`, `hard-opus5-mcp-1`, `hard-opus5-both-1` (with
the hints; their cost pairs `cost-hard-shell-1`, `cost-hard-mcp-1`,
`cost-hard-both-1`) and `hard219-opus5-shell-1`, `hard219-opus5-mcp-1`,
`hard219-opus5-both-1` (header-free; they ran beside the composition tier's
arms of § 4.7 and share its Opus cost pairs) ([`reports/agent-bench/`]).
The hinted runs' solved counts are as re-judged under the shell audit as
fixed after them (it reads `$?` and a variable the call itself binds to a
literal path), 4 and 7 as run; no archived verdict of an earlier arm moves
under it.

+  **Every arm proves every row, with the hints and without them**.  All 84
   final files type-check under the judge with their statements kept.  On
   this tier Opus 5 is at the ceiling with or without the server, so the
   tier answers whether a frontier model can prove these statements (it
   can) and not whether the tools help it prove, which needs rows that are
   hard for the model (the composition tier of § 4.7 is not one) or a
   weaker model.
+  **The hints were worth nothing measurable**.  The `mcp` pair is the
   clean comparison: its prompts, tools, caps, flags, client (2.1.282), and
   corpora are those of the hinted run, and only the index (the stripped
   headers) and one read root (Agda's primitive modules, PR [#200]) differ.
   It solves 14 of 14 on both sides, in 139 turns against 143 and USD 7.71
   against 7.82, and without the sketches Opus wrote the proofs they
   described: cancellation twice for row 1, `⁻¹-anti-homo-∙` and then
   `⁻¹-involutive` for row 3, and the same one-line proof for row 18 (the
   kernel of an injective composite).  No subject in the six arms cites a
   header line in its visible text.
+  **What separates the counts is the protocol, not the proving**.  With
   the hints, the shell arms' subjects went looking for agda-algebras'
   sources, which the prompt said were on disk without saying where, with
   `find /` or from the repository root, and the isolation gate failed
   those rows as it should (nine across the two arms; one such grep listed
   a row's own gold file by path, row 17, `shell`).  Row 4 was lost in both
   shell arms to programs the audit does not model (`perl -i` on the
   subject's own file, and `git diff`), and one `shell` file edited an
   import line rather than adding one (row 6).  The header-free shell
   prompts name the source directories (PR [#200]), and the searches
   outside the roots fell from nine rows to five: two in `shell` (a
   relative path that climbs out of the worktree, a `find` at the
   repository root) and three in `both` (`find /` for agda-algebras' group
   modules, despite the named directories); the other three isolation rows
   are the audit's limits (`perl -pi` twice and a Python edit, each on the
   subject's own file).  Since the prompts changed, the shell arms' two
   extra solves are a re-baseline, not the headers' effect.  No subject saw
   a gold's text: `gold-leak.py` finds no answer in any of the 84
   transcripts that shows a line of its row's gold proof the subject had
   not written itself, or a line of a tier README.
+  **Which tools, given the server**.  The `mcp` arms located definitions
   with `definition_of` (14 calls with the hints, 18 without) and then read
   the files it named (49 and 45 `Read` calls): the tool answers where and
   not what, so every answer was followed by a read, which is [#185].  They
   took every verdict from `check_file`, probed candidates with `fill_hole`
   (5 and 5), and used `search_by_name` (7 and 10), `exports_of` (7 and 8),
   `type_of` (5 and 1), `normalize` (3 and 0), and `get_goal` (2 and 2);
   `search_by_type` was called once, in the header-free arm, and
   `search_in_scope` never.
+  **Which tools, given both**.  The shell did the knowledge work (86 and 96
   Bash calls; with the hints, 68 of the 86 read library sources), and the
   server gave verdicts (`check_file` for 10 and 9 of the 14 final
   verdicts, `agda` by hand for 4 and 5) and probed candidates
   (`fill_hole`, 9 and 6).  The knowledge tools were called once in each
   arm (`type_of`, then `exports_of`), as on the mined rows (§ 4.3).

The per-row account of the hinted arms (what each subject tried, which
tools it used, where it stopped) is on [#189]; the header-free runs are
reported against them on [#219].

### 4.6  What the fixture headers were worth

[#219], PRs [#220] and [#221].  Every agent run before 2026-09-29 had its
fixture's header in view: `Scaffold.stage` copies the obligation byte for
byte, comments included, and the suite's template put hints in the header.
Neither the loop nor the judge reads comments (the loop parses only
`open import` lines; the judge strips comments before its one textual
gate), so no loop number and no archived verdict depends on them; what
they changed is what a subject was told.  They carried the following:

+  **A `Strategy:` line on every obligation**, sketching the proof, from
   `refl` and "case split on the boolean; each branch is refl" to the hard
   tier's "one direction is cong of g; the other is injectivity of g".
+  **On the haystack tier, `Haystack:` and `Needle:` lines** naming the
   module and the very lemma the tier asks a searcher to find
   (`-- Needle: Data.Bool.Properties.∧-assoc`), a `Note:` naming it again,
   and a paragraph on the tier's design.
+  **On the mined tiers, a `Source:` line** naming the module that holds the
   original, which only 3 of the 21 agda-algebras fixtures import directly.
+  **On the standard-library tier, `Note:` lines**, some naming the key move
   ("`*-distribʳ-+` is the non-local lemma that unlocks the suc case").

What a subject visibly did with them is bounded by what the archive keeps,
which is no thinking text.  Three of the 757 transcripts of the sixteen full
arms quote a header line: `agent-opus5-2` on `haystack-bool-and-assoc-diag`
(`the needle named qualified`; no prompt says "needle"), `arm-surface-both-1`
on `algebras-overture-lower-lift` (`Given strategy hint "refl", let's just try
it`), and `arm-verdict-mcp-2` on `algebras-subalgebras-sup-refl` (`composing is
allowed per "Strategy: composition"`).  The header's lines were stripped for
[#219], and every tier's README keeps what its headers said, per row.  One line
survives on the haystack tier, an inline comment under each module line ("The
haystack: reachable qualified; the `using` list holds decoys only"): it names
no lemma, and the header-free runs had it in view.

The re-run: four arms on the same 55 obligations at the same caps
(`suite219-sonnet5-mcp-1`, `suite219-sonnet5-shell-1`,
`suite219-sonnet5-both-1`, `suite219-opus5-mcp-1`), from one frozen
server, extractor, and class snapshot, zero anomalies, compared with the
runs they replace.

| arm | hints in view: run, solved, restated | header-free: solved, restated | rows with no original (34), then and now | agda-algebras (21), solved and restated, then and now | haystack rows solved with no query before the final check, then and now | needle named before any search, then and now |
|---|---|---|---|---|---|---|
| Sonnet `mcp` | `arm-surface-mcp-1`, 48, 7; `-2`, 45, 8 | 44, 9 | 34 and 32; 33 | 14, 7 and 13, 8; 11, 9 | 11 and 10; 3 | 12 and 12; 7 |
| Sonnet `shell` | `arm162-shell-1`, 50, 0 | 47, 4 | 32; 33 | 18, 0; 14, 4 | not read on a shell arm | 12; 6 |
| Sonnet `both` | `arm162-both-1`, 51, 2 | 48, 5 | 32; 32 | 19, 2; 16, 5 | not read on a shell arm | 12; 6 |
| Opus `mcp` | `agent-opus5-1`, 54, 1 | 55, 0 | 34; 34 | 20, 1; 21, 0 | 5; 1 | 11; 10 |

"No query before the final check" is a session that read its file, edited
it, and checked it, and called nothing else (the demo's reading); "needle
named before any search" is a session whose first mention of the needle in
a tool call came before its first search call of any kind, server or shell
(`header-hints.py`).

**What moved**.

+  **The haystack tier's route**.  Every arm still solves all or all but one
   of the twelve (the misses are edited `using` lists whose files
   type-check), but with the `Needle:` line in view the Sonnet `mcp` arms
   solved 8 to 11 of the twelve without a query before the final check
   (11 in `agent-sonnet5-1`, 10 in `arm162-mcp-1`, 8 in `arm184-mcp-1`,
   11 and 10 in the [#191] seeds), and header-free 3; the subject named the
   needle before any search on every row in every Sonnet arm with the
   hints, and on 7, 6, and 6 rows without them.  The reading that the model
   named "the needle qualified from memory" ([ADR 0001] § 9 and the demo
   page, as first written) was, on most rows, the header.  Without it the model
   searched, and `search_by_name` found the needle.
+  **The agda-algebras rows, from solved to restated**.  Each Sonnet arm
   moved three or four of them: `shell` 18 and 0 to 14 and 4, `mcp` 14 and
   7 (or 13 and 8) to 11 and 9, `both` 19 and 2 to 16 and 5, most on the
   `wholesale` stratum.  On those rows the `Strategy:` line named the
   proof's shape in a word (`pairing`, `application`, `constructor`).  In
   the two shell-bearing arms the subject had the original's proof in view
   on every row that moved, with the headers and without them; with the
   shape named it wrote a proof of that shape, and without it cited the
   original.  So on these rows the line decided whether a found answer was
   written out or cited, which is the restated rule's blind spot (§ 2).  Opus moved the other way, one row: 54 and 1 to 55 and 0.
+  **Output**.  Every header-free Sonnet arm wrote more output than its
   counterpart with the hints: 87 thousand tokens against 77 and 82
   (`mcp`), 92 against 70 (`shell`), 82 against 67 (`both`).

**What did not move**.  The 34 rows with no original: 33, 33, and 32
solved, against 32 to 34 with the hints.  The `both` arm's shape: every
verdict from `check_file`, `agda` never run on the shell, and the knowledge
tools unused beside a shell.  And Opus: all 34 rows with no original, as with the hints, and on the haystack tier the needle named before any search on 10 of 12 rows against 11, since it probed lemmas it named itself with `fill_hole` (15 probes, no search call) where Sonnet searched.

**What a difference can mean here**.  The Sonnet `mcp` arm is the one clean
comparison: its server, prompts, client, caps, and read roots are those of
the two [#191] seeds, so the headers are the one variable, and 44 solved and
9 restated sit one row outside those seeds' spread on each column (45 to 48,
7 to 8).  The two shell-bearing arms changed their prompt too (PR [#200]
names the source directories), and each has one seed a side; the Opus arm
has one a side and more changes besides (the server's lean answers and
trimmed surface, readable sources, `--safe`, client 2.1.282 against
2.1.261).  So what holds is the direction, the same in every arm, and the
haystack route, which moved far beyond any seed's spread; a difference of
three rows in one arm alone is not a finding.

**What the headers were worth, then**: on the haystack tier, the answer to
the tier's question on most rows; on the mined agda-algebras rows, about
three proofs written out rather than cited per Sonnet arm; on everything
else, nothing measurable.  The headers' hints did not make the suite
easier to pass, since the solve counts barely moved, but they did decide
how some of it was passed.

### 4.7  The composition tier

[#160], PRs [#218] and [#225].  Twelve agda-algebras obligations
(`agda-algebras/composition`), found by a program that chains the corpus's
own types (`scripts/python/corpus/mine_compositions.py`) and then read
against the source, posed, and given golds that Agda checks.  Each gold
strings two to four library lemmas together, the row's *needles* (one
`needle:` tag each in the index), through a root lemma with an implicit
*middle point*: a variable its premises share and its conclusion does not
mention, as `y` in `x ≤ y → y ≤ z → x ≤ z`.  The miner checked every
needle against the whole corpus: no lemma closes the statement in one step,
no other lemma does a needle's step from the same inputs, and the loop's
moves cannot prove it.  The loop solves none of the twelve, in the fixed
space and under retrieval with both scorers (`comp160-fixed-1`,
`comp160-retrieval-1`, `comp160-retrieval-idf-1`), because `fill_hole`
refuses a root lemma whose middle point is an unsolved meta; the tier's
README (`data/benchmarks/agda-algebras-composition-v0/README.md`) keeps
those gates and each row's needles, novelty record, and gold.

The agents ran on header-free fixtures, one seed per arm, at the hard tier's
caps (60 turns, 1,800 s, USD 6.00), parallelism 2, from one frozen copy of
the server and the extractor and one snapshot of the driver's classes,
client 2.1.282, each arm after a two-row cost pair.  Zero anomalies; USD
22.60 for the six arms.  n is twelve and there is one seed per arm, so a
difference of a row or two is not a finding.

| | Opus `shell` | Opus `mcp` | Opus `both` | Sonnet `shell` | Sonnet `mcp` | Sonnet `both` |
|---|---:|---:|---:|---:|---:|---:|
| final file checks, statement kept | 12 | 12 | 12 | 12 | 12 | 12 |
| solved | 10 | 12 | 10 | 6 | 3 | 5 |
| lost to the preservation gate | 0 | 0 | 0 | 5 | 9 | 5 |
| lost to the isolation gate | 2 | 0 | 2 | 1 | 0 | 2 |
| needles in the final files (of 33) | 20 | 20 | 22 | 25 | 32 | 26 |
| rows on the gold's whole route | 5 | 5 | 6 | 7 | 11 | 8 |
| turns | 130 | 128 | 148 | 157 | 206 | 179 |
| USD (list) | 4.14 | 4.05 | 4.87 | 2.60 | 3.55 | 3.39 |

Runs `comp-opus5-shell-1`, `comp-opus5-mcp-1`, `comp-opus5-both-1`,
`comp-sonnet5-shell-1`, `comp-sonnet5-mcp-1`, `comp-sonnet5-both-1`, and
the cost pairs `cost-comp-*-1` ([`reports/agent-bench/`]).  "On the gold's
whole route" is a final file that names every needle of its row's gold
(`needle-source.py` in the `running-proof-search-sweeps` skill).

+  **Every arm proves every row**.  All 72 final files type-check under the
   judge with their statements kept, for both models, in every arm.  The
   tier sits at the ceiling of both frontier models, as the hard tier sits
   at Opus's (§ 4.5): it answers whether they can string the library's
   lemmas together (they can) and not whether the tools help them do it.
+  **What separates the counts is the protocol, not the proving**.  The
   preservation gate took 19 Sonnet rows and no Opus row, and each of the 19
   final files differs from its obligation only in `using` lists: every
   needle's module is already imported through a `using` list of decoys,
   and Sonnet appended the needle to that list, which the prompt forbids,
   where Opus added an import line.  The isolation gate took seven rows,
   four of them the subject leaving its roots (a `find /` twice, a `cd` to
   the repository root, and a `find` there that listed three gold
   directories' `.agda-lib` files, never a proof) and three the audit's own
   limits (Python and `xargs` inside the roots, and a grep pattern whose
   Markdown backticks, inside double quotes, read as a command
   substitution).  So the Sonnet counts measure a habit of editing, not
   what the model could prove, and no row of the tier is one on which the
   configurations differ in what the subject proved: a row solved in one arm
   and not in another lost a gate, never the proof.
+  **The needles came from the tools and the sources, not from memory**.
   Of the needles a transcript names, all but three first appear in a tool
   answer: in the `mcp` arms mostly an `exports_of` on a module the fixture
   imports (Sonnet 21 of 33) or a `Read` of a file `definition_of` located
   (Opus 19), and in the arms with a shell a `cat` or a `grep` of
   agda-algebras' sources.  The three exceptions are names guessed from a
   neighbor and handed to `search_by_name` (`≑-trans` beside the fixture's
   `≑-refl`).  That is the reverse of the haystack tier, where Opus named
   the needle from memory on 10 of 12 rows (§ 4.6).
+  **The two models took different routes**.  Sonnet stayed on the gold's
   route (11 of 12 rows with the server, 32 of 33 needles).  Opus did on 5
   or 6 rows; on others it unfolded the relations the needles are about,
   which agda-algebras defines as functions and pairs, and wrote the
   composition pointwise: `λ p → φ≤N (θ⊆φ p)` for row 10, where the gold is
   `≤ⁿ-trans` applied to `normalOf-mono`, and `from A≅B , fromIsSurjective
   A≅B` for row 8, where it is `HomImage-≅' IdHomImage A≅B`.  Rows 8, 9, and
   10 took no needle at all in the Opus `mcp` and `shell` arms.  The miner
   checked that each needle is necessary among the corpus's lemmas, not
   against a term built from the definitions, and on this tier the second
   check is the one that binds.
+  **Row 2 has a second route**.  All six arms proved it with
   `⊧-I-invar`, the decoy in the fixture's own `using` list, in place of
   the gold's `HomImage-≅`: take the identity to the homomorphic image
   first, then carry it across the isomorphism.  The miner compared each
   needle's step with other lemmas from the same inputs, and a route that
   takes the steps in another order escapes that comparison.
+  **The middle point stopped no subject**.  On the gold's route a subject
   supplied it through the feeder's conclusion (`≤-trans x≤y∨z (∨-least y≤w
   z≤w)`), and on the defined relations by naming the endpoints, as the gold
   does (`⊆-trans {θ = f i ∧ φ} {φ = f i} {ψ = ⋁ 𝑨 ℓ₀ f}`).  The loop's
   refusal is `fill_hole` asked for the root lemma with holes for its
   arguments, which a subject that writes both arguments never meets.
+  **Which tools**.  With the server, Sonnet leaned on the knowledge tools
   (`type_of` 26, `definition_of` 21, `exports_of` 18, `search_by_name` 10)
   and Opus on `fill_hole` (20) and `definition_of` (13).  Given both, each
   took nearly every verdict from `check_file` (Opus 11, Sonnet 12 of 12)
   and did its reading on the shell (68 and 57 Bash calls), calling the
   knowledge tools 2 and 13 times in the arm, as on the mined rows (§ 4.3)
   and the hard tier.

The per-row account (each row's verdict and route per arm, where each
needle came from, and the finals) is on [#160].  **What the tier says,
then**: it is below the loop's ceiling by construction and at both models'
ceiling in fact.  Rows the models cannot assemble alone need relations the
proof cannot unfold (a record or an abstract definition), longer chains,
or weaker subjects; this tier's twelve cannot tell the tools apart.

## 5.  How to tell a win from a loss

| question | look at | it is a win for the tools when |
|---|---|---|
| Does the server help a frontier model solve more? | § 4.3, `shell` against `mcp`, solved | `mcp` is higher by more than one seed's noise, with the originals hidden from both.  **Today: no on the count (header-free, 47 with a shell against 44 with the server; with the hints, 50 against 47); the agda-algebras rows are confounded by readable originals, and on the hard tier (§ 4.5, with the hints and without them) and the composition tier (§ 4.7), with nothing to copy, every final file of Opus 5, and on the composition tier of Sonnet 5, checks with or without the server**. |
| Does it help it prove rather than cite? | § 4.3, restated | `mcp` restates fewer, with the originals hidden from both.  **Today: not measured; the shell arm restates fewer (4 against 9 header-free, 0 against 6 with the hints), with the original in view for most of its solves**. |
| Does it make a session cheaper? | § 4.3, USD and bytes | `mcp` costs less.  **Today: no, by 17 % header-free (USD 3.99 against 3.42), from 83 % in the first control.  Answer size was not the cause (PR [#190]); the tool surface was a third of the context and is trimmed (PR [#193], cost 17 to 19 % lower); what remains is turns, and four tools with the context below the shell's still cost more because the subject hunts for files**. |
| Which tools does a model want? | § 4.3, `both` arm per tool | a tool is used when a shell is available too.  **`check_file`: yes.  Knowledge tools: no**. |
| Does retrieval help the loop? | § 4.1, haystack and 43-suite | solves appear under exclusion.  **Haystack: yes, 0 to 6.  Elsewhere: no**. |
| Did the fixture headers' hints change what the agents did? | § 4.6 | the header-free arms differ from the hinted ones by more than a seed's spread.  **The haystack tier's route, yes (3 rows solved with no query before the final check, against 8 to 11); about three agda-algebras rows per Sonnet arm written out rather than cited, in the same direction in every arm; the rows with no original, no** |
| Do the tools help a model assemble a proof from library lemmas? | § 4.7, the composition tier, per arm | a row is solved only with the server, or its needles come only from the server's answers.  **Today: not measurable; every final file checks in all six arms, the needles came from tool answers and source reads alike (not from memory), and Opus often skipped them by unfolding the definitions** |
| Is the loop a baseline for the agents? | nothing | **never**; a different instrument |
| Is a lane judgment as trustworthy as batch? | § 4.4 | parity holds.  **Yes, on 80 of 80**. |
| Is the fixed space's 6/22 a failure? | § 3.1 | it is the vocabulary's ceiling, stated; not a loss |

## 6.  What is not measured

+  **Problems a shell-only model fails**.  Every arm is at or near ceiling on
   this suite (a shell-only Sonnet solves 85 % header-free and 91 % with the
   hints, and its files earn 91 % and 98 %), so the suite cannot show a
   tool's upside on hard, novel, multi-lemma work.  That is the original
   question, and it is still open: on the hard tier of [#189] (§ 4.5), posed
   so that nothing could be copied, a shell-only Opus 5 proves all fourteen
   rows, with the headers' hints and without them, and on the composition
   tier of [#160] (§ 4.7), whose golds string two to four library lemmas
   together, every final file of Opus 5 and of Sonnet 5 checks in every
   arm, so both tiers sit at the ceiling too.  The instruments left are rows
   whose relations a proof cannot unfold (a record or an abstract
   definition, where the composition tier's needles could not be bypassed),
   longer chains, the agda-algebras case study ([#23]), and weaker models
   on the two tiers.
+  **Knowledge tools that return content** ([#185]): the one measured defect
   still without its re-run.  Lean answers ([#184]) were measured by PR
   [#190] and were not the cause (§ 4.3).
+  **The tool surface on the hard tier**: [#191] compared the surfaces on
   the mined rows, where an answer exists in the library to be found and
   the count measures citing against copying; only on rows with nothing to
   find ([#189]) can the fourteen tools, the four, and the shell be told
   apart on proving.  The first such runs (§ 4.5) cannot tell them apart
   either, since every arm proves every row, and neither can the
   composition tier's (§ 4.7), so the four-tool arm was not run there; it
   waits for rows that are hard for the model.
+  **A shell prompt that keeps the subject inside its roots**.  On the hard
   tier the hinted shell arms lost nine rows to the isolation gate because
   the subject searched `/` or the repository root for agda-algebras'
   sources, which the prompt said were on disk without saying where
   (§ 4.5).  The prompt now names them (PR [#200]), and the searches fell
   but did not stop: two subjects of the 55-row Sonnet arms (§ 4.3), five
   rows of the header-free hard arms, and four rows of the composition
   tier's arms still ran `find /` or climbed to the repository root.  The
   gate fails every such row, so each arm's solved count is a lower bound,
   and the final files' count (every one checks, on both new tiers) is the
   figure that measures proving.
+  **A locator beside the four tools, and a `definition_of` that returns
   the text**.  The four-tool arm's 111 and 97 failed library reads are
   what a subject does without `definition_of`, which the fourteen-tool
   arms had and used (16 and 12 calls) and which answers where a definition
   is and not what it says.  No arm has run the subset with a locator added
   to it, and none has run with the content-returning `definition_of` of
   [#185]; the two are separate variables.
+  **Construction, tools against no tools**.  The archived arms could not
   read the originals and the [#162] arms could (§ 4.3), so no run compares
   the tools with their absence on rows the subject cannot copy.  The
   control is a re-run with the originals' defining modules hidden from
   every arm, on the file system rather than by the client's permission
   rules (a shell reads anything).  Until then the judge's `original` column
   says which solves had the original's proof in view (§ 4.3), and a
   `transcribed` gate that refused them is a decision not yet taken
   ([#188]).  A hard tier whose statements have no proof on disk needs
   neither.
+  **Small and local models** ([#27], [#28], [#29]), where a shell is least
   usable and structured verdicts plausibly matter most.
+  **Opus with a shell on the mined rows**.  The mined-tier control was run
   on Sonnet only; Opus with a shell has run only on the hard and
   composition tiers (§ 4.5, § 4.7), where it proves every row.

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
[#173]: https://github.com/formalverification/agda-native-air/pull/173
[#174]: https://github.com/formalverification/agda-native-air/pull/174
[#175]: https://github.com/formalverification/agda-native-air/pull/175
[#184]: https://github.com/formalverification/agda-native-air/issues/184
[#185]: https://github.com/formalverification/agda-native-air/issues/185
[#188]: https://github.com/formalverification/agda-native-air/issues/188
[#190]: https://github.com/formalverification/agda-native-air/pull/190
[#193]: https://github.com/formalverification/agda-native-air/pull/193
[#191]: https://github.com/formalverification/agda-native-air/issues/191
[#189]: https://github.com/formalverification/agda-native-air/issues/189
[#197]: https://github.com/formalverification/agda-native-air/pull/197
[#218]: https://github.com/formalverification/agda-native-air/pull/218
[#225]: https://github.com/formalverification/agda-native-air/pull/225
[#200]: https://github.com/formalverification/agda-native-air/pull/200
[#219]: https://github.com/formalverification/agda-native-air/issues/219
[#220]: https://github.com/formalverification/agda-native-air/pull/220
[#221]: https://github.com/formalverification/agda-native-air/pull/221
