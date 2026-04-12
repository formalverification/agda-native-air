# Benchmark Suite — `data/benchmarks/`

**Issue:** M1-5 — Curate baseline benchmark
**Agda:** 2.8.0
**stdlib:** as pinned by `nixpkgs-agda` (Agda 2.8.0 from `nixos-unstable`)

---

## Directory Layout

```
data/benchmarks/
├── README.md                          # this file
├── benchmark-index.jsonl              # machine-readable index of all obligations
├── difficulty-taxonomy.md             # tier definitions and selection criteria
├── agda-stdlib-v0/
│   ├── obligations/                   # .agda files with {!!} holes (one per obligation)
│   │   ├── Nat-plus-identityR.agda
│   │   ├── Nat-plus-comm.agda
│   │   └── ...
│   └── gold/                          # solved .agda files (gold solutions)
│       ├── Nat-plus-identityR.agda
│       ├── Nat-plus-comm.agda
│       └── ...
├── agda-algebras-v0/
│   ├── obligations/                   # .agda files with {!!} holes
│   │   └── ...
│   └── gold/                          # solved .agda files
│       └── ...
└── reports/                           # evaluation output (gitignored)
    └── ...
```

## Fixture Convention

Each obligation is a self-contained Agda module:

- Imports `AgdaDojang.Debug` (for the `reportGoalCtx` macro)
- Imports exactly the stdlib / agda-algebras modules needed
- Contains exactly **one** `{!!}` hole to be filled
- The module name matches the filename stem

The corresponding gold file is identical except the hole is replaced with the
correct proof term.

## JSONL Index Schema (`benchmark-index.jsonl`)

Each line is a JSON object with the following fields:

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique obligation identifier (e.g., `stdlib-nat-plus-comm`) |
| `source` | string | `"agda-stdlib"` or `"agda-algebras"` |
| `module` | string | Fully qualified source module (e.g., `Data.Nat.Properties`) |
| `obligation` | string | Path to the obligation `.agda` file (relative to repo root) |
| `gold` | string | Path to the gold solution `.agda` file (relative to repo root) |
| `goldTerm` | string | The proof term that fills the hole |
| `hole` | string | Pretty-printed name of the definition with the hole |
| `type` | string | Pretty-printed type signature of the obligation |
| `difficulty` | string | One of `"routine"`, `"compositional"`, `"non-obvious"` |
| `domain` | string | Mathematical domain tag (e.g., `"arithmetic"`, `"algebra"`) |
| `proofStrategy` | string | Primary proof technique (e.g., `"refl"`, `"induction"`) |
| `tags` | list[string] | Additional tags for slicing (e.g., `["universe-poly"]`) |

Example line:

```json
{"id":"stdlib-nat-plus-comm","source":"agda-stdlib","module":"Data.Nat.Properties","obligation":"data/benchmarks/agda-stdlib-v0/obligations/Nat-plus-comm.agda","gold":"data/benchmarks/agda-stdlib-v0/gold/Nat-plus-comm.agda","goldTerm":"...","hole":"+-comm","type":"∀ m n → m + n ≡ n + m","difficulty":"compositional","domain":"arithmetic","proofStrategy":"induction","tags":[]}
```

## Evaluation

- `make eval-benchmark-gold` — typecheck all gold solutions (regression guard)
- `make eval-benchmark` — run the propose→check evaluator on all obligations;
  produce a JSON report under `data/benchmarks/reports/`

## agda-algebras Setup

Unlike stdlib (which is Nix-managed), agda-algebras requires a local clone.
Set `AGDA_ALGEBRAS_SRC` to point at your `agda-algebras/src/` directory:

```sh
make eval-benchmark AGDA_ALGEBRAS_SRC=~/git/ualib/agda-algebras/master/src
```

Obligations that require agda-algebras are skipped if `AGDA_ALGEBRAS_SRC` is unset.
