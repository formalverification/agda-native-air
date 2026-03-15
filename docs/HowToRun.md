<!-- File: docs/HowToRun.md -->

# How To Run (Developer Guide)

This is the "copy/paste runnable" guide to running **agda-native-air** end-to-end.

Companion docs:
- `MANIFESTO.md` — vision
- `PLAN.md` — roadmap + milestones
- `docs/representation.md` — data contracts / schemas

---

## 0) Repo mental model (what runs what)

This repo has three “lanes” that connect:

1) **Extraction (Scala driver + Haskell backend)**  
   - Haskell backend (`agda-backend-jsonl`) builds `agda-json` (Agda-as-a-library → JSONL).
   - Scala driver (`proof-parser`, main: `proofparser.extract.AgdaJsonlDriver`) runs `agda-json` per module, validates output, writes logs + manifests.

2) **Transform / utilities (Scala, proof-parser)**  
   - `extract`, `transform`, `a2t`, dataset stats, premise eval.

3) **ML / serving (Python + Spark ETL)**  
   - `etl` in `ml-pipeline` (Spark) → Parquet features
   - `train` / `filter` / `finetune-dataset` (Python) → model checkpoint
   - `serve` (FastAPI)

---

## 1) Recommended environment: Nix shells

Most “it just works” runs are inside a Nix shell.

### 1.1 All-in-one dev shell

```sh
nix develop .#all
```

### 1.2 Backend-only shell

```sh
nix develop .#backend
```

> The Makefile also provides “Nix wrappers” that scrub `LD_LIBRARY_PATH` so nested nix calls don’t explode:

* `make extract-lib-nix`
* `make extract-lib-smoke-nix`

---

## 2) First commands to run (sanity)

### 2.1 See what you’ve got

```sh
make help
make diag
```

### 2.2 Fast correctness check (recommended)

Inside the right shell (e.g. `nix develop .#all`):

```sh
make check
```

Outside nix (Makefile will run checks inside the proper shells):

```sh
make check-nix
```

What `check` does:

* `test-proof-parser`
* `backend-test`
* `backend-smoke`

---

## 3) Backend (Haskell) build + tests

### 3.1 Build the backend executable

```sh
make build-agda-json
```

### 3.2 Locate the backend binary

```sh
make show-agda-json-bin
```

### 3.3 Run backend tests

Run the Haskell backend test suite with:

```sh
make backend-test
```

By default, backend tests **preserve their JSONL outputs** for inspection under:

```
data/test-output/agda-backend-jsonl/
```

To disable output retention: `make backend-test BACKEND_TEST_KEEP=0`  
To clean retained outputs: `make backend-test-clean`

### 3.4 Backend smoke

```sh
make backend-smoke
```

### 3.5 Clean backend artifacts

```sh
make backend-clean
```

---

## 4) Proof-parser tests (Scala)

Canonical Scala test entrypoint:

```sh
make test
# (alias of test-proof-parser)
```

Or explicitly:

```sh
make test-proof-parser
```

There’s also an integration test target:

```sh
make test-integration
```

Run the whole suite (Scala + Python + AgdaDojang + backend tests):

```sh
make test-all
```

---

## 5) Corpus Extraction and Proof Completion

### 5.1 Corpus Extraction (the "real" pipeline path)
This is the main, resumable extraction path that writes

+  `data/<LIB_NAME>/raw/jsonl/*.jsonl`
+  `data/<LIB_NAME>/raw/logs/*`
+  `data/<LIB_NAME>/manifests/<timestamp>.json`

#### 5.1.1 Full corpus extraction (agda-algebras by default)

```sh
make extract-lib
```

**Key behavior**.

+  Builds `agda-json` (via nix if configured).
+  Generates module list via `make agda-algebras-metadata`.
+  Runs Scala `AgdaJsonlDriver` with `--runner spark` and local master.
+  Writes a manifest JSON with exit code + Agda version + git rev.

#### 5.1.2 Smoke extraction (first N modules)

```sh
make extract-lib-smoke \
  SMOKE_N=25              # (optional) controls how many modules
```

#### 5.1.3 Run extraction via Nix wrapper (from outside nix shell)

```sh
make extract-lib-nix
make extract-lib-smoke-nix
```

#### 5.1.4 Fail-fast vs keep-going

By default the driver continues through failures (and records them). To fail fast:

```sh
make extract-lib FAIL_FAST=1
```

#### 5.1.5 Resume control

The top-level knob is `RESUME` (default `1`). To force no resume:

```sh
make extract-lib RESUME=0
```

(Internally this adds `--no-resume` to driver args.)

#### 5.1.6 Parallelism

```sh
make extract-lib PAR=16
```

### 5.2 Proof-completion evaluator (AgdaDojang fixtures)

The proof-completion evaluator is the core demo of the project's propose → check
loop.  It runs AgdaDojang's `reportGoalCtx` macro to extract `(goal, context)`
from each `{!!}` hole in a fixture file, calls a policy backend to get candidate
terms, and typechecks each candidate in Agda.

