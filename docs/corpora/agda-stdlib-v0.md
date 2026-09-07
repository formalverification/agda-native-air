<!-- File: docs/corpora/agda-stdlib-v0.md -->

# Dataset card: agda-stdlib corpus v0

An agda-strux JSONL corpus of the [Agda standard library][agda-stdlib] at version 2.3: one row per definition, carrying the definition's normalized name, its pretty-printed type, a structural encoding of that type, its dependency tokens, and its proof term where it has one.

This corpus exists first for proof search: it is the retrieval substrate of the P2 proposer (issue #123), which turns `search_by_name` / `search_by_type` hits into candidate proof steps for the M1-5 benchmark.  Every [M1-5] obligation is itself a standard-library lemma, so the corpus contains the benchmark's answers verbatim; which is why the search's target-exclusion policy exists and why any use of this corpus against that benchmark must state its exclusion configuration.

+  **Corpus**: `corpus.jsonl` is 55,576 rows, 462,884,404 bytes; `corpus.jsonl.gz` is 13,219,208 bytes.
+  **Row schema**: agda-strux Full JSONL, [`docs/representation.md`](../representation.md) §3; `typeAstVersion` `0.3-v0` on every row.
+  **Companion artifacts**: `coverage.json` (per-module outcomes), `provenance.json` (pins, digests), `stats.json` and `stats.md` (the statistics quoted below).

## Provenance

Everything in this section is recorded machine-readably in `provenance.json`; the values below are that record in prose.

| What | Value |
|---|---|
| Source library | `agda/agda-stdlib` version 2.3 |
| Source tree read | `/nix/store/pkks1pz1n2bci0pva1sxbydnc4xyliid-standard-library-2.3/src` |
| Upstream commit | tag `v2.3` = `8326c7475af1fa456ca04a0203c168d5d7ff842b` |
| Producer | `formalverification/agda-native-air`, `struxdriver.extract.AgdaJsonlDriver` → `agda-strux`'s `agda-json` |
| Agda | 2.8.0 |
| GHC | 9.10.3 |
| Toolchain pin | `flake.lock`: `nixpkgs-agda` at `9dcb002ca1690658be4a04645215baea8b95f31d`, `nixpkgs` at `b6018f87da91d19d0ab4cf979885689b469cdd41` |
| Extraction run | 1,153 modules, `--runner spark` on `local[4]`, parallelism 20, no resume; 5 m 12 s wall, 4,586 s of module time |
| Corpus SHA-256 | `14e0d47e8b904e9bd7822df6c0a33d41820971272079df69fbb66a79311a846d` |
| Gzip SHA-256 | `83e8beb0cfcf70a6a28b8d9ea4f4eb7c67c0f31607440e9337ccee5572ab03c1` |

The source is not a git checkout but the **Nix store derivation the project's own toolchain resolves**, which is a stronger pin than a commit hash: the corpus provably describes the exact bytes the benchmark fixtures typecheck against, interfaces included.  It is also why `provenance.json`'s `source.commit` reads `unknown` (a store path has no git identity) and why this card supplies the upstream mapping instead: nixpkgs' `agdaPackages.standard-library` 2.3 builds the `v2.3` tag named above.  The store path being read-only is not an obstacle but the reason the run is fast: the derivation ships prebuilt `.agdai` interfaces for every module, so extraction reads them instead of typechecking the library from cold.

## Coverage

| Quantity | Value |
|---|---|
| Source files under `src/` | 1,153 |
| Modules requested | 1,153 |
| Attempted | 1,153 |
| Succeeded | 1,149 |
| Failed | 4 |
| Never attempted | 0 |
| Modules contributing 0 rows | 87 |

The 87 zero-row modules are barrels and re-export shells (`Data.Unit.Base` is the canonical example: `⊤` and `tt` live in `Agda.Builtin.Unit`, and the module's own contribution is re-exports), counted as successes because Agda checked them and the backend correctly found nothing of their own to extract.

The **four failures share one cause**: an Agda 2.8.0 internal error (`__IMPOSSIBLE_VERBOSE__` at `src/full/Agda/TypeChecking/Monad/Context.hs:542`) raised while agda-strux traverses the module; the library itself typechecks these modules fine.  The four are `Data.List.Relation.Unary.All`, `Data.List.Relation.Unary.Sufficient`, `Data.Vec.Relation.Unary.All`, and `Tactic.RingSolver.Core.Polynomial.Base`.  Each failure's log opens with a `REPRO:` line reproducing it in one command; the extractor bug is tracked as [#128], not something this corpus can paper over.  None of the four is in the M1-5 benchmark's import surface, so the P2 measurement is unaffected; a consumer needing `All` should know it is absent.

`coverage.json` records all 1,153 outcomes individually (rows, seconds, exit code, and any validation errors) so this table can be checked rather than taken on trust.

## Statistics

Full tables, including the twenty most-depended-upon definitions and the module-level import graph, are in `stats.md`; the same numbers are in `stats.json`.

| Quantity | Value |
|---|---|
| Definitions (rows) | 55,576 |
| Distinct `prettyQname` | 51,805 |
| Distinct `prettyModule` | 3,569 |
| Top-level namespaces | 18 |
| Definitions carrying a proof term | 49,951 |

**By kind**.  50,501 functions (where theorems live), 3,053 constructors, 1,293 records, 528 data types, 182 postulates, 19 other.

**By namespace**.  `Data` 26,178; `Algebra` 14,635; `Relation` 4,901; `Function` 3,159; `Codata` 1,577; `Effect` 1,494; the remaining twelve namespaces (`Tactic`, `Reflection`, `Text`, `System`, `Induction`, `IO`, …) together 3,632.

**Sizes**.  Types have a median length of 269 characters and a p99 of 2,376 (max 23,230); proof terms a median of 156 and a max of 727,379.  A definition takes a median of 5 top-level Π binders and at most 37.

**Dependency shape**.  At definition level: 51,805 nodes (3,771 rows share a name and are merged), 170,458 in-corpus edges; the most depended-upon definitions are the algebraic plumbing: `Algebra.Core.Op₂` (13,482), `Relation.Binary.Core.Rel` (8,116), `Algebra.Core.Op₁` (4,463).  247,905 dependency-token occurrences resolve to nothing in the corpus; the qualified-looking 123,540 of them are dominated by `Agda.Primitive.Level` (34,325) and `Agda.Primitive.Set` (21,193); see Known gaps for why the builtins are outside.  At module level Agda's dependency graph spans 1,182 nodes (the 1,149 extracted modules plus the builtin modules and the synthetic root), acyclic, longest chain 48, read with the load-order caveat in Known gaps.

## Intended uses

+  **Retrieval for proof search** (the reason it exists).  Backing `agda-mcp`'s `search_by_name` / `search_by_type` / `get_dependencies` for the #123 retrieval proposer, whose scope, exclusion, and ranking policies are described in `strux-driver/src/main/scala/struxdriver/search/Retrieve.scala`.
+  **Retrieval and premise-selection data**.  49,951 rows carry a proof term and qualify for the `proof-completion.v0` derived view (representation.md §7.2.4).
+  **Measuring the library**.  Interface width, dependency fan-in, and namespace composition of the standard library at a fixed version.
+  **Schema regression**.  A fixed, digest-identified corpus against which extractor changes can be diffed.

It is **not** a benchmark: no held-out split, no difficulty labels.  For evaluation targets see `data/benchmarks/` and [`docs/benchmarks/taxonomy.md`](../benchmarks/taxonomy.md), and note again that this corpus CONTAINS that benchmark's gold lemmas.

## Known gaps

+  **Four modules are absent**: the extractor-crash quartet named under Coverage.  A consumer resolving `Data.List.Relation.Unary.All.map` gets nothing.
+  **The builtins are outside the corpus**.  `Agda.Builtin.*` and `Agda.Primitive` belong to Agda, not to `src/`, so every reference to `ℕ`'s constructors, `_≡_`, `Level`, or `Set` is an unresolved token, and re-exports of builtin definitions (`Data.Nat.Base._+_`) appear only under their re-exporting rows.  The dependency graph is a library-internal graph.
+  **Types are printed as declared, alias form included**.  `+-comm`'s `type` is `Algebra.Definitions.Commutative Agda.Builtin.Equality._≡_ Agda.Builtin.Nat._+_`, not `(m n : ℕ) → m + n ≡ n + m`; the standard library states most equational lemmas through `Algebra.Definitions` aliases.  String search over types therefore misses expanded forms, and arity cannot be read off the string; a consumer needing the expanded pi type must ask Agda (the interaction lane's `type_of` expands aliases, which is exactly what the P2 proposer does for binder counts).
+  **3,771 rows are shadowed under `prettyQname`** (normalization collapses anonymous module segments).  A consumer keyed on `prettyQname` (`agda-mcp` keeps the last occurrence) indexes 51,805 of the 55,576 rows; use `qname` when identity matters.
+  **Dependency tokens are heuristic**: tokenized from the printed type, not name-resolved; bound variables (`ℓ₁`, `xs`) and truncations (`Agda.Builtin.Equality._`) appear alongside real names.  A recall-oriented candidate set, not resolved edges.
+  **The module import graph is a load-order graph**, from `--dependency-graph`: an edge records a source read, so a module imported by thirty-five files may show a fraction of that in-degree.  Node count, acyclicity, and the longest chain are trustworthy; in-degrees describe one traversal.
+  **`--safe` / `--cubical-compatible` regimes are not recorded** per row.
+  **One library, one version.**  Nothing here generalizes to another library or another stdlib release.

## License and attribution

The corpus is derived from the Agda standard library's `src/`, distributed under the library's MIT-style licence (Copyright 2007–2025 Nils Anders Danielsson, Ulf Norell, and the Agda Team; see the `LICENCE` at the tag).  The rows are distributed under the same terms.  Cite the library as the source of the mathematics:

> The Agda standard library (`agda/agda-stdlib`), version 2.3, tag `v2.3` = `8326c7475af1fa456ca04a0203c168d5d7ff842b`, MIT-style licence.

**This card** is part of `agda-native-air`'s documentation, licensed **CC-BY-4.0** (see `LICENSE-docs`).  `stats.json` and `stats.md` are computed from the corpus's rows and travel with the corpus under its terms, beside it in `data/corpora/agda-stdlib/v0/`.

## Reproducing it

From an `agda-native-air` checkout, outside any Nix shell:

```sh
make corpus-stdlib-nix
```

One target does the whole lane: it discovers the store stdlib from the shellHook-written libraries file, generates the module list from `src/`, extracts every module through `agda-json`, produces the dependency DOT from a scratch Everything module (`scripts/corpus-stdlib-depgraph.sh`, the store being read-only is why the algebras lane's metadata scanner cannot), and packages corpus, coverage, provenance, and stats under `data/corpora/agda-stdlib/v0/`.

Expect five to six minutes of wall time; the store's prebuilt interfaces make the run warm by construction.  Determinism is verified, not assumed: two independent full extraction-plus-assembly runs produced byte-identical `corpus.jsonl` and `corpus.jsonl.gz` (the digests above).

## Using it with agda-mcp

```sh
agda-mcp --corpus data/corpora/agda-stdlib/v0/corpus.jsonl [other flags]
```

Loading registers `search_by_name`, `search_by_type`, and `get_dependencies` alongside the server's other tools.  Measured on this corpus: the load takes about 3.6 seconds to a 727 MB resident footprint (the index keeps only the searched fields; `typeAst` and bodies are read and dropped).  To check the corpus end to end through the real JSON-RPC transport:

```sh
make corpus-mcp-smoke LIB_NAME=agda-stdlib CORPUS_SMOKE_NAME_PATTERN=+-comm
```

[#128]: https://github.com/formalverification/agda-native-air/issues/128
[agda-stdlib]: https://github.com/agda/agda-stdlib
