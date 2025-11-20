<!-- agda-ai-prover/proof-parser/README.md -->

# Proof Parser

The **proof-parser** module converts Agda sources and intermediate dumps into
structured JSON/JSONL datasets for machine learning tasks such as **premise
selection**, **proof synthesis**, and **theorem classification**.

It extracts structured data from Agda sources, converting Agda source code
into JSONL with structured `AgdaData` rows.

It supports **offline** extraction from `.agda`, **interactive** extraction via
`agda --interaction-json`, and  **transformation** of `agda2train` JSON dumps.

---

## 🧩 Data Models

The two schema we use to model Agda data are `AgdaData` and `TrainRecord`.

+  **`AgdaData`** is for representing types and proofs that are complete (no holes);

+  **`TrainRecord`** is for representing **interactive** goals and contexts.

### `AgdaData` — Static Declarations / Proofs
Defined in [`Model.scala`](src/main/scala/proofparser/Model.scala):

```scala
final case class AgdaData(
  file: String,
  module: Option[String],
  name: String,
  agdaType: String,
  proof: String,
  premises: List[String] = Nil
)
```

* Represents a theorem or definition after type-checking.
* Used for static datasets (premise selection, theorem classification).
* Normalized via `AgdaDataOps.normalize()`.


### `TrainRecord` — Interactive Goal Snapshots

Defined in [`SimpleSchema.scala`](src/main/scala/proofparser/SimpleSchema.scala):

```scala
final case class TrainRecord(
  file: String,
  module: String,
  decl: String,
  context: List[CtxVar],
  goalType: String,
  solution: Option[String] = None,
  range: Option[Range] = None,
  imports: List[String] = Nil
)
```

* Represents a live goal and context emitted by Agda (`--interaction-json`).
* Used for supervised learning on incomplete proofs.


---

## 🛠️ Extraction and Transformation Tools

| Tool                          | Input                                    | Output                 | Description                                                        |
| ----------------------------- | ---------------------------------------- | ---------------------- | ------------------------------------------------------------------ |
| **`AgdaExtractorMain`**       | `.agda` source files                     | JSONL of `AgdaData`    | Fast, regex-based static extractor (no Agda process).              |
| **`Agda2TrainTransformer`**   | Agda2Train JSON dumps                    | JSONL of `AgdaData`    | Canonical transformer for structured dumps; filters self-premises. |
| **`Agda2TrainReducer`**       | Agda2Train JSON/JSONL                    | JSONL of `TrainRecord` | Tolerant reducer for lightweight schema.                           |
| **`AgdaSimplifiedExtractor`** | Live Agda session (`--interaction-json`) | JSONL of `TrainRecord` | Interactive extractor using `AgdaBridge`.                          |


---


## 🚀 How to Run (two equivalent ways)

### A. From repo root (preferred)

Use `make` targets that live in the **top-level** `Makefile` in the
main `$PROJECT_ROOT` (`agda-ai-prover`) directory .  They call into this subproject.

```bash
# Offline extraction (.agda → data/train.jsonl)
make extract EXTRACT_INPUT=proof-parser/src/test/resources/agda-example.agda

# Transform a dump → JSONL
make transform \
  A2T_JSON=proof-parser/src/test/resources/proofparser/agda-example.json \
  A2T_OUT=target/a2t.simple.jsonl
```

### B. From this directory (`proof-parser/`)

Use `sbt runMain …` to execute the programs directly.

1.  `AgdaExtractorMain`: `.agda` → AgdaData JSONL offline extractor

    ```bash
    # Extract JSONL training data from a .agda file.
    sbt "runMain proofparser.AgdaExtractorMain \
      ../data/agda-example.agda \
      ../data/train.jsonl"
    ```

2.  `Agda2TrainTransformer`: JSON → AgdaData JSONL Transformer

    Use this once you already have an Agda-to-JSON dump (e.g., from `AgdaExtractor` or prior tooling).

    ```bash
    # Transform a JSON file into JSONL rows for training.
    sbt "runMain proofparser.Agda2TrainTransformer \
      src/test/resources/proofparser/agda-example.json \
      ../target/a2t.simple.jsonl"
    ```

