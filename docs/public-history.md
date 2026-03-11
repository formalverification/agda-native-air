<!-- File: docs/public-history.md -->

## Public History: notes on the migration

When making this project public, we migrated from v.0.1 (agda-ai-prover) to v.1.0 (agda-native-air).
Here are some notes on the migration.

### 1. New public repo identity

Use

+  **repo name:** `agda-native-air`
+  **tagline:** Agda-native AI reasoning environment
+  **primary components:** `agda-dojang`, `agda-mcp`, `agda-strux` structured corpus extraction
   (de-emphasizing "small local prover" and "AI mathematician" as immediate deliverables).

This gives newcomers a clean entry point while still preserving the long-range vision
in the `MANIFESTO.md`.


### 2. What to carry over intact

These are the parts that are already the backbone of the story.

+  `MANIFESTO.md` → replace with `docs/MANIFESTO.md` v2.2;
+  `PLAN.md` → replace with `docs/PLAN.md` v2.2;
+  `docs/representation.md`;
+  `docs/HowToRun.md` after cleanup;
+  `agda-jang` **Agda interaction/evaluation tooling** → rename `agda-dojang`;
+  the **fixture-based proof-completion demo**;
+  **structured extraction pipeline** `agda-backend-jsonl` → rename `agda-strux` +
   `AgdaJsonlDriver.scala` and the docs describing them;
+  **core Make targets** (e.g., `make extract-lib`, `make eval-proof-completion`),
   that demonstrate extraction and evaluation.

...basically, just the pieces that are still relevant in the new manifesto/plan,
which show the project has some history and we've already developed some useful tools
and infrastructure.

### 3. What to rename

We rename the following immediately in the public repo:

+  "AgdaJang" → **"AgdaDojang"**
+  `agda-jang` → **`agda-dojang`**
+  "AgdaBridge" terminology → **AgdaDojang / agda-mcp bridge**
+  `agda-backend-jsonl` → **`agda-strux`**
+  `agda-ai-prover` → **`agda-native-air`**

For the first public phase, we keep small compatibility notes in docs, but the old
branding is no longer prominent.

---

### 4. What to keep but move to secondary status

We keep the following, but do not let them dominate the top-level story:

+  local-model training scripts
+  retrieval-model experiments
+  older policy backends
+  researchy derived-view experiments
+  older roadmap material about conjecture generation and strategy synthesis

We move such artifacts to `experiments/archive/` to keep the work visible and
accessible while avoiding repo sprawl.

---

### 5. What to archive or leave behind

We do **not** migrate everything to the new public repo.

We leave behind and/or heavily prune the following:

+  stale issue references embedded in docs;
+  half-baked FastAPI-centric framing;
+  abandoned or superseded training targets;
+  duplicate READMEs and transitional notes;
+  one-off scripts that only made sense during internal iteration;
+  old branches of the plan that assumed the project's goal was "train a theorem
   prover."

---

### 6. Top-level public layout

```text
agda-native-air/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── docs/
│   ├── MANIFESTO.md
│   ├── PLAN.md
│   ├── architecture.md
│   ├── representation.md
│   ├── architecture.md
│   ├── HowToRun.md
│   ├── roadmap.md
│   └── public-history.md
├── agda-dojang/
│   ├── README.md
│   ├── agda/
│   ├── python/
│   ├── tests/
│   └── Makefile
├── agda-strux/
│   ├── README.md
│   ├── backend/
│   ├── etl/
│   └── tests/
├── agda-mcp/
│   ├── README.md
│   └── mcp/
├── data/
│   └── fixtures/
├── experiments/
│   ├── retrieval/
│   ├── local-models/
│   └── archive/
└── scripts/
```

The repo is organized around the new public architecture, which consists of the
following primary components:

+  **interaction**
+  **extraction**
+  **bridge**
+  **fixtures/evaluation**
+  **experiments**

---

### 7. Git-history strategy

#### Steps which led to the public agda-native-air repo

+  create `agda-native-air` as a **new repo**
+  import selected directories using **history-preserving subtree/filter-repo extraction**
+  create this `docs/public-history.md` artifact explaining that the public repo is a
   curated continuation of a prior private development effort.

---

### 8. Migration units

We split migration into four units so history stays meaningful.

**Unit A — AgdaDojang**.

+  move `agda-jang/` → `agda-dojang/`
+  preserve history
+  clean README
+  keep evaluator + fixtures

**Unit B — Extraction spine**.

+  move `agda-backend-jsonl/` → `agda-strux/`
+  move the backend/ETL/extraction docs and tests
+  preserve history
+  prune dead experimental scripts

**Unit C — Public docs**.  Start fresh for

+ README
+ MANIFESTO
+ PLAN
+ CONTRIBUTING
+ architecture docs

**Unit D — Experimental leftovers**.  Selectively copy, not fully preserve, anything
that is still useful but not central.

