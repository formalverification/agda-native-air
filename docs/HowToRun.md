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

The server exposes **eight tools**: four core proof-state tools — `get_goal`,
`fill_hole`, `check_file`, `get_diagnostics` — and the whole-project gate,
`check_project`, all always available, plus three corpus-backed search tools —
`search_by_name`, `search_by_type`, `get_dependencies` — that are registered
only when you start the server with `--corpus PATH` (an agda-strux JSONL
corpus).  For the full command-line reference (`--agda-bin`, `--agda-flags`,
`--corpus`, `--timeout`, `--check-command`, `--check-timeout`, `--verbose`), see
[`agda-mcp/README.md`](../agda-mcp/README.md#command-line-options).

`check_project` runs the project's own acceptance gate — the nearest Makefile's
`check` target, a command you name with `--check-command`, or `agda` on the
project's `Everything` module — and reports its verdict without misreporting its
exit code, including the case where a wrapper script ending in `echo` reports
shell exit 0 for a build that failed.  See
[`agda-mcp/README.md`](../agda-mcp/README.md#check_project).

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

### 13.5.  Using agda-mcp on another Agda project

You can point Claude Code at another Agda project (for example `agda-algebras`) while
still giving it agda-mcp from *this* repository.  The recommended setup: **launch
Claude Code from the other project's worktree** — so that project is the working
directory, with its own `CLAUDE.md`, git, and permissions — and **attach agda-mcp to
that session**.  agda-mcp does not need to be the working directory;
`scripts/run-server.sh` computes the agda-native-air repo root and `cd`s there before launching the server, so it works from any cwd.

(Launching from agda-native-air and using `/add-dir` to reach the other project also
works, but then agda-native-air stays the project root, so committing the other
project's work through that session is awkward.  Prefer the setup below.)

There are two ways to attach the server.  **Option A is recommended** — it is a plain
file, immune to shell aliasing, and self-documenting.

#### Option A — a project `.mcp.json` (recommended)

Copy the committed template
[`agda-mcp/examples/agda-algebras.mcp.json`](../agda-mcp/examples/agda-algebras.mcp.json)
into the worktree you are editing as `.mcp.json`, replace the two `/ABS/PATH/TO/...`
placeholders with real absolute paths, and keep it out of that project's history:

```sh
cd /path/to/agda-algebras/<your-branch-worktree>
cp /abs/path/to/agda-native-air/agda-mcp/examples/agda-algebras.mcp.json ./.mcp.json
# edit ./.mcp.json — set `command` to this repo's scripts/run-server.sh, and
#                    env.AGDA_ALGEBRAS_ROOT to your agda-algebras worktree path
echo '.mcp.json' >> .git/info/exclude   # local-only ignore; leaves tracked .gitignore alone

nix develop   # optional: gives Claude's own Bash the agda-algebras toolchain
claude        # approve the "agda" server when prompted, then /mcp → agda · ✔ connected
```

Claude Code auto-loads `.mcp.json` from the working directory (asking once to approve
it).  Two entries in it do the real work — `env.AGDA_ALGEBRAS_ROOT`, which registers
your library so the proof-state tools resolve it, and (optionally) `--corpus`, which
turns on the search tools.  Both are covered in *Library registration and the search
corpus* below.  Keep `--timeout 600`: the bound is enforced — on expiry the `agda`
process group is killed and the tool returns a timeout rather than blocking — and the
first typecheck of a large module is cold, building `.agdai` interfaces for its whole
import graph, which can take minutes and overruns even the 300 s default.  Sizing the
bound too small is not a graceful degradation: it aborts exactly the call that would
have built those interfaces, so the next call starts cold again.  Every proof-state
response reports `elapsedMs` and `checkedFromSource`, so you can tell a slow cold call
from a slow warm one (`checkedFromSource` is omitted when the run died before
producing evidence either way — absent means unknown, not warm).

#### Option B — `claude mcp add`

Equivalently, register the server on the command line from the worktree:

```sh
claude mcp add agda --scope local \
  --env AGDA_ALGEBRAS_ROOT=/path/to/agda-algebras/<your-branch-worktree> \
  -- /abs/path/to/agda-native-air/scripts/run-server.sh \
     --agda-flags "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library -l agda-algebras" \
     --timeout 600
```

`--scope local` keeps the registration in your per-project config — not committed to the
other repository.

> **If this errors with `script: unrecognized option '--scope'`** (or similar), your
> shell has `claude` aliased or wrapped — e.g. under `script` for session logging — so
> the subcommand arguments reach the wrapper instead of Claude Code.  Run `type claude`
> to confirm, then either prefix the command with `command` (`command claude mcp add …`
> bypasses the alias/function) or just use Option A, which avoids the `claude` CLI for
> configuration entirely.

#### Library registration and the search corpus

Two things in the config carry the machine-specific setup.  The templates above already
include both; this is what they do and how to get them right.

**Register your library — `env.AGDA_ALGEBRAS_ROOT` (needed for the proof-state tools).**
agda-mcp answers *every* tool call with **this repository's** Agda, inside its `.#backend`
shell — not your project's shell.  (`run-server.sh` does `nix develop <agda-native-air>#backend
--command …`; your own `nix develop` before launching `claude` only equips Claude's Bash,
not the server.)  So `-l agda-algebras` has to resolve in *this* repo's `agda/libraries`,
and setting `AGDA_ALGEBRAS_ROOT` is exactly what puts it there: `run-server.sh` passes the
variable into the `.#backend` shell, whose hook appends your library's `.agda-lib` to
`agda/libraries` (see [§1.3](#13--registering-external-agda-libraries-optional)).  This is
verified to propagate through `run-server.sh`; when registration seems not to happen it is
almost always one of two things:

+  **The path points at the wrong worktree.**  `AGDA_ALGEBRAS_ROOT` must be the *exact*
   worktree you are editing and must contain a `*.agda-lib` at its top level.  If it is
   stale or wrong, the hook prints a warning to **stderr** — which the MCP client hides —
   and silently skips registration, so `-l agda-algebras` then fails with "library not
   found".
+  **The server was not restarted after editing `.mcp.json`.**  The server reads the
   variable and rewrites `agda/libraries` once, at startup; changes to `.mcp.json` take
   effect only after a full restart of Claude Code.

Do **not** hand-edit `agda/libraries` to work around this: the hook regenerates that file
on every shell entry, so a manual line is wiped the next time the server starts.
`AGDA_ALGEBRAS_ROOT` is the durable fix.  For a different library, set the matching
`*_ROOT` variable and `-l <name>` — see [§1.3](#13--registering-external-agda-libraries-optional)
for the supported set.

**You cannot get a silent answer about the wrong worktree.**  A stale `AGDA_ALGEBRAS_ROOT`
used to be a genuine hazard: the server would resolve your file's imports against the
*other* branch's tree and report success.  It now refuses instead — a file whose nearest
`*.agda-lib` names a library the server has registered at a different root fails with a
`rootMismatch` object naming both roots and the libraries file that disagrees.  You do not
have to wait for that to notice, either: every proof-state response carries a `project`
block naming the tree it checked, alongside `command` (the exact `agda` invocation,
resolved binary and cwd included) and `verdict` (what green means, and Agda's own exit
code, which the verdict is read from).  See
[`docs/agda-mcp-environment.md`](agda-mcp-environment.md).

**Add a corpus — `--corpus <abs-path>.jsonl` (turns on the search tools).**  The
`search_by_name` / `search_by_type` / `get_dependencies` tools appear in `tools/list` only
when a corpus is loaded; the proof-state tools do not need one.  Build a corpus of your
library once, then point `--corpus` at it:

```sh
# in agda-native-air, in the .#all shell (Spark), see §5.1 for detail:
make extract-lib LIB_NAME=agda-algebras \
     AGDA_ALGEBRAS_ROOT=/abs/path/to/agda-algebras/<your-worktree>
# collect the per-module JSONL the extractor writes into one file:
find data/agda-algebras/raw -name '*.jsonl' -print0 | xargs -0 cat \
     > /abs/path/to/agda-algebras-corpus.jsonl
```

Then add `"--corpus", "/abs/path/to/agda-algebras-corpus.jsonl"` to the server's `args`.
`make extract-lib` emits exactly the agda-strux JSONL schema that `--corpus` reads (one
entry per line: name, type, kind, dependencies, …), and the server logs how many entries
it loaded at startup, so you can confirm it took.  Retrieval is independent of the
proof-state tools — it neither requires nor affects library registration.

#### Three things to know

+  **`get_goal` and `fill_hole` do not yet work on library-embedded modules.**  Both
   typecheck a temporary copy of the file; for a module that lives inside a library at a
   hierarchical path (e.g. `FLRP.Bridge` at `src/FLRP/Bridge.lagda.md`) that copy
   collides with the module's canonical file once the library is on the include path,
   and Agda reports `ModuleDefinedInOtherFile`.  Only flat, top-level modules work today.
   `check_file` and `get_diagnostics` are unaffected — they typecheck **in place**, so a
   real library file loads and verifies correctly.  A fix that runs `get_goal` /
   `fill_hole` in place too is tracked in
   [#66](https://github.com/formalverification/agda-native-air/issues/66).  Until it
   lands, the reliable workflow on a real library is one of: draft in a **scratch,
   top-level module** in your worktree that imports `AgdaDojang.Debug` plus the modules
   you build on (there all four proof-state tools work, and `get_goal` finds
   `reportGoalCtx` because the import is present); or edit the library file directly and
   verify each change with `check_file` / `get_diagnostics`.
+  **Use absolute file paths.**  The server's working directory is agda-native-air, not
   your project, so tool calls resolve paths from there.  Claude passes absolute paths
   automatically from its own Read/Edit tools; just avoid hand-typing relative paths in
   prompts.
+  **Match the toolchain.**  agda-mcp typechecks with this repo's pinned Agda 2.8.0 and
   standard-library 2.3.  That is only correct if the other project is compatible with
   those versions — confirm `agda --version` and the std-lib version line up.  If the
   project pins a different std-lib you will see mismatch errors; the fix is then to add
   `--agda-bin` pointing at that project's own `agda` (advanced — the macro must still
   typecheck there, with agda-dojang registered).

#### Web UI

Doing this in the "Claude Code on the web" UI is possible but heavier: the container
needs *both* repositories as sources, agda-mcp built in-container (the Nix backend
build — several minutes, and the container is ephemeral), and an MCP config wired to
absolute container paths.  That is worth setting up via an environment setup script
once the workflow is proven, but for a first sanity test the terminal is far simpler.

### 13.6.  Troubleshooting

**Server won't start / "agda not found"**.  Make sure you are inside `nix develop`
(or `nix develop .#backend`).  The Nix shell provides the pinned `agda` binary.

**"ModuleNameDoesntMatchFileName" errors**.  The `--agda-flags` must include
`-i agda-dojang/agda` so that Agda can find the AgdaDojang macros.  Double-check the
flags match the example above.

**"Library 'agda-algebras' not found" on another project**.  The library is not
registered in this repo's `agda/libraries`.  Set `env.AGDA_ALGEBRAS_ROOT` in your
`.mcp.json` to the exact worktree you are editing (it must contain a `*.agda-lib`) and
**fully restart** Claude Code — see *Library registration and the search corpus* in
§13.5 for the two common causes.

**"ModuleDefinedInOtherFile" from `get_goal` / `fill_hole` on a library file**.  This is
the known limitation tracked in
[#66](https://github.com/formalverification/agda-native-air/issues/66): those two tools
typecheck a temp copy that collides with the module's canonical location.  Use
`check_file` / `get_diagnostics` (which load in place), or work in a scratch top-level
module — see the first item under *Three things to know* in §13.5.

**"filePath does not exist" naming a path in the agda-native-air checkout**.  You sent a
relative path from your own project.  The server is a separate process, and
`scripts/run-server.sh` starts it in *this* repository, so relative paths resolve here
rather than in your tree — the error names both the path as resolved and the working
directory it was resolved against.  Send an absolute path: your project's directory
followed by the relative path you tried.  See *Which file gets checked: the path rule*
in [`agda-mcp/README.md`](../agda-mcp/README.md).

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

