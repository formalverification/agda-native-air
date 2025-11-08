<!-- agda-ai-prover/proof-parser/README.md -->

# Proof Parser

The **proof-parser** module extracts structured data from Agda sources; it converts
`.agda` code into JSON/JSONL datasets suitable for ML tasks such as premise
selection, proof synthesis, or theorem classification.

---

## Quickstart: JSON → JSONL (Transformer)

Use this path if you already have an Agda-to-JSON dump (e.g., from `AgdaExtractor` or prior tooling).

```bash
# Example: transform one JSON file into JSONL rows for training
# Run the following command from the `agda-ai-prover/proof-parser` directory:
sbt "runMain proofparser.Agda2TrainTransformer \
  src/test/resources/agda-example.json \
  ../target/a2t.simple.jsonl"
```

**Output format (per line):**

```json
{
  "file": "agda-example",              // base file/module root (no extension)
  "module": "properties",              // optional, e.g., submodule
  "name": "+-comm",                    // local def/theorem name
  "agdaType": "(m n : ℕ) → ...",
  "proof": "…",
  "premises": ["agda-example._+_", "..."]
}
```

Notes:

* We normalize `file` to a base name without `.agda`.
* We drop any self-references from `premises`.
* External references (e.g., stdlib) may appear verbatim.

---

## Programs in the `proof-parser` Package

### Models and Schemas

+  **Model.scala / SimpleSchema.scala**: central data contracts + (optionally) small
   validators.

   +  **Model.scala** defines canonical data classes used across the package
      (`AgdaData`, maybe `Goal`, etc.). This is the “single source of truth” for the
      training-row schema.

   +  **SimpleSchema.scala**. A minimal, explicit schema for reading/writing rows.
      Sometimes used to validate input data or encode/decode within Spark/ETL.

+  **AgdaBridge.scala**: byte-pipe to `agda --interaction-json`. No project deps.

### Transformers and Reducer

+  **Agda2TrainTransformer.scala**

   The richer path that yields `AgdaData`.

   This turns *offline* Agda dumps into canonical `AgdaData` rows.  No dependency on
   the bridge/extractor.

+  **Agda2TrainReducer.scala**

   The “human-readable” subset CLI. It’s fast to run during development and nice for
   spot-checks.

   This is a lighter-weight “mapper” that takes raw extractor JSON and reduces it to
   a simpler subset (used when we want fewer fields). (Subset of the transformer.)



### Parsers and Extractors

*  **AgdaJsonParser.scala**.  Utility functions to parse Agda-specific JSON
   structures. Good candidate to centralize traversal helpers so multiple modules
   don’t re-implement small walkers.

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



### Tests and Benchmarks

#### Dataset stats & premise-selection micro-benchmark

These utilities help sanity-check extracted Agda training rows (JSONL) and give a tiny, deterministic baseline for premise selection.

+  `DatasetStats.scala`: a tidy stats tool (row counts, length summaries, top premises/modules, premises-per-row histogram).

+  `PremiseEval.scala`: a small, deterministic premise-selection benchmark (hash split, global/per-module frequency baselines, Precision@K / Recall@K / F1, coverage).


**Quick start**

```bash
# Show top-level help
make help

# 1) Summarize a dataset (row counts, length stats, histograms)
make dataset-stats DATASET=path/to/train.jsonl TOP=20

# 2a) Fast micro-benchmark (smaller K, same split)
make premise-eval-quick DATASET=path/to/train.jsonl K=5 SPLIT=90

# 2b) Full micro-benchmark (both baselines at K=10, 90/10 hash split)
make premise-eval DATASET=path/to/train.jsonl K=10 SPLIT=90
```

**Interpreting outputs**