3.  `AgdaSimplifiedExtractor`: interactive Agda → TrainRecord JSONL extractor with goals

    ``` bash
    sbt "runMain proofparser.AgdaSimplifiedExtractor \
      ../agda-jang/agda/ApplyDemo.agda \
      ../proof-parser/output/goals.jsonl \
      --include ../agda-jang/agda \
      --lib standard-library \
      --library-file ../agda-jang/agda/libraries"
    ```

    **Flags**

    +  `--include DIR` (repeatable): add import search paths;
    +  `--lib NAME`: use a registered library, e.g., `standard-library`;
    +  `--library-file FILE`: location of Agda library index file.

    **Notes**

    The interactive extractor emits **goals + contexts**, not completed proofs.

---

## Batch Processing from Agda Libraries (IOTCM bridge)

**Prereqs:**

* Agda ≥ 2.7
* Standard library registered (or provide a libraries file)

**Run:**

```bash
# Using your existing libraries file
sbt "runMain proofparser.AgdaSimplifiedExtractor \
  ../agda-jang/agda/ApplyDemo.agda \
  ../proof-parser/output/goals.jsonl \
  --include ../agda-jang/agda \
  --lib standard-library \
  --library-file ../agda-jang/agda/libraries"
```

---

## 📊 Dataset Utilities (stats & micro-benchmark)

These utilities help sanity-check extracted Agda training rows (JSONL) and give a
deterministic baseline for premise selection.

### `DatasetStats.scala`

This is a tidy stats tool (row counts, length summaries, top premises/modules,
premises-per-row histogram).

**Summarize a dataset** (row counts, length stats, histograms):

``` bash
# From main `$PROJECT_ROOT` directory
make dataset-stats DATASET=../data/train.jsonl TOP=20
# or directly, from `agda-ai-prover/proof-parser`
cd proof-parser
sbt "runMain proofparser.DatasetStats data/train.jsonl --top 20"
```

**Outputs**

+  Row and field counts
+  Length stats (`agdaType` / `proof`)
+  Top-K premises and modules
+  Premises-per-row histogram


### `PremiseEval.scala`

This is a small, deterministic premise-selection benchmark (hash split, global/per-module frequency baselines, Precision@K / Recall@K / F1, coverage).

**Fast micro-benchmark** (smaller K, same split):

From main `$PROJECT_ROOT` directory,

``` bash
make gen-sample
make -C proof-parser premise-eval-quick DATASET=../data/sample.jsonl
# OR
make premise-eval-quick DATASET=../data/train.jsonl K=5 SPLIT=90
```

**Full micro-benchmark** (both baselines at K=10, 90/10 hash split):

From main `$PROJECT_ROOT` directory,

``` bash
make premise-eval DATASET=../data/train.jsonl K=10 SPLIT=90
```

or directly, from `agda-ai-prover/proof-parser`

```bash
sbt -error -no-colors "runMain proofparser.PremiseEval  data/train.jsonl --k 10 --split 90"
```


### Interpreting outputs

