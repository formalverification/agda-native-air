<!-- File: docs/corpora/agda-algebras-v0.1.md -->

# Dataset card — agda-algebras corpus v0.1

An agda-strux JSONL corpus of the whole of [`ualib/agda-algebras`][agda-algebras]: one row per definition, carrying the definition's normalized name, its pretty-printed type, a structural encoding of that type, its dependency tokens, and its proof term where it has one.

v0.1 is a re-cut of [v0](agda-algebras-v0.md) at a newer library commit; the schema, the pipeline, and the reading of every statistic are unchanged.  The re-pin exists for one reason: the benchmark tier of issue #127 is mined from this corpus, and its provenance commitment is that the benchmark's library commit and the corpus's library commit are the same, recorded in `data/benchmarks/README.md` and pinned as the `agda-algebras-src` flake input.  The library moved between the v0 cut and the benchmark authoring (a docstring pass, then the first FLRP simplicity work), so the corpus moved with it.

+  **Corpus**: `corpus.jsonl` — 12,379 rows, 205,215,424 bytes; `corpus.jsonl.gz` — 5,365,903 bytes.
+  **Row schema**: agda-strux Full JSONL, [`docs/representation.md`](../representation.md) §3; `typeAstVersion` `0.3-v0` on every row.
+  **Companion artifacts**: `coverage.json` (per-module outcomes), `provenance.json` (commits, pins, digests), `stats.json` and `stats.md` (the statistics quoted below).

## Provenance

Everything in this section is recorded machine-readably in `provenance.json`; the values below are that record in prose.