> **Prerequisite:** run inside `nix develop` (or `nix develop .#all`).
> The evaluator requires Agda on PATH with the correct library configuration.

#### 5.2.1 Smoke test (single fixture, fast)

```sh
make eval-proof-completion-smoke
```

This runs only `FixtureLambda.agda` with `--max-holes 1` and a 10-second timeout.
Expected result: 1 hole solved.

#### 5.2.2 Full fixture evaluation (all fixtures)

```sh
make eval-proof-completion
```

This runs all `data/agda/Fixture*.agda` files through the evaluator.
Expected result: all fixtures pass except `FixtureFail01` (which is an expected
failure, marked `xfail`).

#### 5.2.3 What the evaluator does

For each fixture file, the evaluator:

1. Finds `{!!}` holes in the source.
2. For each hole, injects `reportGoalCtx` and runs Agda to extract a structured
   `(goal, context)` request from Agda's error output.
3. Sends the request to the policy backend (default: `policy_fixture.py`).
4. Tries each candidate term by substituting it into the hole and typechecking.
5. If a candidate typechecks, the hole is marked solved and the source is patched.
6. Repeats until all holes are solved or candidates are exhausted.

#### 5.2.4 Output artifacts

The following results are written to `agda-dojang/_build/eval-proof-completion/<run-id>/`:

+  `fixtures.jsonl` — one row per fixture with summary (holes, solved, final status, elapsed ms);
+  `results.jsonl` — one row per hole attempt with full details (goal, candidate, status, rc, log path);
+  `logs/<fixture>/hole-<N>/` — per-hole Agda output for debugging.

Both JSONL files use schema version `eval-proof-completion.v0`.

#### 5.2.5 Overriding evaluator knobs

The evaluator is controlled by Makefile variables which may be overriden on the
command line, as follows:

```sh
make eval-proof-completion \
  EVAL_FIXTURES="../data/agda/Fixture01.agda" \
  EVAL_MAX_HOLES=2 \
  EVAL_K=3 \
  EVAL_TIMEOUT=15 \
  EVAL_POLICY="python3 python/tools/policy_fixture.py" \
  EVAL_RUN_ID=my-run
```

#### 5.2.6 Fixture files

Committed fixtures live in `data/agda/`.  Each fixture imports from
`AgdaDojang.Debug` (for the `reportGoalCtx` macro) and contains one or more
`{!!}` holes.  The fixture policy (`policy_fixture.py`) uses simple heuristics
to solve them: assumption matching (goal type matches a context binder), `refl`
for equality goals, and `tt` for unit goals.

| Fixture | Holes | What it tests |
|---------|-------|---------------|
| `Fixture01` | 3 | assumption, ⊤ → tt, ≡ → refl |
| `Fixture02–05` | 2–3 | variations on assumption and equality |
| `FixtureHoles` | 4 | sequential multi-hole solving |
| `FixtureLambda` | 1 | lambda introduction |
| `FixtureLet` | 1 | let-bound context |
| `FixtureWhere` | 1 | where-clause context |
| `FixtureStdlibBooleanAlgebra` | 3 | stdlib boolean algebra obligations |
| `FixtureStdlibBooleanAlgebraMinimal` | 3 | minimal variant of the above |
| `FixtureFail01` | 1 | **expected failure** (no policy can solve it) |


---


## 6) “Small” extraction / transforms (non-corpus path)

These targets run mains directly and are useful for quick demos.

### 6.1 Extract a single file/dir using `AgdaExtractorMain`

Defaults:

* input: `proof-parser/src/test/resources/agda-example.agda`
* output: `data/train.jsonl`

```sh
make extract
```

Override input/output:

```sh
make extract EXTRACT_INPUT=/path/to/Thing.agda TRAIN_DATA=/tmp/out.jsonl
```

Library wrappers:

```sh
make extract-stdlib
make extract-categories
```

### 6.2 Transform Agda2Train reflection JSON → JSONL

```sh
make transform
```

### 6.3 Legacy reducer path

```sh
make a2t
```

---

## 7) ETL (Spark) and ML (Python)

### 7.1 Spark ETL: JSONL → Parquet

Requires `DATA_TRAIN` to exist (run `make extract` first):

```sh
make etl
```

This runs:

* `cd ml-pipeline`
* `sbt "project etl" "runMain PreprocessAgda"`
  and expects:
* output at `ml-pipeline/features/train.parquet`

### 7.2 Python venv management

Default behavior: Makefile creates/uses `ml-pipeline/.venv` (unless `USE_VENV=0`).

```sh
make train
```

Useful knobs:

* `USE_VENV=1` (default) → use repo venv
* `USE_VENV=0` → assume you activated an env already
* `TORCH_MODE=cpu` (default), `TORCH_MODE=pypi`, `TORCH_MODE=skip`