* `DatasetStats` prints

  * corpus summary (#rows, non-empty fields),
  * char-length stats for `agdaType` and `proof` (min/p50/p90/p99/max/avg),
  * top-K `premises` and `module` histograms,
  * distribution of “premises per row”.

* `PremiseEval` runs two trivial baselines

  * **GlobalFreq** ranks premises by overall training frequency,
  * **PerModuleFreq** ranks by per-module frequency with global fallback.
    Reports **Precision@K**, **Recall@K**, **F1@K**, and **coverage** (fraction of test rows with ≥1 correct prediction). The split is stable (hash of `(file,module,name)`), so repeated runs are identical.


#### What the reports mean

+  **Precision@K** — among the **top K** predicted premises, the fraction that actually appear in the proof’s used-premise set.
+  **Recall@K** — among the premises actually used by that proof, the fraction found within the **top K** predictions.
+  **F1@K** — harmonic mean of Precision@K and Recall@K.
+  **Coverage** — fraction of test rows where **≥1 correct** premise appears among predictions.
+  **Baselines**:

   + **Global-frequency**: same universal ranking for everyone, based on training counts.
   + **Per-module-frequency**: ranking per module; if a module is sparse, fall back to global.

+  **Split** — A **stable** train/test split (hash of `(file,module,name)`), so runs are reproducible.

---

## 🧪 Tests & Smoke

From **proof-parser/**:

```bash
make test                   # unit tests
make smoke                  # compile + quick eval
make gen-sample N=16        # create data/sample.jsonl
make smoke-sample           # sample-based smoke run
```

---

## 🔎 More Details


### 📂 Directory Layout

```
proof-parser/
├── src/main/scala/proofparser/
│                  ├── AgdaExtractor*.scala
│                  ├── Agda2Train*.scala
│                  ├── AgdaSimplifiedExtractor.scala
│                  ├── AgdaBridge.scala
│                  ├── AgdaJsonParser.scala
│                  ├── DatasetStats.scala
│                  ├── PremiseEval.scala
│                  ├── Model.scala
│                  └── SimpleSchema.scala
└── src/test/
        ├── scala/proofparser/
        │         ├── *Spec.scala
        │         └── TestKit.scala
        └── resources/
            ├── agda-example.agda
            └── proofparser/
                └── agda-example.json
```


### 📦 Components

Here are some more details about each program in the  `proof-parser` package.

#### Models and Schemas

+  **Model.scala / SimpleSchema.scala**: central data contracts + (optionally) small
   validators.

   +  **Model.scala** defines canonical data classes used across the package
      (`AgdaData`, maybe `Goal`, etc.). This is the “single source of truth” for the
      training-row schema.

   +  **SimpleSchema.scala**. A minimal, explicit schema for reading/writing rows.
      Sometimes used to validate input data or encode/decode within Spark/ETL.

+  **AgdaBridge.scala**: byte-pipe to `agda --interaction-json`. No project deps.

#### Transformers and Reducer

+  **Agda2TrainTransformer.scala**

   Transforms *offline* Agda JSON dumps into clean ML-ready JSONL `AgdaData` rows with fields:
   - `file`, `module`, `name`
   - `agdaType`
   - `proof`
   - `premises` (lemma names used inside the proof)

   (No dependency on the bridge/extractor.)

+  **Agda2TrainReducer.scala**

   The “human-readable” subset CLI. It’s fast to run during development and nice for
   spot-checks.

   This is a lighter-weight “mapper” that takes raw extractor JSON and reduces it to
   a simpler subset (used when we want fewer fields). (Subset of the transformer.)



#### Parsers and Extractors

*  **AgdaJsonParser.scala**.  Utility functions to parse Agda-specific JSON
   structures. Reads Agda's JSON interaction output (agda2train/QUILL-style) and normalizes it.
   Good candidate to centralize traversal helpers so multiple modules don’t re-implement small walkers.

+  **AgdaExtractor.scala / AgdaExtractorMain.scala**

   An earlier (richer) extractor for batch/offline processing; it runs on
   Agda-produced JSON dumps (not via IOTCM).  `AgdaExtractorMain` is the
   CLI entrypoint.

+  **AgdaSimplifiedExtractor.scala** *uses* the bridge, builds/sends `IOTCM` “load”,
   parses incoming JSON, emits training-ready goal rows (JSONL); also standalone.

With the new `AgdaSimplifiedExtractor`, we’ve got the live Agda path; the two
extractors co-exist:

+ **ExtractorMain** for batch/offline processing of pre-dumped JSON,
+ **SimplifiedExtractor** for running Agda and harvesting goals interactively.


---


## 📚 References

* [QUILL: Learning Structure-Aware Representations of Dependent Types](https://arxiv.org/abs/2402.02104)
* [agda2train Dataset Generator](https://github.com/omelkonian/agda2train)

---
