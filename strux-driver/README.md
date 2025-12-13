<!-- agda-ai-prover/proof-parser/README.md -->

# ProofParser

**ProofParser** is the data-extraction and normalization component of the **agda-ai-prover** project.

Its purpose is to convert Agda libraries and interactive proof sessions into **structured, semantically informed datasets** suitable for machine learning tasks such as premise selection, proof synthesis, goal prediction, and proof-state modeling.

Unlike lightweight scrapers or text-based parsers, ProofParser is designed to work *with* Agda — invoking its typechecker and interaction protocol — in order to extract information that is only available after elaboration and scope checking.

---

## Role in the Overall System

Within the broader agda-ai-prover architecture, ProofParser is responsible for:

+  defining **canonical data models** for Agda proofs and goals,
+  extracting data from Agda in both **batch (offline)** and **interactive** modes,
+  normalizing heterogeneous inputs into stable **JSONL schemas**,
+  providing small evaluation and sanity-checking utilities for datasets.

All learning components downstream (ETL, training, inference) depend on the correctness and stability of the data produced here.

---

## Not Your Average Parser

Despite the name, ProofParser is *not* a simple parser that scans `.agda` files and populates JSON structures.

In particular:

+  Agda source files are **not self-describing**; names, scopes, implicit arguments, and types are resolved only after type checking.
+  Proof structure, goal boundaries, and dependency information are often invisible at the surface syntax level.
+  Interactive proof development exposes **intermediate goals and contexts** that never appear in completed source files.

For these reasons, ProofParser treats Agda as a **semantic oracle**.

> Agda elaborates, scopes, and type-checks the code; ProofParser observes and records the resulting structure.

This design choice is essential for training agents that reason about *meaningful proof states*, not just text.

---

## Extraction Modes

ProofParser supports several complementary extraction paths, each serving a different purpose.

### 1. Interactive Extraction (Agda-driven)

This is the most semantically rich mode.

In interactive extraction, ProofParser

1.  launches Agda with the `--interaction-json` flag,
2.  loads one or more Agda modules,
3.  observes Agda's JSON interaction messages as the typechecker runs,
4.  records live **proof goals**, **contexts**, **ranges**, and **imports**.

This mode captures

+  the exact goal type Agda is trying to solve,
+  the surrounding context (bound variables with types),
+  source ranges and module information,
+  optional solution terms when goals are closed.

These snapshots are represented using the `TrainRecord` schema and are especially well suited for

+  goal-conditioned learning,
+  interactive proof search,
+  imitation learning from partial proofs.

This extractor is implemented in

+  `AgdaSimplifiedExtractor.scala`
+  `AgdaBridge.scala` (communication with the Agda process)

---

### 2. Offline Extraction (Batch, Agda-mediated)

Offline extraction targets **completed Agda libraries**, but it is still **Agda-mediated**, not a purely syntactic pass over source files.

In this mode, ProofParser ultimately relies on **Agda to elaborate and type-check the code**, and then extracts information from **Agda-produced artifacts** (or Agda-informed dumps), rather than attempting to infer semantics directly from surface syntax.

Concretely, offline extraction proceeds by one of the following routes:

+  Invoking Agda to type-check a library and emit structured information (directly or indirectly), or
+  Consuming Agda-generated JSON dumps (e.g. agda2train-style outputs) that already reflect elaboration, scope resolution, and implicit argument insertion.

From this Agda-mediated data, ProofParser extracts

+  fully type-checked theorem and definition statements,
+  corresponding proof terms *after elaboration*,
+  dependency information (premises actually used in proofs).

The resulting rows are represented using the `AgdaData` schema.

Offline extraction is appropriate for

+  building large static corpora from mature libraries,
+  premise-selection datasets,
+  theorem classification tasks.

> **Important:** ProofParser is deliberately designed so that even its offline paths do **not** rely on naive text scraping. Any mode that bypasses Agda entirely would necessarily lose essential semantic information (scope, implicits, elaborated types) and is therefore less useful as a generator of training data.

That said, the architecture leaves room for *experimental* lightweight extractors for exploratory analysis, but these are not treated as authoritative data sources.

---

### 3. Transformation and Reduction

ProofParser also supports **transformation** of existing semi-structured Agda datasets (e.g. agda2train-style JSON),

+  normalizing file and module paths,
+  filtering self-premises and noise,
+  converting heterogeneous formats into stable internal schemas.

This makes it possible to

+  reuse external datasets,
+  compare different extraction strategies,
+  maintain backward compatibility as upstream formats evolve.

---

## Data Models

ProofParser defines two primary data schemas.

### `AgdaData` — Static Declarations

Represents a completed theorem or definition after type checking.

Typical fields include

+  file and module identifiers,
+  declaration name,
+  fully elaborated type,
+  proof term,
+  list of premises used.

This schema is used for **static learning tasks**.

---

### `TrainRecord` — Interactive Goal Snapshots

Represents a single interactive proof state emitted by Agda.

A `TrainRecord` captures

+  the current goal type,
+  the local context (names and types),
+  source range information,
+  optional solution terms.

This schema is used for **goal-conditioned and interactive learning**.

---

## Why Scala (and Spark)?

ProofParser is implemented in **Scala**, with optional use of **Apache Spark** for downstream processing.

This choice is deliberate.

### Scala

Scala provides

+  a **strong static type system**, well matched to modeling structured proof data,
+  algebraic data types and pattern matching for robust JSON handling,
+  interoperability with mature JVM tooling,
+  good ergonomics for medium-sized research infrastructure.

The goal is to make data contracts explicit and refactor-safe as the project evolves.

---

### Spark

When processing large corpora, Spark enables

+  scalable batch transformations (JSONL → Parquet → features),
+  deterministic, reproducible dataset construction,
+  separation between *extraction* and *learning* concerns.

Spark is used where it adds value, but ProofParser itself does **not** require a cluster or heavy infrastructure to get started.

---

## Running ProofParser

### With Nix (recommended)

From the repository root:

```bash
nix develop
```

This provides Agda, Scala, sbt, and all required dependencies.

---

### Common Tasks

From the repository root:

```bash
make extract        # Offline extraction (.agda → JSONL)
make transform      # Transform existing Agda JSON → JSONL
make smoke          # Compile + quick sanity checks
```

For finer control, ProofParser programs can also be invoked directly via `sbt runMain`.

---

## Tests and Sanity Checks

ProofParser includes

+  unit tests for core schemas and utilities,
+  small example datasets,
+  smoke tests to validate end-to-end extraction.

These are intended to ensure **dataset stability** as the code evolves.

---

## Research Notes and Roadmap

**ProofParser is deliberately designed as a research platform rather than a one-off script.**

In particular, we are continually exploring new ways to improve it.  Here are some examples of what we are working on now and/or in the near future.

+  Deeper integration with Agda's internal representations (e.g. ASTs, scopes).

   **Phase 1**: Treat Agda as a black-box semantic oracle (today)

   **Phase 2**: Instrument Agda more deeply (ASTs, scopes, elaboration artifacts)

   **Phase 3**: Experiment with

   + alternative backends,
   + modified IOTCM protocols,
   + or custom semantic emitters.
+  Richer representations of proof steps and tactics.
+  Cross-corpus normalization and comparison.

---

## See Also

+  Root project README
+  `agda-jang/README.md`
+  `ml-pipeline/README.md`
