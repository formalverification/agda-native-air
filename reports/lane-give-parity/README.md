<!-- File: reports/lane-give-parity/README.md -->

# Can the interaction lane judge a candidate?  The parity archive

This directory holds the measurement behind issue [#163]: for one candidate on
one file, does the interaction lane's reading of `Cmd_give` name the same class
that a batch `fill_hole` names?  Every row here was produced by
`make lane-give-parity`, whose driver is `agda-mcp/parity/Main.hs`, and both
columns of every row are the shipped code: the batch side is
`AgdaMCP.Tools.ProofState.handleFillHole`, the function the `fill_hole` tool
dispatches to, and the lane side is `AgdaMCP.Interaction.giveCandidate` over a
real `agda --interaction-json` child.

Nothing here decides anything.  The two-lane policy (ADR 0002 § 2, decision 1)
is unchanged, no tool sends a give, and whether the lane may judge is a
decision for a reader of these rows.

## What was replayed, and why it is not what the issue asked for

The issue asks for "every depth-0 candidate of the archived proof-search
sweeps".  Those rows are not in the repository: the sweeps write under
`data/benchmarks/reports/`, which is gitignored, and their numbers survive only
as tables in issue comments and in ADR 0001 § 9.  Two committed sources replace
them, and together they are better, because the archive supplies candidates a
frontier model actually proposed and the golds supply candidates that are known
to be right:

+  **The agent-bench probe rows**, `reports/agent-bench/agent-*/results.jsonl`:
   100 rows across three arms, each a real `fill_hole` a subject issued.
+  **The 55 benchmark golds**, as the `goldTerm` field of
   `data/benchmarks/benchmark-index.jsonl`.  A `goldTerm` is a *candidate*
   exactly when splicing it over the obligation's hole reproduces the gold file
   (whitespace-normalized); 39 do, and the other 16 are sentences describing a
   multi-clause strategy (`induction on xs; base refl, step cong suc IH`).  The
   16 are replayed anyway and labeled `gold-prose`: a candidate that does not
   parse is a class both lanes have to answer, and one an agent can produce.

Those 155 rows are 80 distinct (obligation, candidate) pairs over all 55
obligations.  Running the identical judgment twice measures nothing, so the
duplicates collapse; each row records how many archived rows it stands for
(`occurrences`) and which statuses they carried (`archivedStatus`).

## The archived `status` is not a second opinion

An archived row's `status` was measured against the work file *as that subject
had it at that moment*, and a subject could edit the file.  It is therefore not
comparable to a verdict on the committed obligation, and this measurement does
not treat it as one: both columns of every row are measured here, on the
pristine obligation, and the archived status is carried alongside as
provenance.  Two facts fall out of comparing them anyway, and both are recorded
in the issue's parity comment:

+  An archived `crash` is not a verdict.  `Audit.attemptRows` files `crash`
   whenever the `fill_hole` reply was an error or did not decode, so all 16
   archived crashes are addressing failures (three calls passed no hole
   address; thirteen named a position where the subject's own edit had already
   removed the hole), with `elapsedMs: 0` and `rc: -1` as the decoder's
   defaults rather than measurements.  No `agda` ran for any of them.
+  One archived `ok` is a `type_error` here, and the transcript says why: the
   subject added `⊙-injective` to an import list before calling `fill_hole`.
   On the committed obligation the name is not in scope, and both lanes say so.

## What a file holds

| file | contents |
|---|---|
| `parity-rows.jsonl` | the 80 committed candidates, one row per candidate, with the committed flag set |
| `parity-rows-safe.jsonl` | the same 80 with `--safe` added to the per-load argv of both lanes |
| `probe-rows.jsonl` | the six `Cmd_give` rows of the issue's own probe table, replayed through the real lane |
| `deliberate-rows.jsonl` | the constructed cases: force flags, sub-holes, two holes, a `where` clause, an extended lambda, string escaping, a multi-line candidate, and a hole constrained by a later definition.  Their fixtures, where the benchmark suite has no shape for them, are `agda-mcp/parity/fixtures/` |
| `cost-{stdlib,algebras}-{1,2,3}.jsonl` | three processes per tier, three accepted and three refused candidates each, which the cost table is read off |

Each row carries, beside the candidate and its provenance: `laneClass`,
`laneGiven` (whether a `GiveAction` arrived, that is, whether the hole was
consumed), `laneText` (Agda's own rendering of the given term, which is not the
candidate's text), `laneMetas`, `laneCodes`, `laneGiveUs` and `laneResetUs`;
and `batchStatus`, `batchCodes`, `batchMessage`, `batchRemaining` and
`batchMs`.

The points a give leaves behind are three fields, and the distinction is
load-bearing.  `laneRemainingPoints` is every interaction point Agda announced
after the give; `laneNewPoints` counts only those the candidate introduced,
which is the set difference against the load's own point list (Agda's ids are
stable across a give, so it is exact); and `lanePoints` lists each one as
`{id, new, range}`.  A give into one hole of a two-hole file leaves the other
standing, so the two counts differ, and so do the coordinate systems: a **new**
point's range is in the *candidate expression's* coordinates (giving
`s≤s {!!}` reports `1.5-9`, where the sub-hole sits inside the string), while a
point that was already open keeps its range in the **file**.  The wire shape is
identical, so any tool that promises a re-anchored hole list turns on telling
them apart.  `two-holes-sub-hole` in `deliberate-rows.jsonl` carries one of
each in the same row.

`agree` is `null` rather than `false` when one of the two lanes could not answer
at all, and equally when the batch status is `timeout` or `crash`: those are
facts about a process, the lane's reading has no counterpart for either, and
recording one as a disagreement would inflate the count the table is read on.
No row in this archive carries one.

`laneHere` and `laneUnreadable` are the two conjuncts the lane reading uses to
fail closed, carried as evidence rather than only consulted: whether the give
could be shown to have landed on the point it was aimed at, and how many lines
of its response window were not JSON.  Both hold on every row here (`laneHere`
true on every accepted give, `laneUnreadable` zero throughout), which is what
makes them safe conjuncts rather than a source of false type errors.

## What the two disagreements are, and are not

`deliberate-rows.jsonl` carries two rows where the lanes differ, and they are
different kinds of thing.

+  **`where-clause`**: batch `ok`, lane `type_error`
   (`[Interaction.UnexpectedWhere]`).  A hard capability limit: `Cmd_give`
   parses an expression and a `where` block is a clause tail.  The lane calls
   a good candidate bad, which costs a solve and never a false claim.  No
   committed candidate has the shape.
+  **`later-use-hole`**: batch `type_error`, lane `ok`, and this one is **not**
   a false green, which is what the four rows around it establish.  The
   candidate `suc {!!}` on `LaterUse.agda` is a partial fill whose remaining
   hole is pinned by the file's later definition, and it *can* be completed:
   `suc 0` typechecks, exit 0.  The lane is not blessing sub-holes blindly
   either, which is what `later-use-hole-dead` and `-dead-deeper` are for:
   `suc (suc {!!})` and `suc (suc (suc {!!}))` can be completed by nothing at
   all, and the lane refuses both, agreeing with batch.  What the two lanes
   are doing is answering different questions about a partially filled hole:
   batch asks "is the module green, tolerating open interaction holes only",
   so any residual constraint is a type error (ADR 0002 § 3); the lane asks
   "does anything Agda can decide right now contradict this candidate", so a
   constraint that depends on an unfilled hole is deferred rather than counted
   against it.  On a candidate that completes the proof the two coincide, which
   is the 80 of 80 above.

Two things the run refuses rather than works around, because the table's
product is a count and a count that quietly shrinks is worse than a run that
stops: a malformed row in either committed input, and an archived probe row
naming a benchmark id the index does not define.  Each names the file and the
row.  Each candidate is also its own lane request, so `--timeout` bounds one
judgment on both lanes rather than a whole obligation on one of them.

`agree` compares the *class*.  The two lanes reach it by different routes on 17
of the 80 rows, and the error-code lists are what says so: a semicolon in a
candidate ends a declaration when spliced into a file and breaks an expression
parse when given, and leftover metas are a second batch diagnostic but the
lane's invisible goals.  The issue's parity comment reads those 17 out.

## Reproducing

```sh
nix develop .#backend
BACKEND_USE_NIX=0 make lane-give-parity
BACKEND_USE_NIX=0 make lane-give-parity LANE_PARITY_CASES=agda-mcp/parity/deliberate-cases.json \
  LANE_PARITY_OUT=reports/lane-give-parity/deliberate-rows.jsonl
```

The run takes a few minutes: the batch side is a cold `agda` per candidate,
about 5 s on the agda-algebras tier.  A malformed row in either committed
input stops it, naming the file and the line, rather than quietly producing a
smaller table; measured, two truncated lines cost 16 candidates and a whole
obligation before that was so.  It changes nothing on disk.  `fill_hole`
restores under `bracket_` the file it patched, and the lane reloads after every
give that consumed a hole, so `git status` is clean afterwards; if it is not,
that is itself a finding.

[#163]: https://github.com/formalverification/agda-native-air/issues/163
