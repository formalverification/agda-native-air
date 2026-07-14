# Benchmark Suite — `data/benchmarks/`

**Issue:** M1-5 — Curate baseline benchmark (#13)
**Agda:** 2.8.0  **standard-library:** 2.3  (both pinned by `flake.lock`)

The baseline benchmark is a set of Agda proof obligations with committed gold
solutions, used as the standard evaluation set for subsequent experiments.
Every gold solution type-checks under the pinned toolchain; type-checking is the
ground truth for a benchmark entry.

---

## Contents (v0)

The current suite has **22 obligations**, all drawn from `agda-stdlib`, spanning
the three difficulty tiers of `docs/benchmarks/taxonomy.md`:

| Tier | Count | Examples |
|---|---|---|
| `routine` | 7 | `+-identityˡ` (`refl`), `not-involutive`, `tt : ⊤`, `0 < suc n` |
| `compositional` | 10 | `+-comm`, `+-assoc`, `*-zeroʳ`, `length-++`, `map-id`, `++-assoc` |
| `non-obvious` | 5 | `*-comm`, `*-distribʳ-+`, `*-distribˡ-+`, `*-assoc`, `map′` (`Dec`) |

Domains covered: arithmetic, list, logic, maybe, order.  `agda-algebras`
obligations are planned for a later round (see `docs/benchmarks/obligations.md`);
they require a local `agda-algebras` checkout and so are tracked separately.

## Directory Layout

```
data/benchmarks/
├── README.md                          # this file
├── benchmark-index.jsonl              # machine-readable index of all obligations
├── agda-stdlib-v0/
│   ├── obligations/                   # .agda files with one {!!} hole each
│   │   ├── Nat-plus-identityL.agda
│   │   ├── Nat-plus-comm.agda
│   │   └── ...
│   └── gold/                          # solved .agda files (gold solutions)
│       ├── Nat-plus-identityL.agda
│       ├── Nat-plus-comm.agda
│       └── ...
└── agda-algebras-v0/                  # planned — requires a local agda-algebras checkout
    ├── obligations/
    └── gold/
```

Tier definitions and selection criteria live in `docs/benchmarks/taxonomy.md`;
the proposed obligation catalog (including the planned `agda-algebras` entries)
lives in `docs/benchmarks/obligations.md`.

## Fixture Convention

Each obligation is a self-contained Agda module:

+  It imports `AgdaDojang.Debug` and exactly the stdlib modules it needs.
+  It contains exactly **one** `{!!}` hole to be filled.
+  The module name matches the filename stem.
+  Any prerequisite lemmas are provided as explicit imports — the obligation may
   import lemmas, just not the definition it is asked to prove.

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
| `goldTerm` | string | The proof term (or a short sketch) that fills the hole |
| `hole` | string | Name of the definition with the hole |
| `type` | string | Pretty-printed type signature of the obligation |
| `difficulty` | string | One of `"routine"`, `"compositional"`, `"non-obvious"` |
| `domain` | string | Domain tag (e.g., `"arithmetic"`, `"list"`, `"logic"`) |
| `proofStrategy` | string | Primary proof technique (e.g., `"refl"`, `"induction"`) |
| `tags` | list[string] | Additional tags for slicing (e.g., `["standalone"]`) |

Example line:

```json
{"id":"stdlib-nat-plus-identity-r","source":"agda-stdlib","module":"Data.Nat.Properties","obligation":"data/benchmarks/agda-stdlib-v0/obligations/Nat-plus-identityR.agda","gold":"data/benchmarks/agda-stdlib-v0/gold/Nat-plus-identityR.agda","goldTerm":"induction on n; base refl, step cong suc IH","hole":"+-identityʳ","type":"∀ (n : ℕ) → n + 0 ≡ n","difficulty":"compositional","domain":"arithmetic","proofStrategy":"induction","tags":[]}
```

## Type-checking the gold solutions

A gold solution counts only if Agda accepts it.  Inside the flake shell, the
`agda` wrapper registers `standard-library` and the repo-local `agda-dojang`
library, so a gold file checks directly:

```sh
nix develop .#backend --command agda data/benchmarks/agda-stdlib-v0/gold/Nat-plus-comm.agda
```

To verify the whole suite in one step, use the Makefile targets from inside the
Agda-capable dev shell:

```sh
nix develop .#backend --command make eval-benchmark        # all committed golds
nix develop .#backend --command make eval-benchmark-smoke  # one-per-tier CI slice
```

`make eval-benchmark` runs `struxdriver.benchmark.EvalBenchmark --verify-gold`
over the index and writes a JSON report to
`data/benchmarks/reports/gold-verification.json` (gitignored).  The report
records a wall-clock `timestamp` and per-obligation `elapsedMs`; the run is
deterministic modulo those fields, and `eval-benchmark-smoke` strips them before
checking that two runs match.

## agda-algebras obligations (planned)

`agda-algebras` is not Nix-managed; it requires a local clone.  Set
`AGDA_ALGEBRAS_ROOT` to the checkout root (the directory containing the
`.agda-lib` file) before entering the shell, and the flake registers the library
so its modules become importable:

```sh
AGDA_ALGEBRAS_ROOT=~/git/ualib/agda-algebras/master nix develop .#backend
```

Until those obligations are authored and committed, the suite is `agda-stdlib`
only.
