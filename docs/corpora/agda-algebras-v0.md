<!-- File: docs/corpora/agda-algebras-v0.md -->

# Dataset card — agda-algebras corpus v0

An agda-strux JSONL corpus of the whole of [`ualib/agda-algebras`][agda-algebras]: one row per definition, carrying the definition's normalized name, its pretty-printed type, a structural encoding of that type, its dependency tokens, and its proof term where it has one.

The corpus answers questions about a library at library scale without a checkout and without Agda.  It is the counterpart to the live queries of issue #75, which answer against a working tree; this answers against a fixed commit, which is what makes it citable.

+  **Corpus**: `corpus.jsonl` — 11,666 rows, 184,904,547 bytes; `corpus.jsonl.gz` — 4,961,567 bytes.
+  **Row schema**: agda-strux Full JSONL, [`docs/representation.md`](../representation.md) §3; `typeAstVersion` `0.3-v0` on every row.
+  **Companion artifacts**: `coverage.json` (per-module outcomes), `provenance.json` (commits, pins, digests), `stats.json` and `stats.md` (the statistics quoted below).

## Provenance

Everything in this section is recorded machine-readably in `provenance.json`; the values below are that record in prose.

| What | Value |
|---|---|
| Source library | `ualib/agda-algebras`, `git@github.com:ualib/agda-algebras.git` |
| Library commit | `ecc158a3730259b75d2ace4f5e30764e1c514380` (2026-08-17), working tree clean |
| Source tree read | `src/` (the library's `include:` directory) |
| Producer | `formalverification/agda-native-air`, `struxdriver.extract.AgdaJsonlDriver` → `agda-strux`'s `agda-json` |
| Agda | 2.8.0 |
| Agda standard library | 2.3, `/nix/store/pkks1pz1n2bci0pva1sxbydnc4xyliid-standard-library-2.3` |
| GHC | 9.10.3 |
| Toolchain pin | `flake.lock`: `nixpkgs-agda` at `9dcb002ca1690658be4a04645215baea8b95f31d`, `nixpkgs` at `b6018f87da91d19d0ab4cf979885689b469cdd41` |
| Extraction run | 377 modules, `--runner spark` on `local[4]` (no fallback), parallelism 8, no resume; 5 m 39 s wall, 7,348 s of module time |
| Corpus SHA-256 | `acdfaa5766ed83c5055b5f9fee8a9eaeeeadbe4e98630d916352a7851845ed54` |
| Gzip SHA-256 | `88bfd57097d98b3cc455b63899f191b312f3acc40f277cfe93fb40d5fac23238` |

The Nix store path of the standard library is itself the version pin: it names the exact derivation Agda typechecked against.

Two things about *when* these were recorded, because a corpus is packaged after it is extracted and the difference matters.  The library commit, its dirty state, the module list, and the runner that actually ran are recorded by the extraction itself and read back from its manifest; `provenance.json` also reports what the checkout says at packaging time (`commitAtPackagingTime`, `commitMatchesCheckout`), so a library that moved in between is visible rather than silently relabelled.  The toolchain block is sampled when packaging runs and is marked `sampledAt: packaging-time`: the pinned Agda is linked into `agda-json`, so an `agda --version` cannot be an authoritative record of what typechecked the library — the `agda-json` path in the manifest is.

## Coverage

Every one of the library's 377 source files is a module, all 377 were extracted, and all 377 succeeded.  Nothing is excluded.

| Quantity | Value |
|---|---|
| Source files under `src/` | 377 |
| Modules requested | 377 |
| Attempted | 377 |
| Succeeded | 377 |
| Failed | 0 |
| Never attempted | 0 |
| Modules contributing 0 rows | 61 |

The 61 zero-row modules are barrels: `Classical`, `Classical.Bundles`, `Overture`, `Everything`, `EverythingLegacy` and their kin consist of `import` lines, so there is nothing of their own to extract.  They are counted as successes because they are: Agda typechecked them and the backend correctly found no definitions belonging to them.

Two of those barrels reach the corpus only because the module scanner was fixed while this corpus was being prepared, and both are worth naming since an earlier draft of this card explained them away as non-modules:

+  `src/Everything.agda` was dropped by a scanner that discarded the name `Everything` — the name its own synthetic root module once had.  The root was renamed `MetadataEverything` and the discard stayed behind, excluding a real module.
+  `src/agda-algebras.lagda.md` was dropped by a module-name validator whose segment pattern omitted `-`.  A hyphen is an ordinary character in an Agda identifier, the file declares `module agda-algebras where` at line 84, and `Everything` imports it — so it is a module like any other.

Neither adds a row, both being barrels, so the corpus bytes are the same either way; what changed is that the coverage claim no longer needs an excuse.

`coverage.json` records all 377 outcomes individually — rows, seconds, exit code, and any validation errors, with artifact paths relative to the run's out-dir — so this table can be checked rather than taken on trust.

## Statistics

Full tables, including the twenty most-depended-upon definitions and the module-level import graph, are in `stats.md`; the same numbers are in `stats.json`.

| Quantity | Value |
|---|---|
| Definitions (rows) | 11,666 |
| Distinct `prettyQname` | 10,520 |
| Distinct `prettyModule` | 702 |
| Top-level namespaces | 8 |
| Definitions carrying a proof term | 10,629 |

`prettyModule` counts (702) exceed source modules (377) because nested and parameterized submodules get their own normalized module name.

**By kind**.  10,748 functions (which is where theorems live — a proved statement is a function into its statement's type), 625 constructors, 165 records, 125 data types, 3 other.

**By namespace**.  `FLRP` 3,600; `Setoid` 2,510; `Classical` 2,416; `Legacy` 1,856; `Examples` 989; `Overture` 229; `Order` 41; `Exercises` 25.  The library's `Legacy/` subtree is included: it still typechecks, and a corpus that quietly dropped it would misreport what the library contains.

**Sizes**.  Types have a median length of 411 characters and a p99 of 3,294 (max 87,235).  Proof terms have a median of 120 characters and a p99 of 30,502 — with a maximum of 8,386,647, so the tail is very long indeed (see Known gaps).  A definition takes a median of 7 top-level Π binders before its codomain, and at most 40; universe-polymorphic algebra spends a lot of its interface on levels and setoid parameters.

**Dependency shape**.  At definition level the graph is keyed by `prettyQname`: 10,520 nodes, into which the 11,666 rows collapse (1,146 rows share a name with another and are merged, their token sets unioned).  47,202 of the dependency tokens name a definition in this corpus.  The other 69,651 occurrences resolve to nothing here, and are reported as **unresolved tokens** rather than as edges leaving the corpus — `dependencies` is heuristic, and 32,367 of those occurrences are bound variables or truncations that could not name anything anywhere (`ρᵃ`, `Agda.Primitive.`).  The 37,284 that at least have the shape of a qualified name are a lower bound on the real outward edges, and they are dominated by `Agda.Primitive.Level` (6,425), `Agda.Primitive.Set` (2,889), and the standard library's `Data.Fin.Base.Fin` (2,722) and `Agda.Builtin.Nat.Nat` (2,688).  However that lower bound is read, a library corpus is not a closed graph.  A node depends on a median of 10 tokens and at most 56; the most depended-upon definition is `Overture.Signatures.Signature` with 3,542 references.

At module level, Agda's dependency graph over the 377 local plus 254 external modules is acyclic, with 1,237 edges and a longest chain of 73.  Read those two numbers with the caveat in Known gaps: they describe the load order of one run, not the full import relation.

## Intended uses

+  **Retrieval for proof assistance**.  Backing `agda-mcp`'s `search_by_name`, `search_by_type`, and `get_dependencies` (M1-3), and the indices of M2-2 / M2-3 (issues #16 and #17).
+  **Training and evaluation data**.  The `proof-completion.v0` derived view (representation.md §7.2.4) is built from rows with `hasBody=true`; 10,629 of these rows qualify.
+  **Measuring a library**.  Interface width, dependency fan-in, and namespace composition, as a description of a real formalization rather than of a benchmark slice.
+  **Schema regression**.  A fixed, digest-identified corpus against which a change to the extractor's output can be diffed.

It is **not** a benchmark: it contains no held-out split and no difficulty labels.  For evaluation targets see `data/benchmarks/` and [`docs/benchmarks/taxonomy.md`](../benchmarks/taxonomy.md).

## Known gaps

These are properties of the corpus as shipped, not to-do items disguised as caveats.  Where an issue tracks the fix, it is named.

+  **1,146 rows are shadowed under `prettyQname`**.  655 qualified names occur more than once (worst: `Classical.Structures.Ring.absurdlambda`, 28 times), because normalization drops anonymous module segments and distinct definitions collapse onto one name.  A consumer keyed by `prettyQname` — `agda-mcp` keeps the last occurrence — therefore indexes 10,520 of the 11,666 rows.  Every row is still in the file; use `qname` when identity matters.  Tracked by issue #53.
+  **Dependency tokens are heuristic**.  `dependencies` is extracted from the pretty-printed type by tokenization, not by name resolution.  Most tokens are fully-qualified names, but the list also contains bound variables (`ρᵃ`, `lc`), truncations ending in a dot (`Agda.Primitive.`, `Relation.Binary.Bundles.Setoid.`), and record-field projections.  Treat the field as a recall-oriented candidate set, not as resolved edges.  representation.md §4.2 and §6.4 state the same limitation.
+  **Nine rows are over a megabyte each**, and the largest ten are 19% of the corpus by bytes.  They are machine-generated certificate proofs in `FLRP.Certificates.SmallLatticeReps` and `FLRP.Parachute` — the biggest is `FLRP.Certificates.SmallLatticeReps.SLR13.prinTrᵛ` at 8.5 MB.  A consumer that budgets per row rather than per corpus should filter on `astSize` or body length first.
+  **The module import graph is a load-order graph, not the import relation**.  `stats.json`'s `moduleGraph` comes from Agda's `--dependency-graph`, which records an edge when an import causes a *source read* — so the first module to import `Overture.Signatures` gets an edge and the other 34 that import it do not.  Measured: 35 files in `src/` import that module; the DOT records 9 in-edges.  Node count, acyclicity, and the longest chain are trustworthy; in-degree, out-degree, and "most imported" describe one traversal.  Use the definition-level graph, which is computed from the rows themselves, for anything that has to be complete.
+  **No `ports`, `refsFromBody`, or `wires`**.  Those fields are planned for schema v1.0 and are not emitted by this backend (representation.md §6, issue #15), so body-level dependency edges are absent: the graph statistics above are type-level only.
+  **Types are printed with Agda's internal pretty printer**, which fully qualifies names and does not reconstruct surface syntax.  A type in this corpus reads `Overture.Signatures.Signature 𝓞 𝓥` where the source reads `Signature 𝓞 𝓥`.  This is what makes string search over types work at all, but it means the strings are not source text.
+  **`--safe` and `--cubical-compatible` status is not recorded** per row, so the corpus cannot be filtered by which pragma regime a definition was checked under.
+  **One library, one commit**.  Nothing here generalizes to another Agda library; a corpus of the standard library or of `agda-categories` is separate work.

## License and attribution

The corpus is derived from `agda-algebras`' `src/`, which is licensed under the **Apache License 2.0**, Copyright 2025-2026 William DeMeo and Contributors.  The rows are therefore distributed under the same license, and a redistribution must carry that license and attribution.  Cite the library as the source of the mathematics:

> The Agda Universal Algebra Library (`ualib/agda-algebras`), commit `ecc158a3730259b75d2ace4f5e30764e1c514380`, Apache-2.0.

**This card** — the prose you are reading, which `agda-native-air` wrote — is part of that project's documentation and is licensed **CC-BY-4.0** (see its `LICENSE-docs`).

**`stats.json` and `stats.md` are not.**  They are computed from the corpus's rows and quote the library's identifiers, so they inherit the corpus's terms: **Apache-2.0**, like the corpus itself.  They also ship beside the corpus under `data/corpora/agda-algebras/v0/` and as release assets, not under `docs/`.  The rule `agda-native-air` applies is that an artifact derived from a corpus travels with that corpus; see the "Licensing" section of its `README.md`.

## Reproducing it

From an `agda-native-air` checkout, outside any Nix shell:

```sh
git -C ~/git/ualib/agda-algebras/master checkout ecc158a3730259b75d2ace4f5e30764e1c514380

make extract-lib-nix AGDA_ALGEBRAS_ROOT=~/git/ualib/agda-algebras/master PAR=8 RESUME=0
make corpus-nix
```

The first target generates the module list (typechecking the library once to get its dependency graph), then extracts every module through `agda-json`.  The second concatenates the per-module JSONL and writes `coverage.json`, `provenance.json`, `stats.json`, and `stats.md` under `data/corpora/agda-algebras/v0/`.

Assembly refuses to write a corpus whose row count disagrees with the extraction manifest's, so a raw tree that changed after it was validated is an error rather than a quietly inconsistent release.

Expect about six minutes of wall time with warm `.agdai` interfaces and considerably more from cold; the extraction is 7,348 seconds of module time at parallelism 8.  Byte-identical output is expected for the same library commit and the same toolchain: modules are concatenated in sorted order and the gzip is written with no stored filename and `mtime=0`.  Compare against the digests above.

## Using it with agda-mcp

```sh
gunzip -k corpus.jsonl.gz
agda-mcp --corpus corpus.jsonl [other flags]
```

Loading registers `search_by_name`, `search_by_type`, and `get_dependencies` alongside the server's other tools.  The whole corpus loads in about 1.4 seconds to a 308 MB resident footprint: the index keeps only the fields the search tools serve, so the `typeAst` and the proof bodies are read and dropped rather than retained (which is what the 2.7 GB before that change was).  Search is a linear scan over 10,520 entries; issue #16 replaces it with inverted indices.

To check a corpus end to end through the server's real JSON-RPC transport:

```sh
make corpus-mcp-smoke
```

[agda-algebras]: https://github.com/ualib/agda-algebras