Examples:

```sh
make train TORCH_MODE=pypi
make train USE_VENV=0
```

### 7.3 Filter + finetune dataset builder

```sh
make filter
make finetune-dataset
```

You can enforce minimum lengths:

```sh
make filter MIN_TYPE_LEN=10 MIN_PROOF_LEN=10
```

### 7.4 Serve (FastAPI)

```sh
make serve
```

This requires:

* model checkpoint exists at `ml-pipeline/models/model.pt`
* `ml-pipeline/python/api/app.py` exists

---

## 8) One-command “pipeline” runs

### 8.1 Default pipeline (uses `make extract` path)

```sh
make pipeline
```

Pipeline does:

1. `extract`
2. dataset stats
3. `filter`
4. `finetune-dataset`
5. `train` (on filtered)

### 8.2 Library-specific pipeline runs

```sh
make train-stdlib
make train-algebras
make train-categories
```

---

## 9) Dataset utilities

### 9.1 Stats

```sh
make dataset-stats
```

Override dataset:

```sh
make dataset-stats DATASET=/path/to/train.jsonl TOP=50
```

### 9.2 Premise evaluation

```sh
make premise-eval
```

Quick version (no auto-extract):

```sh
make premise-eval-quick DATASET=/path/to/train.jsonl K=10 SPLIT=90
```

Sample dataset helpers:

```sh
make gen-sample
make dataset-stats-sample
make premise-eval-quick-sample
make smoke-sample
```

---

## 10) Smoke, audit, probe-all

### 10.1 Curated smoke suite (writes logs)

```sh
make smoke
```

Or in nix:

```sh
make smoke-nix
```

Customize smoke targets:

```sh
make smoke SMOKE_TARGETS="gen-sample extract test backend-smoke"
```

### 10.2 Audit (curated always-works targets)

```sh
make audit
make audit-nix
```

### 10.3 Probe-all (attempts many targets, writes logs)

```sh
make probe-all
```

---

## 11) Where outputs land

### 11.1 Corpus extraction outputs

Default library: `LIB_NAME=agda-algebras`

* Raw root:

  * `data/agda-algebras/raw/`
* JSONL:

  * `data/agda-algebras/raw/jsonl/*.jsonl`
* Logs:

  * `data/agda-algebras/raw/logs/`
* Manifests:

  * `data/agda-algebras/manifests/<timestamp>.json`

### 11.2 Non-corpus extract outputs

* `data/train.jsonl` (default)

### 11.3 ML outputs

* Parquet: `ml-pipeline/features/train.parquet`
* Models: `ml-pipeline/models/model.pt`
* Finetune dataset: `data/finetune.jsonl` (or overridden)

---

## 12) Debugging playbook

### 12.1 “AgdaJsonlDriver exited 0 but produced no JSONL”

The Makefile already treats this as an error (exit code 2). Next steps:

* check `data/<LIB>/raw/logs/` for per-module logs
* check the manifest in `data/<LIB>/manifests/`
* verify `JAVA_HOME` is set (the Makefile will fail loudly if empty)
* verify `AGDA_LIB_DIR` points to the directory containing `agda-dojang/agda/libraries`

### 12.2 Backend binary resolution issues

The Makefile resolves `agda-json` by running:

* `cabal list-bin exe:agda-json` (inside backend shell)
* then filters to the last line that ends in `agda-json`

If it can’t resolve:

* run `make show-agda-json-bin`
* run `command -v agda-json`
* run `make backend-test` (ensures build is sane)

### 12.3 sbt / JDK weirdness

Targets `extract-lib` and `extract-algebras-backend` expect a pinned JDK:

* `JAVA_HOME` / `SBT_JAVA_HOME`

If sbt launches the wrong java:

* confirm `JAVA_HOME` inside your `nix develop .#all`
* try `make diag`

### 12.4 Spark not found

If you see `spark-submit not found`:

* run inside `nix develop .#all`
* or install Spark and ensure `spark-submit` is on PATH
* check with: `make _check-spark`

### 12.5 GitHub CLI issue export fails (repo “not found”)

If `gh` mysteriously can’t see the repo, the fix is usually:

```sh
env -u GH_TOKEN -u GITHUB_TOKEN gh auth status
```

because env tokens can shadow your stored auth.

---

## 13) Cleaning

```sh
make clean   # remove a few generated files
make wipe    # remove generated artifacts (features/models/etc.)
make tree    # repo tree, excluding build dirs
```

---

## 14) “Known good” sequences

### 14.1 Quick confidence check

```sh
nix develop .#all
make check
make extract-lib-smoke
```

### 14.2 End-to-end (small path)

```sh
nix develop .#all
make pipeline
```

### 14.3 End-to-end (corpus path + ML later)

```sh
nix develop .#all
make extract-lib
# (then once ETL/ML is ready for that corpus)
make etl
make train
```
