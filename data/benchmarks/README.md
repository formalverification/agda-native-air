# Benchmark Suite — `data/benchmarks/`

**Issue:** [M1-5] Curate baseline benchmark (#13)
**Agda:** 2.8.0  **standard-library:** 2.3  (both pinned by `flake.lock`)

The baseline benchmark is a set of Agda proof obligations with committed gold
solutions, used as the standard evaluation set for subsequent experiments.
Every gold solution type-checks under the pinned toolchain; type-checking is the
ground truth for a benchmark entry.

---

## Contents (v0)

The current suite has **55 obligations** from two libraries, spanning the three
difficulty tiers of `docs/benchmarks/taxonomy.md`: two tiers cut from the Agda
standard library and one from agda-algebras.

The **`agda-stdlib` tier** (22 obligations) is the original [M1-5] cut and is
**frozen**: the P1 baseline (issue #113) is quoted against it, so it only ever
grows by whole new tiers, never by edits.

| Tier            | Count | Examples                                                            |
|-----------------|-------|---------------------------------------------------------------------|
| `routine`       | 7     | `+-identityˡ` (`refl`), `not-involutive`, `tt : ⊤`, `0 < suc n`     |
| `compositional` | 10    | `+-comm`, `+-assoc`, `*-zeroʳ`, `length-++`, `map-id`, `++-assoc`   |
| `non-obvious`   | 5     | `*-comm`, `*-distribʳ-+`, `*-distribˡ-+`, `*-assoc`, `map′` (`Dec`) |

Domains covered: arithmetic, list, logic, maybe, order.

The **`agda-algebras` tier** (21 obligations, issue #127) is the re-cut second
half of #13, mined from the agda-algebras corpus so the benchmark and the
corpus are cut from the same library at the same commit:

| Tier            | Count | Examples                                                                |
|-----------------|-------|-------------------------------------------------------------------------|
| `routine`       | 6     | `lift∼lower` (`refl`), the `Op` projection, `Image F ∋ (F ⟨$⟩ a)`       |
| `compositional` | 10    | `SurjInv` inverse law, `⊙-injective`, `𝒾𝒹`/`⊙-hom`, `mon→hom`, `≥`-laws |
| `non-obvious`   | 5     | `≤-reflexive`, `≤-trans`, `≤-trans-≅`, `kercon`, `ker-in-con`           |

Domains: setoid, algebra, universe.

The **`agda-stdlib-haystack` tier** (12 obligations, issue #129) is the
retrieval instrument: each gold is one application of a standard-library lemma
that the fixture imports but does not `using`-list, so the lemma is reachable
only by its qualified name and a searcher has to *find* it in the imported
module (the haystack) rather than read it off the fixture:

| Tier            | Count | Examples                                                                 |
|-----------------|-------|--------------------------------------------------------------------------|
| `routine`       | 3     | `+-suc m m`, `length-++ xs`, `∧-assoc a b a`                            |
| `compositional` | 5     | `+-mono-≤ le le`, `*-mono-≤ le le`, `+-∸-assoc n le`, `map-++ f xs xs`  |
| `non-obvious`   | 4     | `+-mono-< lt lt`, `m+n≤o⇒m≤o m le`, `m+n≡0⇒m≡0 m eq`, `∷-injectiveˡ eq` |

Domains: arithmetic, order, list, logic.  Haystacks: `Data.Nat.Properties`
(7 obligations), `Data.List.Properties` (3), `Data.Bool.Properties` (2).

### agda-algebras tier: selection criteria and provenance

+  **Library commit**: `4662373d281daf0f20a6319f1a46755a45d33293` equal by
   construction to the corpus provenance commit (dataset card
   `docs/corpora/agda-algebras-v0.1.md`) and to the `agda-algebras-src` flake
   input, so the benchmark's library, the corpus's library, and the toolchain's
   library can never drift apart silently.
+  **Corpus-mined**: candidates are corpus rows with `defKind: function`, a body,
   and a *plausibly single-term* proof (length-bounded, transport-marker-free,
   which is an approximation, since the corpus records no per-row clause count;
   single-term-ness is established when each gold is restated and type-checked as
   one term) in the `Overture`/`Setoid` namespaces; the committed filter is
   `scripts/python/corpus/mine_benchmark_candidates.py`; run it as
   `python3 scripts/python/corpus/mine_benchmark_candidates.py --corpus
   data/corpora/agda-algebras/v0.1/corpus.jsonl.gz`.  Tier classification, import
   strata, and deprecation checks are then by hand against the library source, per
   the taxonomy.
+  **Single-term golds only**: the P1 term-mode ceiling therefore does not bind
   this tier; every gold is expressible as one `fill_hole` term by construction
   (21/21).  What binds is the action space, which is the point.
+  **Import strata** (recorded per obligation in `tags`):
   `stratum:using` (11 obligations) imports its lemma pool through narrow `using`
   lists, so the P1 fixed action space keeps footing; `stratum:wholesale`
   (10 obligations) opens agda-algebras modules with **no** `using` list, starving
   the fixed space by design so that P2 retrieval uplift on these rows is
   attributable to retrieval and nothing else.
+  **Wholesale-stratum semantics, stated plainly**: opening a module wholesale
   brings the restated lemma's own library name into scope (fixture definitions
   carry a prime, e.g. `lift∼lower′`, to avoid the clash).  A searcher that
   retrieves and applies the library's original lemma has legitimately found the
   needle in the haystack; excluding the target from the candidate pool is the P2
   target-exclusion policy's job, not the fixture's.

### agda-stdlib-haystack tier: design constraints and gates

+  **Why it exists**: the P2 retrieval measurement (issue #123, numbers on
   #113) found that every frozen stdlib obligation *is* a stdlib lemma, so once
   the answer key is excluded from the candidate pool there is no needle left
   to find, and the term-mode ceiling binds the rest.  This tier is built to
   contain needles that are not the answer key.
+  **Reachable but not listed**: each fixture opens its haystack module with a
   narrow `using` list of one or two *decoys*, lemmas of the same family that
   cannot close the goal in term mode, so the fixed action space has a real
   pool to fail with while the needle is reachable only qualified
   (`open import M using (xs)` grants qualified access to all of `M`).  The
   gold therefore names the needle qualified, `Data.Nat.Properties.+-suc m m`,
   which is the same text the retrieval proposer's qualified rendering
   produces.
+  **Statements are specializations the library does not state**: a diagonal
   instance (`m + suc m ≡ suc (m + m)`), a hypothesis-consuming instance
   (`m ≤ n → m + m ≤ n + n`), or an instance whose implicit argument
   unification solves from the goal (`length (xs ++ xs) ≡ …`).  No statement
   is a stdlib lemma up to renaming, and none becomes one after `_<_` or an
   alias family unfolds, since the retrieval proposer's lane-form exclusion
   compares normalized printings.
+  **Golds stay within the committed candidate shapes**: one lemma applied to
   context names, with at most three visible binders in the lemma's
   lane-printed telescope (hypotheses count), because that is what the
   proposer's saturated form can emit and `fill_hole` refuses candidates that
   leave metas unsolved.  A gold outside those shapes would measure the shape
   vocabulary, not retrieval; `+-cancelˡ-≡` (four visible binders) and any
   two-lemma composite under `trans` are excluded on this rule, and a fixture
   binds every hypothesis in its clause rather than leaving it in the goal,
   since the proposer saturates every visible binder and a Π-typed goal could
   only be closed by a partial application.
+  **Three mechanical gates**, all re-runnable: the name and statement rules
   checked against the whole corpus by
   `scripts/python/corpus/check_haystack_exclusion.py` (run as
   `python3 scripts/python/corpus/check_haystack_exclusion.py --corpus
   data/corpora/agda-stdlib/v0/corpus.jsonl --index
   data/benchmarks/benchmark-index.jsonl`); the fixed-space sweep over the
   tier's ids, every status `exhausted` or `budget_exceeded`
   (`make proof-search-loop PROOF_SEARCH_PROPOSER=fixed
   PROOF_SEARCH_LOOP_IDS="--ids …"`); and the retrieval sweep with exclusion
   on, whose per-fixture ledger must report zero exclusions.  The measured
   numbers are posted on #129 and #113, and the per-row outcome (whether the
   token-overlap ranker surfaced the needle at all) is part of the record: a
   row the ranker cannot find is a valid instrument, not a defective fixture.
+  **Stratum tag**: every row carries `stratum:haystack` in `tags`, beside
   the agda-algebras strata; `source` stays `agda-stdlib`, so `EvalBenchmark`
   verifies the golds in the unchanged stdlib environment, and the loop
   harness reports the tier under `agda-stdlib/haystack` in `perStratum`,
   separately from the frozen tier's plain `agda-stdlib`.
+  **Frozen tier untouched**: the 22 obligations of `agda-stdlib-v0` are
   byte-identical to the P1 and P2 baselines' fixtures; this tier is a new
   directory, which is the only way the stdlib content grows.

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
├── agda-algebras-v0/
│   ├── obligations/                   # 21 modules, one {!!} hole each
│   └── gold/                          # solved twins
└── agda-stdlib-haystack-v0/
    ├── obligations/                   # 12 modules, one {!!} hole each
    └── gold/                          # solved twins, needle named qualified
```

Tier definitions and selection criteria live in `docs/benchmarks/taxonomy.md`;
the original design catalog lives in `docs/benchmarks/obligations.md` (its
`agda-algebras` sketches are superseded by the committed tier above).

## Fixture Convention

Each obligation is a self-contained Agda module:

+  It imports `AgdaDojang.Debug` and exactly the stdlib modules it needs.
+  It contains exactly **one** `{!!}` hole to be filled.
+  The module name matches the filename stem.
+  Any prerequisite lemmas are provided as explicit imports; the obligation may
   import lemmas, just not the definition it is asked to prove.  Wholesale-stratum
   agda-algebras fixtures qualify this deliberately: their module-wide `open`
   necessarily brings the restated lemma's own library name into scope (see the
   stratum semantics above); the gold still never *applies* it, and keeping the
   original reachable is the stratum's point, since retrieving it is a legitimate
   find and excluding it is the P2 target-exclusion policy's job.  Haystack-tier
   fixtures qualify it the other way round: their `using` lists hold only
   decoys, and the lemma the gold applies is deliberately *not* listed.

The corresponding gold file is identical except the hole is replaced with the
correct proof term.

## JSONL Index Schema (`benchmark-index.jsonl`)

Each line is a JSON object with the following fields:

| Field           | Type         | Description                                                    |
|-----------------|--------------|----------------------------------------------------------------|
| `id`            | string       | Unique obligation identifier (e.g., `stdlib-nat-plus-comm`)    |
| `source`        | string       | `"agda-stdlib"` or `"agda-algebras"`                           |
| `module`        | string       | Fully qualified source module (e.g., `Data.Nat.Properties`)    |
| `obligation`    | string       | Path to the obligation `.agda` file (relative to repo root)    |
| `gold`          | string       | Path to the gold solution `.agda` file (relative to repo root) |
| `goldTerm`      | string       | The proof term (or a short sketch) that fills the hole         |
| `hole`          | string       | Name of the definition with the hole                           |
| `type`          | string       | Pretty-printed type signature of the obligation                |
| `difficulty`    | string       | One of `"routine"`, `"compositional"`, `"non-obvious"`         |
| `domain`        | string       | Domain tag (e.g., `"arithmetic"`, `"list"`, `"logic"`)         |
| `proofStrategy` | string       | Primary proof technique (e.g., `"refl"`, `"induction"`)        |
| `tags`          | list[string] | Additional tags for slicing (e.g., `["standalone"]`, `["stratum:haystack"]`) |

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
`data/benchmarks/reports/gold-verification.json` (gitignored).  The report records
a wall-clock `timestamp` and per-obligation `elapsedMs`; the run is deterministic
modulo those fields, and `eval-benchmark-smoke` strips them before checking that
two runs match.

## The agda-algebras library

The library is Nix-managed and its flake pins `ualib/agda-algebras` at the
benchmark commit as the `agda-algebras-src` input and builds it once into a store
path with prebuilt `.agdai` interfaces, published to the project Cachix cache;
the flake's `nixConfig` registers that substituter, so CI and fresh machines
(after accepting the cache on first use) pull rather than build, and need no
checkout.  A developer working against a live checkout still overrides it the
old way:

```sh
AGDA_ALGEBRAS_ROOT=~/git/ualib/agda-algebras/master nix develop .#backend
```

`EvalBenchmark` passes `--library agda-algebras` for this tier's rows only, so the
frozen stdlib rows are verified in an unchanged environment.

## License

These fixtures are Agda source written for this repository, so the repository's
code license applies: [Apache-2.0](../../LICENSE).  They import the Agda standard
library, which carries its own (MIT) license and is not vendored here.  See the
"Licensing" section of the top-level `README.md` for the wider policy on data.
