<!-- File: docs/HowToRun.md -->

# How To Run (Developer Guide)

This is the "copy/paste runnable" guide to running **agda-native-air** end-to-end.

**Companion docs**.  
+ [`MANIFESTO.md`](MANIFESTO.md) — vision
+ [`PLAN.md`](PLAN.md) — roadmap + milestones
+ [`representation.md`](representation.md) — data contracts / schemas
+ [`architecture.md`](architecture.md) — system architecture overview

---

## Quick Start

```sh
git clone git@github.com:formalverification/agda-native-air.git
cd agda-native-air
nix develop
```
<!-- doc-test: quick-check -->
```sh
make check
```
<!-- doc-test: quick-eval-smoke -->
```sh
make eval-proof-completion-smoke
```

> **Note:** most targets require the Nix shell.  If a command fails with a
> missing binary (e.g., `agda`, `sbt`), enter `nix develop` first.

---

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [0.  Repo mental model (what runs what)](#0--repo-mental-model-what-runs-what)
- [1.  Recommended environment: Nix shells](#1--recommended-environment-nix-shells)
- [2.  First commands to run (sanity)](#2--first-commands-to-run-sanity)
- [3.  Backend (Haskell) build + tests](#3--backend-haskell-build--tests)
- [4.  Strux driver tests (Scala)](#4--strux-driver-tests-scala)
- [5.  Corpus Extraction and Proof Completion](#5--corpus-extraction-and-proof-completion)
- [6.  "Small" extraction / transforms (non-corpus path)](#6--small-extraction--transforms-non-corpus-path)
- [7.  ETL (Spark) and ML (Python)](#7--etl-spark-and-ml-python)
- [8.  One-command workflows](#8--one-command-workflows)
- [9.  Dataset utilities](#9--dataset-utilities)
- [10.  Smoke, audit, probe-all](#10--smoke-audit-probe-all)
- [11.  Where outputs land](#11--where-outputs-land)
- [12.  Debugging playbook](#12--debugging-playbook)
- [13.  agda-mcp — AI-assisted proof development ](#13--agda-mcp--ai-assisted-proof-development)
- [14.  Known good sequences](#14--known-good-sequences)
- [15.  Cleaning](#15--cleaning)

<!-- markdown-toc end -->




## 0.  Repo mental model (what runs what)

This repo has three "lanes" that connect:

1.  **Extraction (Scala driver + Haskell backend)**  
    - Haskell backend (`agda-strux`) builds `agda-json` (Agda-as-a-library → JSONL).
    - Scala driver (`strux-driver`, main: `struxdriver.extract.AgdaJsonlDriver`) runs `agda-json` per module, validates output, writes logs + manifests.

2.  **Transform / utilities (Scala, strux-driver)**  
    - `extract`, `transform`, `a2t`, dataset stats, premise eval.

3.  **Proof completion (AgdaDojang + Python)**  
    - `eval-proof-completion` / `eval-proof-completion-smoke` — the propose → check loop.
    - Deterministic fixture policy + retrieval policy.

4.  **ML / ETL (Python + Spark)**  
    - `etl` in `ml-pipeline` (Spark) → Parquet features
    - `train-retrieval-smoke` → deterministic retrieval artifact
    - `filter` → cleaned dataset
    - Legacy training and FastAPI server archived to `experiments/archive/`.

---

## 1.  Recommended environment: Nix shells

Most "it just works" runs are inside a Nix shell.

### 1.1.  All-in-one dev shell

```sh
nix develop .#all
```

### 1.2.  Backend-only shell

```sh
nix develop .#backend
```

> The Makefile also provides "Nix wrappers" that scrub `LD_LIBRARY_PATH` so nested nix calls don't explode:

+  `make extract-lib-nix`
+  `make extract-lib-smoke-nix`

### 1.3.  Registering external Agda libraries (optional)

Every Agda-equipped shell registers `standard-library` and the repo-local
`agda-dojang` by default.  To type-check against an external library from a local
checkout — `agda-algebras`, `agda-categories`, or `TypeTopology` — point the
matching `*_ROOT` environment variable at the **library root** (the directory that
contains the `.agda-lib` file) before entering the shell:

```sh
AGDA_ALGEBRAS_ROOT=~/git/ualib/agda-algebras/master  nix develop .#backend
AGDA_CATEGORIES_ROOT=~/git/agda-categories           nix develop .#backend
AGDA_TYPETOPOLOGY_ROOT=~/git/TypeTopology            nix develop .#backend
```

The shell hook searches each root for a `.agda-lib`, registers what it finds, and
prints a summary.  Libraries that are not registered show how to enable them:

```
   Agda libraries:
     * standard-library (Nix-managed)
     * agda-dojang (repo-local)
     - agda-algebras: set AGDA_ALGEBRAS_ROOT to enable
     - agda-categories: set AGDA_CATEGORIES_ROOT to enable
     - TypeTopology: set AGDA_TYPETOPOLOGY_ROOT to enable
```

Once a library is registered (its line changes to a `*` entry), a module that
imports it type-checks directly — e.g. `agda MyModule.agda` or
`nix develop .#backend --command agda MyModule.agda`.

Reproducible, no-clone registration (pinning the library in the flake so
collaborators need no local checkout) is deferred future work, tracked in
[#54](https://github.com/formalverification/agda-native-air/issues/54).

---

## 2.  First commands to run (sanity)

### 2.1.  See what you've got

<!-- doc-test: help -->
```sh
make help
```
<!-- doc-test: diag -->
```sh
make diag
```

### 2.2.  Fast correctness check (recommended)

Inside the right shell (e.g. `nix develop .#all`):

```sh
make check
```

Outside Nix (Makefile will run checks inside the proper shells):

```sh
make check-nix
```

`check` does the following:

+  `test-strux-driver` (Scala tests in `strux-driver/`);
+  `backend-test` (Haskell tests in `agda-strux/`);
+  `backend-smoke` (run `agda-json` on a sample file).

---

## 3.  Backend (Haskell) build + tests

### 3.1.  Build the backend executable

<!-- doc-test: build-agda-json -->
```sh
make build-agda-json
```

### 3.2.  Locate the backend binary

<!-- doc-test: show-agda-json-bin -->
```sh
make show-agda-json-bin
```

### 3.3.  Run backend tests

Run the Haskell backend test suite with:

<!-- doc-test: backend-test -->
```sh
make backend-test
```

By default, backend tests **preserve their JSONL outputs** for inspection under

```
data/test-output/agda-strux/
```

To disable output retention: `make backend-test BACKEND_TEST_KEEP=0`  
To clean retained outputs: `make backend-test-clean`

### 3.4.  Backend smoke

<!-- doc-test: backend-smoke -->
```sh
make backend-smoke
```

### 3.5.  Clean backend artifacts

<!-- doc-test: backend-clean -->
```sh
make backend-clean
```

---

## 4.  Strux driver tests (Scala)

Canonical Scala test entrypoint:

```sh
make test     # (alias for test-strux-driver)
```

Or explicitly:

<!-- doc-test: test-strux-driver -->
```sh
make test-strux-driver
```

There's also an integration test target:

<!-- doc-test: test-integration -->
```sh
make test-integration
```

Run the whole suite (Scala + Python + AgdaDojang + backend tests):

```sh
make test-all
```

---

## 5.  Corpus Extraction and Proof Completion

### 5.1.  Corpus Extraction (the "real" pipeline path)
This is the main, resumable extraction path that writes

+  `data/<LIB_NAME>/raw/jsonl/*.jsonl`
+  `data/<LIB_NAME>/raw/logs/*`
+  `data/<LIB_NAME>/manifests/<timestamp>.json`

#### 5.1.1.  Full corpus extraction (agda-algebras by default)

<!-- doc-test: extract-lib -->
```sh
make extract-lib
```

**Key behavior**.

+  Builds `agda-json` (via nix if configured).
+  Generates module list via `make agda-algebras-metadata`.
+  Runs Scala `AgdaJsonlDriver` with `--runner spark` and local master.
+  Writes a manifest JSON with exit code + Agda version + git rev.

#### 5.1.2.  Smoke extraction (first N modules)

```sh
make extract-lib-smoke \
  SMOKE_N=25              # (optional) controls how many modules
```

#### 5.1.3.  Run extraction via Nix wrapper (from outside nix shell)

<!-- doc-test: extract-lib-nix -->
```sh
make extract-lib-nix
```
<!-- doc-test: extract-lib-smoke-nix -->
```sh
make extract-lib-smoke-nix
```

#### 5.1.4.  Fail-fast vs keep-going

By default the driver continues through failures (and records them). To fail fast:

```sh
make extract-lib FAIL_FAST=1
```

#### 5.1.5.  Resume control

The top-level knob is `RESUME` (default `1`). To force no resume:

```sh
make extract-lib RESUME=0
```

(Internally this adds `--no-resume` to driver args.)

#### 5.1.6.  Parallelism

```sh
make extract-lib PAR=16
```

### 5.2.  Proof-completion evaluator (AgdaDojang fixtures)

The proof-completion evaluator is the core demo of the project's propose → check
loop.  It runs AgdaDojang's `reportGoalCtx` macro to extract `(goal, context)`
from each `{!!}` hole in a fixture file, calls a policy backend to get candidate
terms, and typechecks each candidate in Agda.

> **Prerequisite:** run inside `nix develop` (or `nix develop .#all`).
> The evaluator requires Agda on PATH with the correct library configuration.

#### 5.2.1.  Smoke test (single fixture, fast)

```sh
make eval-proof-completion-smoke
```

This runs only `FixtureLambda.agda` with `--max-holes 1` and a 10-second timeout.
Expected result: 1 hole solved.

#### 5.2.2.  Full fixture evaluation (all fixtures)

```sh
make eval-proof-completion
```

This runs all `data/agda/Fixture*.agda` files through the evaluator.
Expected result: all fixtures pass except `FixtureFail01` (which is an expected
failure, marked `xfail`).

#### 5.2.3.  What the evaluator does

For each fixture file, the evaluator:

1. Finds `{!!}` holes in the source.
2. For each hole, injects `reportGoalCtx` and runs Agda to extract a structured
   `(goal, context)` request from Agda's error output.
3. Sends the request to the policy backend (default: `policy_fixture.py`).
4. Tries each candidate term by substituting it into the hole and typechecking.
5. If a candidate typechecks, the hole is marked solved and the source is patched.
6. Repeats until all holes are solved or candidates are exhausted.

#### 5.2.4.  Output artifacts

The following results are written to `agda-dojang/_build/eval-proof-completion/<run-id>/`:

+  `fixtures.jsonl` — one row per fixture with summary (holes, solved, final status, elapsed ms);
+  `results.jsonl` — one row per hole attempt with full details (goal, candidate, status, rc, log path);
+  `logs/<fixture>/hole-<N>/` — per-hole Agda output for debugging.

Both JSONL files use schema version `eval-proof-completion.v0`.

#### 5.2.5.  Overriding evaluator knobs

The evaluator is controlled by Makefile variables which may be overriden on the
command line, as follows:

```sh
make eval-proof-completion \
  EVAL_FIXTURES="data/fixtures/Fixture01.agda" \
  EVAL_MAX_HOLES=2 \
  EVAL_K=3 \
  EVAL_TIMEOUT=15 \
  EVAL_POLICY="python3 python/tools/policy_fixture.py" \
  EVAL_RUN_ID=my-run
```

#### 5.2.6.  Fixture files

Committed fixtures live in `agda-dojang/data/fixtures/` (or `data/fixtures/` when
running via `make -C agda-dojang`). Each fixture imports from
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


## 6.  "Small" extraction / transforms (non-corpus path)

These targets run mains directly and are useful for quick demos.

### 6.1.  Extract a single file/dir using `AgdaExtractorMain`

Defaults:

+ input: `data/agda/agda-example.agda`
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

### 6.2.  Transform Agda2Train reflection JSON → JSONL

```sh
make transform
```

### 6.3.  Legacy reducer path

```sh
make a2t
```

---

## 7.  ETL (Spark) and ML (Python)

### 7.1.  Spark ETL: JSONL → Parquet

Requires `DATA_TRAIN` to exist (run `make extract` first):

```sh
make etl
```

This runs:

* `cd ml-pipeline`
* `sbt "project etl" "runMain PreprocessAgda"`
  and expects:
* output at `ml-pipeline/features/train.parquet`

### 7.2.  Python venv management

Default behavior: Makefile creates/uses `ml-pipeline/.venv` (unless `USE_VENV=0`).

Useful knobs:

+ `USE_VENV=1` (default) → use repo venv
+ `USE_VENV=0` → assume you activated an env already
+ `TORCH_MODE=cpu` (default), `TORCH_MODE=pypi`, `TORCH_MODE=skip`


### 7.3.  Filter

```sh
make filter
```

You can enforce minimum lengths, as follows:

```sh
make filter MIN_TYPE_LEN=10 MIN_PROOF_LEN=10
```

### 7.4.  Retrieval model (current ML path)

```sh
make train-retrieval-smoke
make eval-proof-completion-smoke-retrieval
```

The first command trains a deterministic retrieval artifact from committed
fixture data; the second runs the proof-completion evaluator using it.

> **Note:** The legacy MLP trainer (`make train`), FastAPI server (`make serve`),
> and `finetune-dataset` target have been archived to `experiments/archive/`.
> See `docs/PLAN.md` for the current architecture.


---

## 8.  One-command workflows

These assume you're in the default Nix shell (`nix develop`). 

### 8.1.  Quick confidence check

```sh
make check
make eval-proof-completion-smoke
```

### 8.2.  Extraction + evaluation (small path)

```sh
make extract-lib-smoke
make eval-proof-completion
```

> **Note:** The legacy `make pipeline` target (which chained extract → filter →
> finetune-dataset → train) has been archived along with the components it
> depends on.  See `experiments/archive/` for details.

---

## 9.  Dataset utilities

### 9.1.  Stats

```sh
make dataset-stats
```

Override dataset:

```sh
make dataset-stats DATASET=/path/to/train.jsonl TOP=50
```

### 9.2.  Premise evaluation

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

## 10.  Smoke, audit, probe-all

### 10.1.  Curated smoke suite (writes logs)

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

### 10.2.  Audit (curated always-works targets)

```sh
make audit
make audit-nix
```

### 10.3.  Probe-all (attempts many targets, writes logs)

```sh
make probe-all
```

---

## 11.  Where outputs land

### 11.1.  Corpus extraction outputs

Default library: `LIB_NAME=agda-algebras`

* Raw root:

  * `data/agda-algebras/raw/`
* JSONL:

  * `data/agda-algebras/raw/jsonl/*.jsonl`
* Logs:

  * `data/agda-algebras/raw/logs/`
* Manifests:

  * `data/agda-algebras/manifests/<timestamp>.json`

### 11.2.  Non-corpus extract outputs

* `data/train.jsonl` (default)

### 11.3.  ML outputs

* Parquet: `ml-pipeline/features/train.parquet`
* Models: `ml-pipeline/models/model.pt`  (legacy)
* Finetune dataset: `data/finetune.jsonl`  (legacy)

---

## 12.  Debugging playbook

### 12.1.  "AgdaJsonlDriver exited 0 but produced no JSONL"

The Makefile already treats this as an error (exit code 2). Next steps:

* check `data/<LIB>/raw/logs/` for per-module logs
* check the manifest in `data/<LIB>/manifests/`
* verify `JAVA_HOME` is set (the Makefile will fail loudly if empty)
* verify `AGDA_LIB_DIR` points to the directory containing `agda/libraries`

### 12.2.  Backend binary resolution issues

The Makefile resolves `agda-json` by running:

* `cabal list-bin exe:agda-json` (inside backend shell)
* then filters to the last line that ends in `agda-json`

If it can't resolve:

* run `make show-agda-json-bin`
* run `command -v agda-json`
* run `make backend-test` (ensures build is sane)

### 12.3.  sbt / JDK weirdness

Targets `extract-lib` and `extract-algebras-backend` expect a pinned JDK:

* `JAVA_HOME` / `SBT_JAVA_HOME`

If sbt launches the wrong java:

* confirm `JAVA_HOME` inside your `nix develop .#all`
* try `make diag`

### 12.4.  Spark not found

If you see `spark-submit not found`:

* run inside `nix develop .#all`
* or install Spark and ensure `spark-submit` is on PATH
* check with: `make _check-spark`

### 12.5.  GitHub CLI issue export fails (repo "not found")

If `gh` mysteriously can't see the repo, the fix is usually:

```sh
env -u GH_TOKEN -u GITHUB_TOKEN gh auth status
```

because env tokens can shadow your stored auth.

---


## 13.  agda-mcp — AI-assisted proof development

`agda-mcp` is an MCP server that lets AI coding agents (Claude Code, Codex CLI,
Cursor, etc.) interact with Agda through standard tool calls.

The server exposes **seven tools**: four core proof-state tools — `get_goal`,
`fill_hole`, `check_file`, `get_diagnostics` — that are always available, plus
three corpus-backed search tools — `search_by_name`, `search_by_type`,
`get_dependencies` — that are registered only when you start the server with
`--corpus PATH` (an agda-strux JSONL corpus).  For the full command-line
reference (`--agda-bin`, `--agda-flags`, `--corpus`, `--timeout`, `--verbose`),
see [`agda-mcp/README.md`](../agda-mcp/README.md#command-line-options).

This section walks you through building, testing, running, and connecting an agent.

### 13.1.  Build & Test

Enter the `backend` Nix shell.[^1]

```sh
nix develop .#backend   # required!
```

Once in the `backend` Nix shell, do

```sh
cd agda-mcp
cabal build
cabal test
```

The test suite includes both pure tests (marker parsing, hole finding) and tier-2
integration tests that invoke a real `agda` binary.  For the integration tests, you
must be in the Nix `backend` shell (`nix develop .#backend`) or have `agda` in
your `PATH`; if Agda is not found, tier-2 tests are skipped.

Or, from the repo root (no shell entry or `cd` needed — the Makefile enters the
backend shell for you):

```sh
make agda-mcp-smoke   # build + a fast JSON-RPC round-trip sanity check
make agda-mcp-test    # full cabal test (unit + corpus + Agda integration)
```

Already inside `nix develop .#backend`?  Pass `BACKEND_USE_NIX=0` to skip the nested shell (as CI does).


### 13.2.  Run the server manually

#### Outside the Nix shell

To verify that the server works, enter the following on the command line
(from the top-level project directory, outside the Nix shell):

```sh
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test","version":"0.1"}}}' \
  | ./scripts/run-server.sh \
      --agda-flags "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library" \
      2>/dev/null
```

After a few seconds, you should see a JSON-RPC response tht includes `serverInfo.name: "agda-mcp"`.

#### Inside the Nix shell

Start `agda-mcp`, send it JSON-RPC requests on stdin, and verify everything is wired up. 

```sh
nix develop .#backend
cd agda-mcp
cabal run agda-mcp -- --agda-flags "-i ../agda-dojang/agda --library-file=../agda/libraries -l agda-dojang -l standard-library"
```

The server prints a startup banner and "Waiting for MCP client..." signaling that it is ready for your JSON-RPC input!

Type or paste a JSON-RPC request (one per line) to stdin; e.g.,

 ```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test","version":"0.1"}}}
```

You should see a JSON response immediately on the next line; e.g.,

```json
{"id":1,"jsonrpc":"2.0","result":{"capabilities":{"tools":{}},"protocolVersion":"2024-11-05","serverInfo":{"name":"agda-mcp","version":"0.2.0"}}}
```

Press Ctrl-C to stop the server.

Alternatively, you can pipe input directly to the server, as follows:

```sh
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test","version":"0.1"}}}' \
  | cabal run agda-mcp -- \
      --agda-flags "-i ../agda-dojang/agda --library-file=../agda/libraries -l agda-dojang -l standard-library"
```

For a pre-built sequence of test requests, see `agda-mcp/test/resources/mcp-test-input.jsonl`.


---

### 13.3.  Connect Claude Code

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) is a CLI coding agent
that can connect to `agda-mcp`, giving you an interactive AI assistant that can
inspect goals, fill holes, and check Agda files through natural language.

1.  **Install Claude Code** (requires Node.js 18+).

    ```sh
    npm install -g @anthropic-ai/claude-code
    ```

2.  **Navigate to the repo root** (`cd agda-native-air`).  The `.mcp.json` file there
    configures the agda MCP server connection.

3.  **Launch Claude Code**.

    ```sh
    MCP_TIMEOUT=120000 claude
    ```

    Claude Code will detect `.mcp.json` and start the agda MCP server.  You may need
    to approve the connection when prompted.

4.  **Verify Connection**.  Enter `/mcp` at the Claude Code prompt and confirm `agda · ✔ connected`.

5.  **Try a proof-state query**.  Once connected, start by entering a simple query at the Claude Code prompt, such as

    ```
    Use ONLY the agda MCP tool `get_goal` with filePath "agda-dojang/data/fixtures/Fixture01.agda" and holeIndex 0. Show me the raw result.
    ```

    If that works, try something a bit harder, such as

    ```
    Use ONLY the agda MCP tools (`get_goal`, `fill_hole`, `check_file`, `get_diagnostics`) to solve all holes in `agda-dojang/data/fixtures/Fixture01.agda`.  For each hole, inspect with `get_goal`, propose a candidate, and verify with `fill_hole`.  If a candidate fails, read the error message and adjust. Note: `fill_hole` validates candidates without modifying the file — once all candidates are verified, use your Edit tool to write them into the source, then confirm with `check_file`.
    ```

    If you started the server with `--corpus` (the shipped `.mcp.json` does, using
    the bundled fixture corpus), you can also exercise the search tools:

    ```
    Use ONLY the agda MCP tool `search_by_name` to find definitions whose name contains "hom", then `get_dependencies` on the most relevant result. Show me the raw results.
    ```


### 13.4.  Connect other MCP clients

Any MCP-compatible agent can connect to `agda-mcp`.  The general pattern is to
configure the agent to start `cabal run agda-mcp -- --agda-flags "..."` as a
subprocess with the repo root as working directory.

See [`agda-mcp/README.md` § Configuring MCP Clients](../agda-mcp/README.md#configuring-mcp-clients)
for JSON configuration examples for Claude Desktop, Cursor, and Codex CLI.

### 13.5.  Troubleshooting

**Server won't start / "agda not found"**.  Make sure you are inside `nix develop`
(or `nix develop .#backend`).  The Nix shell provides the pinned `agda` binary.

**"ModuleNameDoesntMatchFileName" errors**.  The `--agda-flags` must include
`-i agda-dojang/agda` so that Agda can find the AgdaDojang macros.  Double-check the
flags match the example above.

**Claude Code doesn't see the MCP server**.  Verify that `.mcp.json` exists in the
repo root and that the `cwd` field (if present) points to the correct absolute path.
Run `claude` from the repo root directory.


---

## 14.  Known good sequences

Each of these assume you are in the `all` Nix shell (`nix develop .#all`).

### 14.1.  Quick confidence check

```sh
make check
make extract-lib-smoke
```

### 14.2.  End-to-end proof completion

```sh
make eval-proof-completion
```

### 14.3.  Corpus extraction (requires agda-algebras cloned locally)

```sh
make extract-lib
```

### 14.4.  Retrieval model + evaluation

```sh
make train-retrieval-smoke
make eval-proof-completion-smoke-retrieval
```

---

## 15.  Cleaning

```sh
make clean   # remove a few generated files
make wipe    # remove generated artifacts (features/models/etc.)
make tree    # repo tree, excluding build dirs
```

---

[^1]: For `agda-mcp`, the `backend` shell is required at the moment since the default Nix shell has wrong GHC version.

