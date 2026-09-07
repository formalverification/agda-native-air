# Benchmark Suite — `data/benchmarks/`

**Issue:** M1-5 — Curate baseline benchmark (#13)
**Agda:** 2.8.0  **standard-library:** 2.3  (both pinned by `flake.lock`)

The baseline benchmark is a set of Agda proof obligations with committed gold
solutions, used as the standard evaluation set for subsequent experiments.
Every gold solution type-checks under the pinned toolchain; type-checking is the
ground truth for a benchmark entry.

---

## Contents (v0)

The current suite has **43 obligations** from two libraries, spanning the three
difficulty tiers of `docs/benchmarks/taxonomy.md`.

The **`agda-stdlib` tier** (22 obligations) is the original M1-5 cut and is
**frozen**: the P1 baseline (issue #113) is quoted against it, so it only ever
grows by whole new tiers, never by edits.

| Tier | Count | Examples |
|---|---|---|
| `routine` | 7 | `+-identityˡ` (`refl`), `not-involutive`, `tt : ⊤`, `0 < suc n` |
| `compositional` | 10 | `+-comm`, `+-assoc`, `*-zeroʳ`, `length-++`, `map-id`, `++-assoc` |
| `non-obvious` | 5 | `*-comm`, `*-distribʳ-+`, `*-distribˡ-+`, `*-assoc`, `map′` (`Dec`) |

Domains covered: arithmetic, list, logic, maybe, order.

The **`agda-algebras` tier** (21 obligations, issue #127) is the re-cut second
half of #13, mined from the agda-algebras corpus so the benchmark and the
corpus are cut from the same library at the same commit:

| Tier | Count | Examples |
|---|---|---|
| `routine` | 6 | `lift∼lower` (`refl`), the `Op` projection, `Image F ∋ (F ⟨$⟩ a)` |
| `compositional` | 10 | `SurjInv` inverse law, `⊙-injective`, `𝒾𝒹`/`⊙-hom`, `mon→hom`, `≥`-laws |
| `non-obvious` | 5 | `≤-reflexive`, `≤-trans`, `≤-trans-≅`, `kercon`, `ker-in-con` |

Domains: setoid, algebra, universe.

### agda-algebras tier: selection criteria and provenance

+  **Library commit**: `4662373d281daf0f20a6319f1a46755a45d33293` — equal by
   construction to the corpus provenance commit (dataset card
   `docs/corpora/agda-algebras-v0.1.md`) and to the `agda-algebras-src` flake
   input, so the benchmark's library, the corpus's library, and the toolchain's
   library can never drift apart silently.
+  **Corpus-mined**: candidates are corpus rows with `defKind: function`, a
   body, and a *plausibly single-term* proof (length-bounded,
   transport-marker-free — an approximation, since the corpus records no
   per-row clause count; single-term-ness is established when each gold is
   restated and type-checked as one term) in
   the `Overture`/`Setoid` namespaces — the committed filter is
   `scripts/python/corpus/mine_benchmark_candidates.py`; run it as
   `python3 scripts/python/corpus/mine_benchmark_candidates.py --corpus
   data/corpora/agda-algebras/v0.1/corpus.jsonl.gz`.  Tier classification,
   import strata, and deprecation checks are then by hand against the library
   source, per the taxonomy.
+  **Single-term golds only**: the P1 term-mode ceiling therefore does not bind
   this tier — every gold is expressible as one `fill_hole` term by
   construction (21/21).  What binds is the action space, which is the point:
+  **Import strata** (recorded per obligation in `tags`):
   `stratum:using` (11 obligations) imports its lemma pool through narrow
   `using` lists, so the P1 fixed action space keeps footing;
   `stratum:wholesale` (10 obligations) opens agda-algebras modules with **no**
   `using` list, starving the fixed space by design so that P2 retrieval
   uplift on these rows is attributable to retrieval and nothing else.
+  **Wholesale-stratum semantics, stated plainly**: opening a module wholesale
   brings the restated lemma's own library name into scope (fixture
   definitions carry a prime — `lift∼lower′` — to avoid the clash).  A
   searcher that retrieves and applies the library's original lemma has
   legitimately found the needle in the haystack; excluding the target from
   the candidate pool is the P2 target-exclusion policy's job, not the
   fixture's.

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
└── agda-algebras-v0/
    ├── obligations/                   # 21 modules, one {!!} hole each
    └── gold/                          # solved twins
```

Tier definitions and selection criteria live in `docs/benchmarks/taxonomy.md`;
the original design catalog lives in `docs/benchmarks/obligations.md` (its
`agda-algebras` sketches are superseded by the committed tier above).

## Fixture Convention

Each obligation is a self-contained Agda module:

+  It imports `AgdaDojang.Debug` and exactly the stdlib modules it needs.
+  It contains exactly **one** `{!!}` hole to be filled.
+  The module name matches the filename stem.
+  Any prerequisite lemmas are provided as explicit imports — the obligation may
   import lemmas, just not the definition it is asked to prove.  Wholesale-stratum
   agda-algebras fixtures qualify this deliberately: their module-wide `open`
   necessarily brings the restated lemma's own library name into scope (see the
   stratum semantics above) — the gold still never *applies* it, and keeping the
   original reachable is the stratum's point, since retrieving it is a legitimate
   find and excluding it is the P2 target-exclusion policy's job.

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

### Checking a single fixture in an editor

Each agda-algebras fixture directory carries its own `.agda-lib` project file
(`gold/` and `obligations/` separately: the twin modules share top-level
names, so one shared library would make every module ambiguous).  Any tool
that resolves the nearest project file — agda-mode in an editor, agda-mcp's
`check_file`, or a bare `agda` — can therefore check a fixture in isolation.
One caveat for the CLI: Agda anchors project discovery at the *current
directory*, not the target file, so run it from the fixture's own directory
(editors do this naturally):

```sh
cd data/benchmarks/agda-algebras-v0/gold
agda --library-file=../../../../agda/libraries Homs-comp-hom.agda
```

The `depend:` names resolve against the repo registry `agda/libraries`,
which every dev-shell entry (re)writes.  A gold checks green; an obligation
checks to exactly one `UnsolvedInteractionMetas` error at its hole — the
expected outcome for a file whose point is the open hole (in an editor it
simply loads, hole open).  The harness itself never relies on these project
files: `EvalBenchmark` and the search loop pass their library flags
explicitly, so fixture verification is identical with or without them.

## The agda-algebras library

The library is Nix-managed since #127: the flake pins `ualib/agda-algebras` at
the benchmark commit as the `agda-algebras-src` input and builds it once into a
store path with prebuilt `.agdai` interfaces (Cachix-cached), which every
Agda-capable shell registers automatically — CI and fresh machines need no
checkout and no library build.  A developer working against a live checkout
still overrides it the old way:

```sh
AGDA_ALGEBRAS_ROOT=~/git/ualib/agda-algebras/master nix develop .#backend
```

`EvalBenchmark` passes `--library agda-algebras` for this tier's rows only, so
the frozen stdlib rows are verified in an unchanged environment.

## License

These fixtures are Agda source written for this repository, so the repository's
code license applies: [Apache-2.0](../../LICENSE).  They import the Agda
standard library, which carries its own (MIT) license and is not vendored here.
See the "Licensing" section of the top-level `README.md` for the wider policy on
data.
