<!-- agda-ai-prover/ml-pipeline/README.md -->

# MLPipe

This is the learning, evaluation, and inference component of the **agda-ai-prover** project.

Its purpose is to take the **structured, semantically informed datasets** produced by ProofParser and use them to train, evaluate, and deploy machine-learning models that support AI-assisted reasoning in Agda.

MLPipe is intentionally modular and research-oriented; it is designed to support experimentation with different data representations, learning objectives, and model architectures, rather than to lock the project into a single ML stack or approach.

---

## Role in the Overall System

Within the agda-ai-prover architecture, MLPipe is responsible for

+  transforming extracted proof data into learning-ready features,
+  training models for tasks such as premise selection and goal prediction,
+  evaluating models using simple, reproducible baselines,
+  serving trained models to interactive components (e.g. AgdaJang).

Where ProofParser answers *“what mathematical structure is present?”* and AgdaJang answers *“what actions can we take?”*, MLPipe answers

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

1. **Input**: JSONL datasets produced by ProofParser (`AgdaData`, `TrainRecord`).
2. **ETL / Feature Engineering**: transformation into columnar, model-friendly formats.
3. **Training & Evaluation**: learning models and measuring performance.
4. **Inference / Serving**: making trained models available to agents.

Each stage can be run independently.

---

## 1) Input: JSONL datasets produced by ProofParser

This is the pre-ETL stage and is the responsibility of the `agda-backend-jsonl` and
`ProofParser` components of the project; see:

+  [agda-backend-jsonl/README][]
+  [proof-parser/README][]

---


## 2) ETL and Feature Engineering (Scala / Spark)

### Why Scala and Spark?

MLPipe reuses the Scala/Spark stack introduced in ProofParser for several reasons.

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

---

## 3) Training and Evaluation (Python / PyTorch)

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

## 4) Inference and Serving

MLPipe includes early-stage support for model serving.

A lightweight **FastAPI** server can

+  load trained models,
+  accept structured goal or premise queries,
+  return ranked predictions or scores.

This server is intended to be called by interactive components such as AgdaJang, closing the loop between learning and proof execution.

### Pre-training policy backend