| What | Value |
|---|---|
| Source library | `ualib/agda-algebras`, `git@github.com:ualib/agda-algebras.git` |
| Library commit | `a5f9acb5f869bf675544705ab29c0cb6e4ee2531` (2026-08-31), working tree clean |
| Source tree read | `src/` (the library's `include:` directory) |
| Producer | `formalverification/agda-native-air` at `23d6e025a789bce2a85352dd9d0ba134d32c3845` (main), working tree clean; `struxdriver.extract.AgdaJsonlDriver` → `agda-strux`'s `agda-json` |
| Agda | 2.8.0 |
| Agda standard library | 2.3, `/nix/store/pkks1pz1n2bci0pva1sxbydnc4xyliid-standard-library-2.3` |
| GHC | 9.10.3 |
| Toolchain pin | `flake.lock`: `nixpkgs-agda` at `9dcb002ca1690658be4a04645215baea8b95f31d`, `nixpkgs` at `b6018f87da91d19d0ab4cf979885689b469cdd41` |
| Extraction run | 394 modules, `--runner spark` (no fallback), parallelism 8, no resume; 5 m 34 s wall, 7,037 s of module time |
| Corpus SHA-256 | `5fa932326467e1c73ebed9e3bdf1ba264b8f3637ed462e94054d34ac07359c1f` |
| Gzip SHA-256 | `1bffda68dce92326725876c7f136b10677ecd42d37cfa5f0774d7d7f07f7cde1` |

The digests were confirmed byte-identical across two independent assembly runs over the same extraction.  The v0 card's notes on *when* values are recorded apply verbatim: the library commit, its dirty state, and the runner come from the extraction manifest; `commitMatchesCheckout` was true at packaging; the toolchain block is sampled at packaging time.

## Coverage

Every one of the library's 394 source files is a module, all 394 were extracted, and all 394 succeeded.  Nothing is excluded.

| Quantity | Value |
|---|---|
| Source files under `src/` | 394 |
| Modules requested / attempted / succeeded | 394 / 394 / 394 |
| Failed / never attempted | 0 / 0 |
| Modules contributing 0 rows | 62 |

The 62 zero-row modules are barrels (`Classical`, `Overture`, `Everything`, `EverythingLegacy` and kin): `import` lines only, so nothing of their own to extract.  `coverage.json` records all 394 outcomes individually.

## Statistics

Full tables, including the twenty most-depended-upon definitions and the module-level import graph, are in `stats.md`; the same numbers are in `stats.json`.

| Quantity | Value |
|---|---|
| Definitions (rows) | 12,379 |
| Distinct `prettyQname` | 11,182 |
| Distinct `prettyModule` | 745 |
| Top-level namespaces | 8 |
| Definitions carrying a proof term | 11,300 |

**By kind**.  11,433 functions, 641 constructors, 176 records, 126 data types, 3 other.

**By namespace**.  `FLRP` 4,027; `Classical` 2,616; `Setoid` 2,528; `Legacy` 1,856; `Examples` 1,041; `Overture` 232; `Order` 54; `Exercises` 25.  Relative to v0 the growth is concentrated in `FLRP` (+427), `Classical` (+200), and `Examples` (+52) — the library's docstring-and-FLRP week.

**Sizes**.  Types have a median length of 423 characters and a p99 of 3,197 (max 87,123).  Proof terms have a median of 122 characters and a p99 of 31,539 — with a maximum of 11,557,651, so the certificate tail got longer still (see Known gaps).  A definition takes a median of 7 top-level Π binders before its codomain, and at most 40.

**Dependency shape**.  At definition level the graph is keyed by `prettyQname`: 11,182 nodes, into which the 12,379 rows collapse (1,197 rows share a name with another and are merged).  50,845 of the dependency tokens name a definition in this corpus; the other 75,377 occurrences resolve to nothing here and are reported as unresolved tokens, of which 39,959 at least have the shape of a qualified name — a lower bound on the real outward edges, dominated by `Agda.Primitive.Level` (6,703) and the standard library's `Data.Fin.Base.Fin` (2,932).  The most depended-upon definition is `Overture.Signatures.Signature` with 3,674 references.

At module level, Agda's dependency graph over 655 modules (local plus external) is acyclic, with 1,281 edges and a longest chain of 76.  The v0 caveat stands: that DOT is a load-order graph, not the import relation; use the definition-level graph for anything that has to be complete.

## Intended uses

The same four as v0 — retrieval for proof assistance, training and evaluation data, measuring a library, schema regression — plus the one this cut exists for:

+  **Benchmark curation** (issue #127).  The agda-algebras tier of `data/benchmarks/` is mined from this corpus's rows (`scripts/python/corpus/mine_benchmark_candidates.py`) and its fixtures are cut from the same library commit, so "the benchmark's library" and "the corpus's library" cannot drift apart silently.

It is **not** a benchmark: no held-out split, no difficulty labels; see `data/benchmarks/`.

## Known gaps

All seven v0 gaps carry over unchanged in kind; the numbers that moved:

+  **1,197 rows are shadowed under `prettyQname`** (684 qualified names occur more than once; worst `Classical.Structures.Ring.absurdlambda`, 28 times).  A consumer keyed by `prettyQname` indexes 11,182 of the 12,379 rows.  Use `qname` when identity matters.  Tracked by issue #53.
+  **Ten rows are over a megabyte each**, and the largest ten are 22.7 % of the corpus by bytes — machine-generated certificate proofs in `FLRP`; the biggest is now 11.5 MB.  Filter on `astSize` or body length before budgeting per row.
+  Dependency tokens remain heuristic; the module DOT remains load-order; types remain internal-printer strings; `--safe`/`--cubical-compatible` regimes remain unrecorded; one library, one commit.

## License and attribution

Identical to v0: the corpus and its stats inherit the library's **Apache-2.0** (Copyright 2025-2026 William DeMeo and Contributors); this card is **CC-BY-4.0**.  Cite:

> The Agda Universal Algebra Library (`ualib/agda-algebras`), commit `a5f9acb5f869bf675544705ab29c0cb6e4ee2531`, Apache-2.0.

## Reproducing it

From an `agda-native-air` checkout at the producer commit, outside any Nix shell, with `~/git/ualib/agda-algebras/master` checked out at the library commit above:

```sh
make extract-lib-nix AGDA_ALGEBRAS_ROOT=~/git/ualib/agda-algebras/master PAR=8 RESUME=0
make corpus-nix CORPUS_VERSION=v0.1
```

Artifacts land under `data/corpora/agda-algebras/v0.1/`.  Byte-identical output is expected for the same library commit and toolchain (sorted concatenation, gzip with no filename and `mtime=0`); compare against the digests above.  Expect about six minutes of wall time with warm `.agdai` interfaces.

## Using it with agda-mcp

As for v0: `gunzip -k corpus.jsonl.gz && agda-mcp --corpus corpus.jsonl [flags]` registers `search_by_name`, `search_by_type`, and `get_dependencies`; `make corpus-mcp-smoke CORPUS_VERSION=v0.1` drives them over the real JSON-RPC transport.

[agda-algebras]: https://github.com/ualib/agda-algebras
