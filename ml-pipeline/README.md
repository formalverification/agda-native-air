<!-- File: agda-native-air/ml-pipeline/README.md -->

# MLPipe

This is the learning, evaluation, and inference component of the **agda-native-air** project.

Its purpose is to take the **structured, semantically informed datasets** produced by StruxDriver and use them to train, evaluate, and deploy machine-learning models that support AI-assisted reasoning in Agda.

MLPipe is intentionally modular and research-oriented; it is designed to support experimentation with different data representations, learning objectives, and model architectures, rather than to lock the project into a single ML stack or approach.


<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Role in the Overall System](#role-in-the-overall-system)
- [Design Principles](#design-principles)
- [Pipeline Overview](#pipeline-overview)
- [Stage 1: Input (JSONL datasets produced by StruxDriver)](#stage-1-input-jsonl-datasets-produced-by-proofparser)
- [Stage 2: ETL and Feature Engineering (Scala / Spark)](#stage-2-etl-and-feature-engineering-scala--spark)
- [Stage 3: Training and Evaluation (Python / PyTorch)](#stage-3-training-and-evaluation-python--pytorch)
- [Stage 4: Inference and Serving](#stage-4-inference-and-serving)
- [Running MLPipe](#running-mlpipe)
- [Research Notes and Future Directions](#research-notes-and-future-directions)
- [See Also](#see-also)

<!-- markdown-toc end -->


---

## Role in the Overall System

Within the agda-native-air architecture, MLPipe is responsible for

+  transforming extracted proof data into learning-ready features,
+  training models for tasks such as premise selection and goal prediction,
+  evaluating models using simple, reproducible baselines,
+  serving trained models to interactive components (e.g. AgdaDojang).

Where StruxDriver answers *“what mathematical structure is present?”* and AgdaDojang answers *“what actions can we take?”*, MLPipe answers

> *“What patterns can be learned from existing mathematics, and how can they guide future proof search?”*

---

## Design Principles

MLPipe is guided by several core principles.

+  **Structure over text**: models consume structured representations, not raw source code.
+  **Reproducibility**: datasets, splits, and evaluations are deterministic.
+  **Separation of concerns**: extraction, feature engineering, training, and inference are cleanly separated.
+  **Research flexibility**: swapping models or encodings should be easy.

The pipeline favors clarity and inspectability over maximal performance.

---

## Pipeline Overview

At a high level, the pipeline consists of four stages.

1. **Input**: JSONL datasets produced by StruxDriver (`AgdaData`, `TrainRecord`).
2. **ETL / Feature Engineering**: transformation into columnar, model-friendly formats.
3. **Training & Evaluation**: learning models and measuring performance.
4. **Inference / Serving**: making trained models available to agents.

Each stage can be run independently.

---

## Directory Structure

### Main Directories

+ `etl`: Scala/Spark ETL programs.
+ `python`: Python modeling and training programs.

### Scala/Spark Programs

These are in `ml-pipeline/etl/src/main/scala/etl`.

+ `BuildProofCompletionDataset.scala`: builds proof-completion dataset from Agda definition rows.
+ `PreprocessAgda.scala`: preprocesses Agda backend JSONL to Parquet.
+ `PreprocessAgdaSchema.scala`: schema for preprocessed Agda definitions.

### Python Programs

These are under `ml-pipeline/python`.


+  `conftest.py`: Pytest configuration for the ml-pipeline project.
+  `requirements.txt`: Python package dependencies.
+  `model/`

   +  `filter_jsonl.py` reads a JSON Lines (JSONL) file containing records, applies
      a few simple *schema-aware* filters, writes the filtered result back as JSONL.

   +  `train_retrieval.py` builds a deterministic retrieval artifact for
      `agda-dojang/python/tools/policy_retrieval.py`.

+  `scripts/inspect_runtime.py`: inspect and print the runtime environment.

+  `tests/`

   +  `test_train_retrieval.py`: tests ensuring retrieval model artifact is
      deterministic across runs and adheres to expected invariants.

The FastAPI serving app and the legacy PyTorch/MLP tooling (`api/`, `model/train.py`,
`model/batch_infer.py`, `model/export_*.py`, `model/build_finetune_dataset.py`, and
their tests) have been archived to `experiments/archive/ml-pipeline/`; model serving
will be handled by `agda-mcp`.[^1]

---


## Stage 1: Input (JSONL datasets produced by StruxDriver)

This is the pre-ETL stage and is the responsibility of the `agda-strux` and
`StruxDriver` components of the project; see:

+  [agda-strux/README][]
+  [strux-driver/README][]

---

## Stage 2: ETL and Feature Engineering (Scala / Spark)

### Why Scala and Spark?

MLPipe reuses the Scala/Spark stack introduced in StruxDriver for several reasons.

+  Strong static typing for feature schemas.
+  Mature support for large-scale data processing.
+  Easy transition from small local experiments to large corpora.
+  Clear declarative transformations over structured data.

Spark is used where it provides leverage; small experiments can be run locally without a cluster.

### Typical ETL Tasks

ETL jobs perform tasks such as

+  parsing JSONL into typed datasets,
+  normalizing names, modules, and identifiers,
+  constructing feature vectors for goals and premises,
+  splitting datasets into train/validation/test sets.

The output is typically written in **Parquet** format for efficiency and reproducibility.

### Proof-completion training dataset builder (Phase 1)

This is the ETL stage where we consume existing Agda libraries and extract
proof-completion training data sets from them.

(This is distinct from the
[Proof completion demo](#proof-completion-demo-phase-1-propose--agda-check)
in Stage 4 below, which proposes and verifies proofs to fill holes in incomplete Agda
files.)

MLPipe includes a small, deterministic dataset builder that converts
**canonical Agda definition rows** (from the extractor's "Full" JSONL) into a
proof-completion-style training dataset, with key-value pairs of the form

> **(goal, local context) → proof body**

**Implementation**. `ml-pipeline/etl/src/main/scala/etl/BuildProofCompletionDataset.scala`

**Input**.  canonical JSONL rows containing (at minimum) `file`, `prettyQname`,
`type`, `body`, `hasBody`, and structural AST as either `typeAst` (object) or
`typeAstJson` (string).

**Output**. JSONL rows with `schemaVersion = "proof-completion.v0"` and keys such as
`goal`, `context`, `targetRaw`, `target`, `targetResolver`, `targetResolved`, and
lightweight provenance fields.

**The builder is CI-friendly**.

+ streaming (no full-corpus load),
+ deterministic ordering,
+ skip-reason reporting (useful when a fixture slice unexpectedly yields zero rows),
+ `--strict` fails on parse errors **or** if `emitted == 0`.

**Run**. Recommended smoke target (fixture-driven) is run with

```sh
# from repo root
make etl-proof-completion-dataset-smoke
```

**Run manually**.  Direct invocation with

```sh
cd ml-pipeline
sbt -batch "project etl" \
  "runMain etl.BuildProofCompletionDataset \
    --in   /abs/path/to/canonical.full.jsonl \
    --out  /abs/path/to/proof_completion.jsonl \
    --limit 200 \
    --strict"
```

---

## Stage 3: Training and Evaluation (Python / PyTorch)

### Model Training

Model training is currently implemented in Python using **PyTorch**.

The initial focus is on relatively simple, interpretable models, including

+  premise-selection models,
+  goal-conditioned classifiers,
+  embedding-based similarity models.

These serve both as baselines and as scaffolding for more ambitious approaches.

### Evaluation

Evaluation emphasizes **simple, transparent metrics**, for example,

+  Precision@K / Recall@K for premise selection,
+  coverage (does the model propose *any* correct premise?),
+  comparisons against frequency-based baselines.

The goal is not to optimize leaderboards, but to understand what information the models are actually using.

---

## Stage 4: Inference and Serving

??? info "Deprecated: MLPipe includes early-stage support for model serving [^1]"

    A lightweight **FastAPI** server can

    +  load trained models,
    +  accept structured goal or premise queries,
    +  return ranked predictions or scores.

    This server is intended to be called by interactive components such as AgdaDojang, closing the loop between learning and proof execution.

Model serving will be handled by `agda-mcp`.[^1]

### Pre-training policy backend

See [agda-dojang/README](https://github.com/formalverification/agda-native-air/blob/85-agda-check-evaluator-fixtures/agda-dojang/README.md#policy-fixturepy)

#### Proof completion demo (Phase 1: propose → Agda-check)

Two canonical commands:

```bash
# Full fixture evaluation (writes logs + JSONL + report.json/report.md)
make eval-proof-completion

# Fast smoke run (single tiny fixture; good for CI/local sanity checks)
make -C agda-dojang eval-proof-completion-smoke
```

These commands currently run Python tooling inside the `agda-dojang` subproject because the evaluation loop depends on the AgdaDojang *reflection macros* (to extract goal + local context) and the AgdaDojang library setup (pinned stdlib, library-file, include paths). The ML pipeline consumes the resulting artifacts (goal/context requests, candidate attempts, aggregate reports) as inputs to later dataset-building and model work.

---

## Running MLPipe

### With Nix (recommended)

From the repository root:

```bash
nix develop
```

This provides Python, Scala, Spark, and all required dependencies.

---

### Common Tasks

#### Extraction and Conversion: Agda -> JSONL -> Parquet

From the repository root:

``` bash
# Enter default Nis devShell:
nix develop

# Extract agda-algebras to JSONL files in data/agda-algebras/raw/jsonl:
make extract-lib

# Merging all records into single train.sample.jsonl file:
make train-jsonl-sample

# Convert single JSONL file to Parquet format:
cd ml-pipeline && sbt -batch "project etl" "runMain etl.PreprocessAgda ../../data/train.sample.jsonl ../features"

# Alternative: Use the new config-driven ETL target (after extraction):
make etl-agda-algebras
```

**Note:** The new `etl-agda-algebras` target automatically handles merging JSONL shards
and running the ETL pipeline according to `configs/agda-algebras.yaml`. It produces
outputs in `ml-pipeline/data/agda-algebras/{train,test}.parquet`.

(Note, ETL commands may show many Spark-generated `[error]` lines; these can be ignored.)

Finally, confirm the Parquet has the **new columns** and **rows > 0**:

```bash
python - <<'PY'
import os, glob
import pyarrow.parquet as pq

base = "ml-pipeline/features"
need = {"type","body","hasBody","typeAstVersion","typeAstJson","prettyQname","defKind","dependencies","astSize"}
for split in ["train.parquet", "test.parquet"]:
    path = os.path.join(base, split)
    files = glob.glob(path + "/**/*.parquet", recursive=True)
    assert files, f"no parquet files under {path}"
    t = pq.read_table(path)
    cols = set(t.column_names)
    missing = sorted(need - cols)
    print(split, "rows=", t.num_rows, "missing=", missing)
    assert t.num_rows > 0
    assert not missing
print("OK")
PY
```

What success looks like:

```bash
train.parquet rows= 61 missing= []
test.parquet rows= 4 missing= []
OK
```

This proves: Agda extraction → sample JSONL → Spark ETL is wired and produces both
string and structural fields.

---

### ETL, Train, and Smoke Tests

From the repository root:

```bash
make etl                    # JSONL → Parquet features.
make train-retrieval-smoke  # Train the deterministic retrieval artifact.
make smoke                  # End-to-end sanity checks.
```

`make etl` runs the Spark ETL (`etl.PreprocessAgda`) and writes
`ml-pipeline/features/{train,test}.parquet`.  `make train-retrieval-smoke` builds the
committed retrieval artifact from the smoke dataset.  `make smoke` runs the top-level
sanity lane (sample generation, dataset stats, extraction, and tests).

(sbt prefixes everything a forked process writes to stderr with `[error]`, so Spark's
own INFO/WARN logs surface as `[error]` lines even on a successful run.  Judge the run
by its exit code and the `✅ wrote ...` success marker, not by the presence of `[error]`
lines.)


---

### Other Common Tasks

Run `make help` for additional targets and configuration options.

---

## Research Notes and Future Directions

+  Richer encodings of dependent types and contexts.
+  Joint models over goals and action sequences.
+  Integration with large language models as components.
+  Curriculum learning across mathematical corpora.
+  Active learning driven by AgdaDojang interactions.

*MLPipe is intentionally conservative today, providing a stable foundation for more experimental work.*

---

## See Also

+ [Root project README][]
+ [`agda-strux/README.md`][agda-strux/README]
+ [`agda-dojang/README.md`][agda-dojang/README]
+ [`strux-driver/README.md`][strux-driver/README]


[^1]: **Note:** The FastAPI model server (`api/main.py`) and the legacy MLP trainer have been archived to `experiments/archive/ml-pipeline/`.  Model serving will be handled by `agda-mcp`; see `docs/PLAN.md` Phase 1 for the current architecture.



[Root project README]: https://github.com/formalverification/agda-native-air/blob/main/README.md
[agda-strux/README]: https://github.com/formalverification/agda-native-air/blob/main/agda-strux/README.md
[strux-driver/README]: https://github.com/formalverification/agda-native-air/blob/main/strux-driver/README.md
[agda-dojang/README]: https://github.com/formalverification/agda-native-air/blob/main/agda-dojang/README.md


