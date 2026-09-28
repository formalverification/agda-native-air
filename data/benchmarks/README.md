# Benchmark Suite — `data/benchmarks/`

**Issue:** [M1-5] Curate baseline benchmark (#13)
**Agda:** 2.8.0  **standard-library:** 2.3  (both pinned by `flake.lock`)

The baseline benchmark is a set of Agda proof obligations with committed gold
solutions, used as the standard evaluation set for subsequent experiments.
Every gold solution type-checks under the pinned toolchain; type-checking is
the ground truth for a benchmark entry.

---

## Contents (v0)

The current suite has **69 obligations** from two libraries, spanning the three
difficulty tiers of `docs/benchmarks/taxonomy.md`: two tiers cut from the Agda
standard library, one mined from agda-algebras, and two hard tiers, one in each
library's vocabulary, posed so that no proof of their statements is on disk.

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

The two **hard tiers** (14 obligations, issue [#189]) are posed rather than
mined: statements in group theory and universal algebra written for them, each
under a module telescope and tagged `stratum:novel`.  The **`agda-stdlib-hard`
tier** (6 obligations) is posed in the standard library's
`Algebra.Bundles.Group` vocabulary and reports as `agda-stdlib/novel`; the
**`agda-algebras-hard` tier** (8 obligations) is posed in agda-algebras'
vocabulary and reports as `agda-algebras/novel`.  Each tier's README records
its rows' novelty checks, their golds, and the rows dropped from the eighteen
posed; what the two share is under "Hard tiers: conventions, golds, and the
novelty check" below.

| `agda-stdlib-hard` | Count | Examples                                                                |
|--------------------|-------|-------------------------------------------------------------------------|
| `compositional`    | 3     | `x ∙ x ≈ ε` for all `x` makes a group abelian, a surjective image of an abelian group is abelian |
| `non-obvious`      | 3     | `(x ∙ y)² ≈ x² ∙ y²` makes a group abelian, a unique involution is central |

| `agda-algebras-hard` | Count | Examples                                                              |
|----------------------|-------|-----------------------------------------------------------------------|
| `compositional`      | 4     | `H ∩ K` is normal in `H`, the third isomorphism theorem on cosets, `kercon (g ⊙ f) ≑ kercon f` |
| `non-obvious`        | 4     | `HK/K ≅ H/(H ∩ K)` on cosets, the kernel as a normal subgroup, a product of normal subgroups is their join |

Domains: group, algebra.

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
+  **Ranking ground truth** (recorded per obligation in `tags`, issue #19): every
   row carries one `restates:<prettyQname>` tag naming the library original it was
   mined from, by its corpus `prettyQname`, and zero or more `target:<prettyQname>`
   tags naming the library lemmas and constructors the gold term applies, product
   plumbing (`_,_`, `proj₁`, `proj₂`) and the record projections that only
   destructure a hypothesis or name a carrier (`Func.to`, `Setoid._≈_`, `𝔻[_]`)
   excepted.  The two are kept apart because they measure different regimes: the
   original's rank in the unexcluded pool is the haystack question (would the
   exclusion-off control commit it), while the targets' ranks in the excluded pool
   are the fair question (would ranking hand the searcher the lemmas the gold
   needs).  A `target:` may name a standard-library definition (`Function.Base.id`,
   `Relation.Binary.Bundles.Setoid.refl`), which the agda-algebras corpus cannot
   retrieve, or a constructor, which the retrieval proposer's `defKind` filter
   never proposes; the offline recall instrument (`make proof-search-recall`)
   reports both cases by name rather than counting them as ranking failures.

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

### Hard tiers: conventions, golds, and the novelty check

The two hard tiers of issue [#189], `agda-stdlib-hard-v0/` and
`agda-algebras-hard-v0/`, are one posed set split by the library whose
vocabulary a statement uses.  Each tier's README holds its rows, their novelty
verdicts, and the search record; what they share is here.

+  **Fixtures**.  One module per obligation, its name the file stem,
   `open import AgdaDojang.Debug` first, exactly one `{!!}`.  Each checks to
   exactly one `UnsolvedInteractionMetas` and no other error or warning under
   the judge's own `agda` invocation for its row's `source`, with and without
   `--safe`.  The obligations are the issue's files, byte for byte apart from
   the header's `File:` line.
+  **Module telescopes**.  Every statement is posed under `module _ … where`
   (`(G : Group c ℓ)` with `open Group G`, or agda-algebras' `(𝒢 : Group α ρ)`
   with its subgroups and their proofs), because that is the readable way to
   write them.  The definition's elaborated type includes the telescope, which
   is what the judge compares.  Goal-anchored `get_goal` and `type_of` answer
   inside it (checked on row 1: the lane's goal display, and `sq`, `assoc`,
   `inverseˡ` typed in the goal's scope); a `type_of` without a line sees the
   top-level scope, where the telescope's opens are not in scope, which is
   issue [#139].
+  **The scope a statement is posed in**.  Every row opens modules inside its
   telescope, and four define predicates before the hole.  The judge compares
   the definition's type by the names it mentions, so a file could keep that
   type and change what such a predicate means.  Since issue [#189] the judge
   freezes these lines as text, as it freezes the module line and the imports:
   every line outside the definition with the hole must survive, each
   declaration's lines as one run that nothing continues, in the obligation's
   order, while lines may be added between declarations (`Gates.scope` in
   `strux-driver/.../agentbench/Judge.scala`, pinned in `JudgeSpec`).  The
   mined tiers' obligations have no such lines, so their verdicts cannot move.
+  **Index rows**.  `source` is the library whose vocabulary the statement
   uses, which also chooses the corpus a subject is given, and the tag
   `stratum:novel` makes every report count the tiers as `agda-stdlib/novel`
   and `agda-algebras/novel`.  No row carries a `restates:` or `target:` tag,
   since no row has an original, and no definition in either corpus or either
   library's sources carries any of the fourteen hole names, so the
   restatement rule cannot fire.  `module` names the library module the
   fixture's `Source:` line names first (nothing is proved there); `goldTerm`
   is the fixture's `Strategy:` line, a sketch; `type` is the signature as the
   fixture writes it, as on every other tier, because Agda prints these types
   with every definition unfolded (past a thousand characters on rows 10 to
   18).

**Golds**.  A wanted gold's twin under `gold/` is the obligation with the hole
still in it and a `-- GOLD WANTED` line under the header, so it checks exactly
as the obligation does.  A finished gold replaces the hole and changes no other
line of the obligation: the proof's imports go in a `where` block under the
clause, not in the telescope.  It type-checks under the judge's invocation with
`--safe`, and its statement is the obligation's: the holed definition's
elaborated type, from `agda-json` on the gold and on a copy of the obligation
whose hole is postulated, is the same with binder names removed.  While any
gold is wanted, the following hold:

+  the CI slice `make eval-benchmark-smoke` selects rows by a fixed id list
   (`BENCHMARK_SMOKE_IDS` in the `Makefile`) that names none of these rows, so
   it stays green;
+  the full `make eval-benchmark`, which is not a CI lane, reports each wanted
   gold as failing;
+  the judge cannot judge a row whose gold is wanted, since its statement gate
   reads the statement from the gold's elaborated type and `agda-json` cannot
   extract a holed file: it stops on an internal error of Agda's
   (`src/full/Agda/TypeChecking/Rules/LHS.hs:751`) on 68 of the 69 committed
   obligations, every one whose hole stays open (the exception is
   `Unit-trivial`, whose hole of type `⊤` Agda fills by eta).  A row without a
   gold waits for one.

Since 2026-09-27 no gold is wanted on either tier, and the full `make
eval-benchmark` passes all 69 rows.

**Alternative proofs**.  A gold file may keep further proofs of its statement
after the gold itself, each a definition with the same signature and a name
that says how it proves it (`squares-commute-by-assoc`).  Only two things read
a gold file: `make eval-benchmark` type-checks all of it, so an alternative is
verified with the gold and cannot rot, and the judge reads only the definition
the index names as `hole`, so an alternative changes no verdict.  Subjects
never see a gold.

**The novelty check**.  A statement belongs in a hard tier only if no proof of
it is on disk: in the agda-algebras library (the flake's store copy, at the
commit of the corpus), in the standard library 2.3, or in either corpus.  Each
row was checked four ways, as follows:

+  `search_by_type` through the agda-mcp server over the agda-algebras corpus
   v0.1 (SHA-256 `af864432`), and for the standard-library rows also over the
   standard-library corpus v0 (`14e0d47e`), with a limit of 2,000.  The tool
   is a case-insensitive substring match over each definition's printed type,
   which is fully qualified and broken across lines, so a whole statement
   never matches; each row records its statement's most distinctive fragments
   and its conclusion's head, in the corpus's own spelling (`Group-Op.∙`,
   `Coset.∼`, `Algebra.Definitions.Commutative`);
+  `search_by_name` with the natural names, the same way;
+  a conjunctive search over the same corpus rows, every fragment in one row's
   type, which the server's tools cannot do;
+  `grep` over both libraries' sources for the conclusion's head symbols
   together: the files containing all of them, then the lines.

The verdicts are defined as follows:

+  **absent**: nothing on disk proves the statement; the nearest lemma is a
   different statement;
+  **on disk, other vocabulary**: agda-algebras proves the statement's content
   in its own group vocabulary, as lemmas a subject can read and translate;
+  **generalization**: a theorem on disk implies the statement;
+  **partly on disk**: some conjuncts are one or two library lemmas away, and
   the rest are absent.

Across both tiers, the check found ten rows absent (1, 2, 3, 4, 10, 11, 12,
15, 17, 18), three on disk in agda-algebras' vocabulary (5, 8, 9), one a
generalization's instance (7), and four partly on disk (6, 13, 14, 16).  The
three on disk were dropped on 2026-09-27, since a subject with a shell can
read their proofs, and so was row 15, which is not provable as posed; fourteen
rows remain.  Each tier's README says why under "Dropped rows" and keeps the
dropped rows' searches as the record of the check.

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
├── agda-stdlib-haystack-v0/
│   ├── obligations/                   # 12 modules, one {!!} hole each
│   └── gold/                          # solved twins, needle named qualified
├── agda-stdlib-hard-v0/
│   ├── README.md                      # the rows, golds, dropped rows, novelty check
│   ├── obligations/                   # 6 modules, one {!!} hole each
│   └── gold/                          # solved twins
└── agda-algebras-hard-v0/
    ├── README.md                      # the rows, golds, dropped rows, novelty check
    ├── obligations/                   # 8 modules, one {!!} hole each
    └── gold/                          # solved twins
```

Tier definitions and selection criteria live in `docs/benchmarks/taxonomy.md`;
the original design catalog lives in `docs/benchmarks/obligations.md` (its
`agda-algebras` sketches are superseded by the committed tier above).

## Fixture Convention

Each obligation is a self-contained Agda module:

+  It imports `AgdaDojang.Debug` and exactly the stdlib modules it needs.
+  It imports them the way a person writing Agda would, not the way a byte
   budget would: `Relation.Binary.PropositionalEquality`, not its cheaper
   `.Core`.  That costs interface bytes, and the cost is measured and
   deliberate: see [`docs/import-closure.md`](../../docs/import-closure.md),
   which records what a fixture's closure costs, why the suite's imports are
   left idiomatic, and what an edit to one would break.  A consumer with a
   byte budget, such as a browser-hosted checker, carries its own trimmed
   copy of the obligation rather than reshaping the corpus.
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

[#139]: https://github.com/formalverification/agda-native-air/issues/139
[#189]: https://github.com/formalverification/agda-native-air/issues/189
