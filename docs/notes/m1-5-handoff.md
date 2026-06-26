<!-- File: docs/notes/m1-5-handoff.md -->

# Issue #13 (M1-5) — Claude Code Hand-off Notes

## 1. Issue Reference

- **Repo:** `agda-native-air`
- **Issue:** [#13] "[M1-5] Curate baseline benchmark — 20 to 50 proof obligations from agda-algebras + agda-stdlib"
- **Branch:** (PR exists; confirm via `gh pr list --state open` and `git branch --show-current`)
- **Milestone:** M1 — AgdaDojang + AgdaMCP + First End-to-End Proofs

## 2. Mission

**Land the open PR for Issue #13.** Two of three acceptance criteria are met; one remains:

| Acceptance criterion | Status |
| --- | --- |
| ≥ 20 benchmark obligations with gold solutions | ✅ (30 committed) |
| `make eval-benchmark` runs deterministically and produces a JSON report | ❌ — this session's focus |
| Benchmark includes obligations at ≥ 3 difficulty levels | ✅ (routine / compositional / non-obvious) |

Out of scope: Issue #49 (pre-public cleanup) is queued next but **must not be started in this session** — it will collide with anything still in flight on #13.

## 3. State of the PR (per prior session — verify against the actual branch)

**Believed to be in place.** Confirm by reading the files:

- 30 proof obligations curated: 20 from `agda-stdlib`, 10 from `agda-algebras`.
- Three-tier difficulty taxonomy: `routine` / `compositional` / `non-obvious`.
- `data/benchmarks/benchmark-index.jsonl` — the manifest.
- `data/benchmarks/README.md` — selection criteria and distribution write-up.
- `EvalBenchmark.scala` — Scala runner using cats-effect, circe, sealed-trait ADTs. Location not 100% confirmed; likely under `strux-driver/src/main/scala/...` or `ml-pipeline/etl/src/main/scala/...`. Locate with:
  ```bash
  git ls-files | grep -i evalbench
  ```
- sbt dependency updates aligned with Spark 4.1.0: `json4s` 4.0.7, `cats-core` 2.12.0, `fs2` 3.10.2.
- A `withFilter` bug in a Scala for-comprehension (tuple destructuring in `<-`) was caught and fixed earlier in PR history — no action needed, just FYI if you see related commits.

**First action:** run

```bash
gh issue view 13
gh pr list --state open
git log --oneline -20
git diff main...HEAD --stat
```

and read enough of the diff to ground yourself before editing anything.

## 4. What Remains

### 4.1 Wire up `make eval-benchmark`

Decision (William): produce **both** targets.

- `eval-benchmark` — runs all 30 obligations end-to-end. Not part of CI (too slow / requires the full Agda env).
- `eval-benchmark-smoke` — runs a small slice (~3 obligations, one per difficulty tier). Wired into `make ci-smoke`.

Follow conventions of existing siblings:

- `eval-proof-completion-smoke-retrieval`
- `train-retrieval-smoke`
- `etl-proof-completion-smoke`

Look at how they set variables, invoke sbt, locate the output, and gate on env. The new targets should mirror that shape — same `${SBT}` / `${PY_RUN}` style, same `&&`/`set -e` discipline, same stdout layout.

### 4.2 Verify determinism of the JSON report

Determinism is the explicit acceptance criterion. Audit `EvalBenchmark.scala` for sources of non-determinism in the *report*:

- **No wall-clock timestamps in the report itself.** Wall-clock duration is required as a metric (per the issue's "wall-clock time" requirement) but rounding helps. Better still: emit `wallClockSeconds` as a diagnostic field in a *sidecar* log, and keep the canonical report deterministic. Discuss with William if a tradeoff is needed.
- **Stable iteration order.** Any `Map`, `Set`, or `groupBy` collection must be sorted (by stable key — `qname`, `module`, `name`, etc.) before serialization. Prefer `SortedMap` or explicit `.toVector.sortBy(...)`.
- **Stable manifest reading order.** Read `benchmark-index.jsonl` line-by-line; do not reorder.
- **No random seeds** unless seeded explicitly and recorded in the report.
- **Stable JSON field ordering.** circe's `Encoder` derivation respects the case-class field order — that's fine — but watch out for `Map[String, X]` fields, which need explicit sorting.

### 4.3 Confirm the JSON report shape

Per the issue, the runner should score: **success rate, iterations, wall-clock time.**

Recommended top-level report shape (verify against what the runner already emits — adapt rather than rewrite):

```json
{
  "schemaVersion": "0.1",
  "benchmarkVersion": "v0",
  "totals": {
    "obligations": 30,
    "successes": <int>,
    "successRate": <float, 4 d.p.>
  },
  "byDifficulty": {
    "routine":       {"obligations": N, "successes": N, "successRate": F},
    "compositional": {"obligations": N, "successes": N, "successRate": F},
    "nonObvious":    {"obligations": N, "successes": N, "successRate": F}
  },
  "byLibrary": {
    "agda-stdlib":   {...},
    "agda-algebras": {...}
  },
  "obligations": [
    {
      "id": "...",
      "module": "...",
      "holeIdentifier": "...",
      "difficulty": "routine",
      "library": "agda-stdlib",
      "success": true,
      "iterations": 1,
      "wallClockSeconds": 0.42
    },
    ...
  ]
}
```

If the runner already emits something close to this, leave it. If it emits something materially different, prefer minimal change.

### 4.4 End-to-end local run

```bash
make eval-benchmark-smoke   # should pass quickly, suitable for CI
make eval-benchmark         # full run on 30 obligations; capture report
```

Capture one successful report run and ensure it round-trips deterministically:

```bash
make eval-benchmark > /tmp/report-1.json
make eval-benchmark > /tmp/report-2.json
diff /tmp/report-1.json /tmp/report-2.json   # must be empty
```

(Adjust to whatever the actual report destination is.)

### 4.5 Update `data/benchmarks/README.md`

Add a "Running the benchmark" section: how to invoke each target, where the report lands, how to interpret the fields. Keep it terse — selection criteria docs already exist and should not be duplicated.

### 4.6 Final pre-merge

```bash
make ci-smoke   # must pass
git status      # check for stray files
```

Commit message convention: prefix with `[M1-5]`. Reference `#13`.

## 5. Repo Conventions to Follow

- **Functional Scala**: immutable structures, `IO` / `EitherT` for effects, no `var`, no exceptions as control flow.
- **Doc-comment headers** on every new or substantially edited file: purpose, project fit, brief design notes. Liberal inline comments.
- **Makefile**: targets use `${SBT}`, `${PYTHON}`, `${PY_RUN}` variables (see top of the file); `.PHONY` declared; `make help` documentation lines kept tidy.
- **sbt invocation pattern**: `sbt -Dsbt.supershell=false -f <sub>/build.sbt "runMain <fqcn> -- <args>"`. Match the style of `eval-proof-completion-smoke-retrieval`.
- **Output paths**: align with existing `eval-*` outputs — likely `data/benchmarks/reports/` or similar; check what the runner currently writes.
- **No new dependencies** unless absolutely required. The dep graph was just aligned for Spark 4.1.0.

## 6. Files to Read First

```bash
gh issue view 13
gh pr view                                      # current PR for the branch
git diff main...HEAD --stat

# locate and read the runner
git ls-files | grep -i evalbench
# then: cat or view the file

# the manifest + fixtures
cat data/benchmarks/benchmark-index.jsonl | head -5
cat data/benchmarks/README.md
ls data/benchmarks/agda-stdlib-v0/ | head
ls data/benchmarks/agda-algebras-v0/ | head

# existing Makefile patterns
grep -n -E '(eval-|smoke)' Makefile | head -30
grep -n -E '\.PHONY' Makefile | head
```

## 7. Open Decision Points (escalate to William if uncertain)

1. **Report destination.** Stdout, a fixed file path, or both? Prior `eval-*` targets probably set a precedent — match it.
2. **Smoke-slice selection.** Pick one obligation per difficulty tier from the smaller library (likely `agda-algebras`, to avoid pulling in stdlib paths) for `eval-benchmark-smoke`. If the runner already supports `--filter` or `--ids`, use that; otherwise consider a minimal `benchmark-index-smoke.jsonl`.
3. **Wall-clock in report.** If determinism vs. metric reporting becomes a real conflict, lean toward sidecar diagnostics + deterministic core report. Don't drop wall-clock entirely — it's an explicit metric per the issue.
4. **Iterations metric.** The runner needs to know what counts as an "iteration." For a fixture-driven benchmark with gold solutions, this is likely `1` per obligation (single check); confirm with William before implementing anything more elaborate.

## 8. Out of Scope

- Issue #49 (pre-public cleanup). Queued next.
- Refactoring `EvalBenchmark.scala` beyond what's needed for the wiring.
- New benchmark obligations beyond the existing 30.
- Premise selection / local-model integration (M2 work).
- Touching `experiments/archive/` or any active Scala/Haskell/Python sources outside the runner and Makefile.

## 9. When to Stop and Ask

- Before making any structural change to `EvalBenchmark.scala` (signatures, ADTs, public API).
- Before adding a dependency.
- Before changing fixture format or the contents of `benchmark-index.jsonl`.
- If `make ci-smoke` regresses for a non-obvious reason.

## 10. Useful Commands (cheat sheet)

```bash
# state
gh issue view 13
gh pr view
git status
git diff main...HEAD --stat

# build + test
make ci-smoke
make help | grep -E '(eval|smoke|bench)'
sbt -f strux-driver/build.sbt "Test/compile"

# eventually
make eval-benchmark-smoke
make eval-benchmark
```

