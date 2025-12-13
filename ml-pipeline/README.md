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

## ETL and Feature Engineering (Scala / Spark)

### Why Scala and Spark?

MLPipe reuses the Scala/Spark stack introduced in ProofParser for several reasons.

+  Strong static typing for feature schemas.
+  Mature support for large-scale data processing.
+  Easy transition from small local experiments to large corpora.
+  Clear declarative transformations over structured data.

Spark is used where it provides leverage; small experiments can be run locally without a cluster.

---

### Typical ETL Tasks

ETL jobs perform tasks such as

+  parsing JSONL into typed datasets,
+  normalizing names, modules, and identifiers,
+  constructing feature vectors for goals and premises,
+  splitting datasets into train/validation/test sets.

The output is typically written in **Parquet** format for efficiency and reproducibility.

---

## Training and Evaluation (Python / PyTorch)

### Model Training

Model training is currently implemented in Python using **PyTorch**.

The initial focus is on relatively simple, interpretable models, including

+  premise-selection models,
+  goal-conditioned classifiers,
+  embedding-based similarity models.

These serve both as baselines and as scaffolding for more ambitious approaches.

---

### Evaluation

Evaluation emphasizes **simple, transparent metrics**, for example,

+  Precision@K / Recall@K for premise selection,
+  coverage (does the model propose *any* correct premise?),
+  comparisons against frequency-based baselines.

The goal is not to optimize leaderboards, but to understand what information the models are actually using.

---

## Inference and Serving

MLPipe includes early-stage support for model serving.

A lightweight **FastAPI** server can

+  load trained models,
+  accept structured goal or premise queries,
+  return ranked predictions or scores.

This server is intended to be called by interactive components such as AgdaJang, closing the loop between learning and proof execution.

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

From the repository root:

```bash
make etl          # JSONL → Parquet features
make train        # Train a baseline model
make serve        # Start the inference server
make smoke        # End-to-end sanity check
```

Run `make help` for additional configuration options.

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

* Root project README
* `proof-parser/README.md`
* `agda-jang/README.md`