* `DatasetStats`: prints

  * corpus summary (#rows, non-empty fields),
  * char-length stats for `agdaType` and `proof` (min/p50/p90/p99/max/avg),
  * top-K `premises` and `module` histograms,
  * distribution of “premises per row”.

* `PremiseEval`: runs two trivial baselines

  * **GlobalFreq**: ranks premises by overall training frequency,
  * **PerModuleFreq**: ranks by per-module frequency with global fallback.
    Reports **Precision@K**, **Recall@K**, **F1@K**, and **coverage** (fraction of test rows with ≥1 correct prediction). The split is stable (hash of `(file,module,name)`), so repeated runs are identical.

**Pro tip:** Use `make smoke` to quickly check that essential targets still run after refactors (see below). Customize which targets are checked via `SMOKE_TARGETS=...`.



---

## Test Harness for the `proof-parser` Package

### Layout

```
proof-parser/
  src/test/scala/proofparser/
    TestKit.scala                         // small helpers (resource loading, gens)
    Agda2TrainTransformerSpec.scala       // parsing + self-premise tests (unit)
    AgdaSimplifiedExtractorSpec.scala     // pure parts only: iotcmLoad/moduleName/goals (unit)
  src/test/resources/proofparser/
    agda-example.json                     // copy of your sample JSON for tests
```

+  **TestKit.scala**: small utility to load test resources and define arbitrary generators.
+  **Agda2TrainTransformerSpec.scala**: deterministic tests for parsing and self-premise filtering.
+  **AgdaSimplifiedExtractorSpec.scala**: tests the *pure bits* (e.g., `iotcmLoad` shape, `moduleName`, and `extractGoalsPretty` using canned JSON). We don’t spin up Agda in unit tests; integration with Agda will be a separate “it” or `IT` suite later.


---

## Extract directly from Agda (IOTCM bridge)

This path asks Agda to scope-check/type-check your file and emits training rows from goals/pretty text.

**Prereqs:**

* Agda ≥ 2.7 (you’re on 2.8.0 ✅)
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

Flags:

* `--include DIR` (repeatable): add import search paths (Agda’s `-i`).
* `--lib NAME`: use a registered library (Agda’s `-l`), e.g., `standard-library`.
* `--libraries-file FILE`: alternate libraries index file (Agda’s `--library-file`).

> Tip: Agda doesn’t have `--library-path`; use `--library-file=PATH/TO/libraries` to point at a custom libraries file, or just `--lib standard-library` if it’s already registered.

---

## 📦 Components

+  **`AgdaExtractor.scala`**

   Scans `.agda` files for definitions and theorem-like constructs, producing `(name,
   type, proof)` triples.

+  **`AgdaExtractorMain.scala`**

   Main program to extract proofs from Agda files and output them in JSONL format.
   Writes output to files `data/train.jsonl` **and** `data/train.manifest.json`.

+  **`AgdaJsonParser.scala`**

   Reads Agda's JSON interaction output (agda2train/QUILL-style) and normalizes it.

+  **`Agda2TrainTransformer.scala`**
   Transforms JSON into a clean ML-ready JSONL format with fields:
   - `file`, `module`, `name`
   - `agdaType`
   - `proof`
   - `premises` (lemma names used inside the proof)

+  **`Model.scala`**
   Data model for Agda theorem extraction

---

## 📂 Directory Layout

```
proof-parser/
├── build.sbt
├── README.md
└── src/
    ├── main/
    │   └── scala/
    │       └── proofparser/
    │           ├── Agda2TrainReducer.scala
    │           ├── Agda2TrainTransformer.scala
    │           ├── AgdaBridge.scala
    │           ├── AgdaExtractorMain.scala
    │           ├── AgdaExtractor.scala
    │           ├── AgdaJsonParser.scala
    │           ├── AgdaSimplifiedExtractor.scala
    │           ├── Model.scala
    │           └── SimpleSchema.scala
    └── test/
        ├── resources/
        │   ├── agda-example.agda
        │   └── proofparser/
        │       └── agda-example.json
        └── scala/
            └── proofparser/
                ├── Agda2TrainTransformerSpec.scala
                ├── AgdaExtractorSpec.scala
                ├── AgdaSimplifiedExtractorSpec.scala
                ├── ModelSpec.scala
                ├── SimpleSchemaSpec.scala
                └── TestKit.scala
```

---

## 🛠️ Setup

### With sbt

```bash
cd proof-parser
sbt compile
sbt test
```

---

## 🧪 Usage

### ✅ Extract theorems directly from `.agda`

```bash
sbt "run /absolute/path/to/agda-example.agda"
```

Produces `theorems.jsonl` with raw name/type/proof triples.

---

### ✅ Convert JSON → JSONL

```bash
sbt "runMain proofparser.Agda2TrainTransformer ../data/agda-example.json ../data/agda-example.jsonl"
```

Fields:

```json
{
  "file": "agda-example.agda",
  "module": "Example",
  "name": "+-comm",
  "agdaType": "(m n : ℕ) → (m + n) ≡ (n + m)",
  "proof": "...",
  "premises": ["cong", "trans", "+-suc", "+-comm"]
}
```

---

## 📚 References

* [QUILL: Learning Structure-Aware Representations of Dependent Types](https://arxiv.org/abs/2402.02104)
* [agda2train Dataset Generator](https://github.com/omelkonian/agda2train)

---

## 🚧 Roadmap

* Batch mode for large library extraction (Agda stdlib, ualib).
* Richer JSON schema (contexts, metas, tactics).
* Integration with ML pipeline for end-to-end training.