See [agda-jang/README](https://github.com/formalverification/agda-ai-prover/blob/85-agda-check-evaluator-fixtures/agda-jang/README.md#policy-fixturepy)


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
```sh
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

```sh
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

``` bash
train.parquet rows= 61 missing= []
test.parquet rows= 4 missing= []
OK
```

This proves: Agda extraction → sample JSONL → Spark ETL is wired and produces both
string and structural fields.


---

### ETL, Train, Serve, and Smoke Tests

From the repository root:

```bash
make etl          # JSONL → Parquet features.
make train        # Train a baseline model.
make serve        # Start the inference server (placeholder; yet to be implemented).
make smoke        # End-to-end sanity checks.
```

What success looks like:

``` bash
$ make etl
>> [etl] Spark: JSONL -> Parquet -> /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/features/train.parquet
cd ml-pipeline && \
  sbt -Dsbt.supershell=false "project etl" "runMain etl.PreprocessAgda"
[info] welcome to sbt 1.10.11 (N/A Java 21.0.3)
[info] loading settings for project ml-pipeline-build-build from metals.sbt...
[info] loading project definition from /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/project/project
[info] loading settings for project ml-pipeline-build from metals.sbt...
[info] loading project definition from /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/project
[success] Generated .bloop/ml-pipeline-build.json
[success] Total time: 2 s, completed Feb 1, 2026, 2:38:18 PM
[info] loading settings for project root from build.sbt...
[info] set current project to ml-pipeline (in build file:/home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/)
[info] set current project to ETL (in build file:/home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/)
[info] running (fork) etl.PreprocessAgda 
[error] Using Spark's default log4j profile: org/apache/spark/log4j2-defaults.properties
[error] 26/02/01 14:38:20 WARN Utils: Your hostname, alonzo resolves to a loopback address: 127.0.1.1; using 192.168.1.34 instead (on interface wlp0s20f3)
...
[error] 26/02/01 14:38:26 INFO ShutdownHookManager: Shutdown hook called
[error] 26/02/01 14:38:26 INFO ShutdownHookManager: Deleting directory /tmp/spark-73102be6-e849-4ce6-8a1a-02aadd609d99
[success] Total time: 8 s, completed Feb 1, 2026, 2:38:26 PM
✅ wrote /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/features/train.parquet

$ make train
>> [train] USE_VENV=1 TORCH_MODE=cpu
   TRAIN_DATA=/home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/data/train.jsonl
🐍 inspecting Python / torch runtime...
Python executable : /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/.venv/bin/python
torch version     : 2.6.0+cu124
/home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/.venv/lib/python3.12/site-packages/torch/cuda/__init__.py:129: UserWarning: CUDA initialization: Unexpected error from cudaGetDeviceCount(). Did you run some cuda functions before calling NumCudaDevices() that might have already set an error? Error 804: forward compatibility was attempted on non supported HW (Triggered internally at /pytorch/c10/cuda/CUDAFunctions.cpp:109.)
  return torch._C._cuda_getDeviceCount() > 0
CUDA available    : False
🧊 USING CPU-ONLY TORCH
>> [train] training -> /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/models/model.pt (input=/home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/data/train.jsonl)
/home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/.venv/lib/python3.12/site-packages/torch/cuda/__init__.py:129: UserWarning: CUDA initialization: Unexpected error from cudaGetDeviceCount(). Did you run some cuda functions before calling NumCudaDevices() that might have already set an error? Error 804: forward compatibility was attempted on non supported HW (Triggered internally at /pytorch/c10/cuda/CUDAFunctions.cpp:109.)
  return torch._C._cuda_getDeviceCount() > 0
epoch 1/10  loss=0.0085
epoch 2/10  loss=0.0039
epoch 3/10  loss=0.0019
epoch 4/10  loss=0.0010
epoch 5/10  loss=0.0006
epoch 6/10  loss=0.0004
epoch 7/10  loss=0.0002
epoch 8/10  loss=0.0001
epoch 9/10  loss=0.0001
epoch 10/10  loss=0.0001
✅ saved model to /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/models/model.pt
✅ model ready: /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/models/model.pt

$ make serve
⚠️  /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/ml-pipeline/python/api/app.py not found; skipping serve.

$ make smoke
→ Top-level smoke on "2026-02-01T21:39:16Z"
→ logs: /home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/worktrees/william/58-integrate-into-etl/data/make-logs/20260201T213916Z
------------------------------------------------------------
>>> make gen-sample
✓ gen-sample (17s)
------------------------------------------------------------
>>> make dataset-stats-sample
✓ dataset-stats-sample (12s)
------------------------------------------------------------
>>> make premise-eval-quick-sample
✓ premise-eval-quick-sample (13s)
------------------------------------------------------------
>>> make extract
✓ extract (7s)
------------------------------------------------------------
>>> make test
✓ test (27s)
------------------------------------------------------------
>>> make backend-smoke
✓ backend-smoke (12s)
✓ smoke passed: gen-sample dataset-stats-sample premise-eval-quick-sample extract test backend-smoke
```

---

### Other Common Tasks
 
Run `make help` for additional targets and configuration options.

---

## Research Notes and Future Directions

+  Richer encodings of dependent types and contexts.
+  Joint models over goals and action sequences.
+  Integration with large language models as components.
+  Curriculum learning across mathematical corpora.
+  Active learning driven by AgdaJang interactions.

*MLPipe is intentionally conservative today, providing a stable foundation for more experimental work.*

---

## See Also

+ [Root project README][]
+ [`agda-backend-jsonl/README.md`][agda-backend-jsonl/README]
+ [`agda-jang/README.md`][agda-jang/README]
+ [`proof-parser/README.md`][proof-parser/README]

[Root project README]: https://github.com/formalverification/agda-ai-prover/blob/main/README.md
[agda-backend-jsonl/README]: https://github.com/formalverification/agda-ai-prover/blob/main/agda-backend-jsonl/README.md
[proof-parser/README]: https://github.com/formalverification/agda-ai-prover/blob/main/proof-parser/README.md
[agda-jang/README]: https://github.com/formalverification/agda-ai-prover/blob/main/agda-jang/README.md
[`agda-jang/python/agdajang/policy_fixture.py`]: https://github.com/formalverification/agda-ai-prover/blob/main/agda-jang/python/tools/policy_fixture.py


