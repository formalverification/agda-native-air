<!-- agda-ai-prover/proof-parser/README.md -->

# Proof Parser

The **proof-parser** module extracts structured data from Agda sources.  
It converts `.agda` code into JSON/JSONL datasets suitable for ML tasks such as premise selection, proof synthesis, or theorem classification.

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
├── src/main/scala/proofparser/
│   ├── AgdaExtractor.scala
│   ├── AgdaExtractorMain.scala
│   ├── AgdaJsonParser.scala
│   ├── Agda2TrainTransformer.scala
│   └── Model.scala
├── src/test/scala/proofparser/
│   ├── AgdaExtractorSpec.scala
│   └── Agda2TrainTransformerSpec.scala
└── README.md
```

---

## 🛠️ Setup

### With sbt

```bash
cd proof-parser
sbt compile
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
