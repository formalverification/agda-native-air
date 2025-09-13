<!-- agda-ai-prover/proof-parser/README.md -->

# Proof Parser

The **proof-parser** module extracts structured data from Agda sources.  
It converts `.agda` code into JSON/JSONL datasets suitable for ML tasks such as premise selection, proof synthesis, or theorem classification.

---

## 📦 Components

- **`AgdaExtractor.scala`**  
  Scans `.agda` files for definitions and theorem-like constructs, producing `(name, type, proof)` triples.

- **`AgdaJsonParser.scala`**  
  Reads Agda’s JSON interaction output (agda2train/QUILL-style) and normalizes it.

- **`Agda2TrainTransformer.scala`**  
  Transforms JSON into a clean ML-ready JSONL format with fields:
  - `file`, `module`, `name`
  - `agdaType`
  - `proof`
  - `premises` (lemma names used inside the proof)

---

## 📂 Directory Layout

```
proof-parser/
├── src/main/scala/proofparser/
│   ├── AgdaExtractor.scala
│   ├── AgdaJsonParser.scala
│   └── Agda2TrainTransformer.scala
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
