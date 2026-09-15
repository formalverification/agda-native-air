<!-- File: agda-native-air/README.md -->

# Agda-native AIR
[![CI](https://github.com/formalverification/agda-native-air/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/formalverification/agda-native-air/actions/workflows/ci.yml) [![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Docs: CC-BY 4.0](https://img.shields.io/badge/Docs-CC--BY_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/) [![Agda](https://img.shields.io/badge/Agda-2.8.0-4e9a06.svg)](https://wiki.portal.chalmers.se/agda) [![Haskell](https://img.shields.io/badge/backend_GHC-9.10.3-5e5086.svg)](https://www.haskell.org/) [![Scala](https://img.shields.io/badge/Scala-2.13-dc322f.svg)](https://www.scala-lang.org/)

*Agda-native Artificial Intelligence Reasoning environment*

`agda-native-air` is a research project for building the interaction, retrieval, and
evaluation infrastructure that allows modern AI agents to work effectively with
**Agda**.

The project is organized around four core components.

1. **Interaction**: programmatic access to Agda proof states and hole filling;
2. **Bridge**: an MCP-based interface for AI agents;
3. **Retrieval**: structured corpus extraction and search over Agda libraries;
4. **Evaluation**: deterministic fixtures, logs, and reproducible proof-completion reports.

Agda remains the final arbiter of correctness.

---

## Why this project exists

AI-assisted theorem proving is advancing rapidly, but most recent infrastructure
and benchmarks are concentrated in the Lean ecosystem.

Agda deserves its own serious path into AI-assisted formal reasoning.

This repository focuses on building that path:

- **AgdaDojang**: programmatic interaction with Agda;
- **agda-mcp**: MCP bridge for frontier coding agents;
- **structured extraction**: retrieval- and analysis-friendly Agda corpus data;
- **deterministic evaluation**: reproducible proof-completion and benchmarking workflows.

The long-term vision is ambitious: AI systems that help with proof development,
library growth, counterexample discovery, and eventually mathematical exploration.
But the near-term goal is sharper and more practical: a credible,
publishable **Agda-native reasoning environment**.

---

## Repository layout

```
agda-native-air/
├── README.md
├── LICENSE, LICENSE-docs, CONTRIBUTING.md
├── .github/                   # CI workflow, CODEOWNERS, issue and PR templates
├── flake.nix, flake.lock      # the pinned toolchain: Agda 2.8.0, stdlib 2.3, GHC, Scala, Spark, Python
├── Makefile                   # the single CLI for extract → transform → ETL → train → eval
├── agda-dojang/               # repo-local Agda library (reflection macros) + evaluation harness
├── agda-mcp/                  # the MCP server (Haskell)
├── agda-strux/                # structured extraction: Agda-as-a-library → JSONL (Haskell)
├── strux-driver/              # Scala driver: runs the extractor, hosts the benchmark runner and the proof search
├── ml-pipeline/               # Spark ETL (Scala) and training / retrieval / evaluation (Python)
├── configs/                   # pipeline configuration: the agda-algebras extraction config, logging
├── data/
│   └── benchmarks/            # the proof-obligation benchmark: fixtures, golds, index
├── docs/
│   ├── README.md              # index of the documentation, with a reading order
│   ├── adr/                   # architecture decision records (0001 proof search, 0002 agda-mcp)
│   ├── agda-mcp/              # the server's design notes
│   ├── proof-search/          # how the search works and how to read a run
│   ├── benchmarks/            # the difficulty taxonomy
│   ├── corpora/               # one dataset card per published corpus
│   ├── feedback/              # documents imported from consumer projects
│   ├── notes/                 # working notes and background reading
│   └── mcp-field-reports.md   # the session-by-session record of the server in real use
├── experiments/               # archived exploratory work (read-only)
├── reports/                   # archived agent transcripts
└── scripts/                   # launchers and Python utilities
```

### Main components

+  `agda-mcp/`: the bridge.  A Haskell MCP server that exposes Agda's proof state,
   type-checking verdicts, live scope and type queries, and corpus search to any
   MCP client.  Its design record is [`docs/adr/0002-agda-mcp.md`](docs/adr/0002-agda-mcp.md).
+  `agda-dojang/`: the interaction layer.  A repo-local Agda library whose
   reflection macros report goals and contexts, plus the proof-completion
   evaluation harness.
+  `agda-strux/`: the extractor.  A Haskell backend linking Agda as a library;
   its `agda-json` executable turns a checked module into canonical JSONL, one row
   per definition.
+  `strux-driver/`: the Scala driver.  It runs the extractor over a library,
   validates and transforms the JSONL, hosts the benchmark runner, and hosts the
   proof search (`struxdriver.search`), a client of `agda-mcp` like any agent.
+  `ml-pipeline/`: the ETL and modelling layer.  A Spark job turns JSONL into
   Parquet features; the Python side holds training, retrieval, and evaluation
   code.
+  `data/benchmarks/`: the benchmark suite.  Paired obligation and gold modules,
   a machine-readable index, and the difficulty classification of every row.
+  `docs/`: design records, notes, dataset cards, and the evidence record;
   [`docs/README.md`](docs/README.md) is the map.

---

## Current status

As of September 2026 the following are built, measured, and in use.

+  **`agda-mcp` v0.2.0**.  Thirteen tools over stdio: four proof-state tools
   (`get_goal`, `fill_hole`, `check_file`, `get_diagnostics`), a whole-project
   gate (`check_project`), five live queries answered by a persistent interaction
   lane (`type_of`, `normalize`, `resolve_name`, `definition_of`, `exports_of`),
   and three corpus-backed search tools (`search_by_name`, `search_by_type`,
   `get_dependencies`), which the server registers only when it is started with
   a corpus.  Every verdict on a file is the exit code of the `agda` run that
   produced it, `check_project` reports the exit code of the project's own gate
   without misreporting it, every response about a file names the tree it
   checked, and a server pointed at the wrong checkout refuses rather than
   guesses.  The tool contracts are in
   [`agda-mcp/README.md`](agda-mcp/README.md); the design decisions and the
   evidence behind them are [ADR 0002](docs/adr/0002-agda-mcp.md); connecting an
   agent, to this repository or to another Agda project, is
   [`docs/HowToRun.md` § 13](docs/HowToRun.md).  The server is in use from Claude
   Code sessions on two external Agda projects,
   [`ualib/agda-algebras`](https://github.com/ualib/agda-algebras) and the
   Cardano formal ledger specification,
   [`IntersectMBO/formal-ledger-specifications`](https://github.com/IntersectMBO/formal-ledger-specifications);
   what those sessions did with it, and
   where it fell short, is recorded session by session in
   [`docs/mcp-field-reports.md`](docs/mcp-field-reports.md).
+  **Two corpora**, extracted by `agda-strux` from pinned library commits and
   described by dataset cards under [`docs/corpora/`](docs/corpora/): the Agda
   standard library 2.3 (55,576 definitions from 1,153 modules;
   [card](docs/corpora/agda-stdlib-v0.md), reproducible from the flake in
   minutes) and agda-algebras (13,123 definitions from 409 modules;
   [card](docs/corpora/agda-algebras-v0.1.md), published as the
   [`agda-algebras-corpus-v0.1`](https://github.com/formalverification/agda-native-air/releases/tag/agda-algebras-corpus-v0.1)
   release).
+  **A benchmark of 55 proof obligations** with gold solutions, in three
   library tiers: 22 from the standard library, 21 mined from agda-algebras at
   the corpus commit, and 12 standard-library obligations whose proofs need a
   lemma the fixture imports but never names (the haystack tier).  Every row is
   classified into one of three difficulty tiers.  Every gold type-checks under
   the pinned toolchain, and CI re-verifies a slice whenever the benchmark, the
   Scala driver, or the flake changes.  See
   [`data/benchmarks/README.md`](data/benchmarks/README.md) and
   [`docs/benchmarks/taxonomy.md`](docs/benchmarks/taxonomy.md).
+  **Proof search on `agda-mcp`**.  A beam search in `strux-driver` proposes
   terms for the open hole, by rule or by retrieval over a corpus, and lets Agda
   judge every step.  The measured record: the fixed action space solves 8 of
   the 43 obligations of the first two library tiers and none of the 12 haystack
   rows, 8 of 55 in all; its 6 of 22 on the standard-library tier is exactly that tier's
   term-mode ceiling (the other sixteen golds restructure the clause: thirteen
   inductions, two case splits, and one reasoning chain whose imports the
   obligation does not carry, none of which a term can express).  Retrieval adds
   no solve under target exclusion on those two tiers, while the labeled
   controls with exclusion off commit all five excluded standard-library lemmas
   and one wholesale agda-algebras lemma end to end, so the machinery works; on
   the agda-algebras tier the ledgers locate the binding constraint in ranking
   at scale.  On the haystack tier, built so that retrieval has a needle to
   find, retrieval solves 6 of 12 against the fixed space's 0 of 12, the first
   solves under exclusion.  A stronger scorer is in review
   ([#152](https://github.com/formalverification/agda-native-air/pull/152)); the
   tracking issue, [#113](https://github.com/formalverification/agda-native-air/issues/113),
   carries the current numbers.  How the search works is
   [`docs/proof-search/overview.md`](docs/proof-search/overview.md); its decisions
   and numbers are [ADR 0001](docs/adr/0001-proof-search-on-agda-mcp.md).
+  **The extraction and evaluation pipeline**, end to end: `agda-strux` →
   `strux-driver` → the Spark ETL and Python layers, with a proof-completion
   evaluator whose reports share one schema with the search's, so a model's
   result and a search's result sit in the same table.

What comes next, in the order the evidence argues for:

+  **Ranking at scale** ([#19](https://github.com/formalverification/agda-native-air/issues/19)):
   the agda-algebras ledgers and the haystack nulls locate the binding
   constraint in ranking thousands of in-scope lemmas; a learned
   premise-selection scorer slots into the seam the search already exposes.
+  **An agent-in-the-loop measurement** ([#154](https://github.com/formalverification/agda-native-air/issues/154)):
   a frontier model driving the server over the same 43 obligations under a
   fixed prompt and budget, reported per tier beside the search's numbers.
+  **The field stream** (Milestone 5): the ergonomics the field reports keep
   asking for, such as batch verdicts, a returned patch from `fill_hole`, a
   library registry that survives worktree churn, and a profiling tool.
+  **Local specialist models** (Milestones 2 and 4): not started.  When they
   arrive they attach to `agda-mcp` as extra tools, so the interface an agent
   sees does not change.

For the plan and the record behind this section, see

+  [`docs/README.md`](docs/README.md): the index of `docs/`, what lives where, and a reading order;
+  [`docs/GITHUB_PROJECT.md`](docs/GITHUB_PROJECT.md): the living roadmap, milestones and issues synced with GitHub;
+  [`docs/architecture.md`](docs/architecture.md): the system architecture, layer by layer, with per-layer status;
+  [`docs/MANIFESTO.md`](docs/MANIFESTO.md) and [`docs/PLAN.md`](docs/PLAN.md): motivation, vision, and the plan by phase;
+  [`docs/representation.md`](docs/representation.md): the data contract for what the extractor emits;
+  [`docs/public-history.md`](docs/public-history.md): notes on the early history of this repository.

---

## Quick start

See [`docs/HowToRun.md`](docs/HowToRun.md) for the full setup.

Typical development flow is as follows (exact commands provided below):

1. clone the repo;
2. enter the Nix development shell;
3. run tests;
4. run the fixture demo;
5. explore extraction / evaluation workflows.

**Example high-level commands**.

```sh
git clone git@github.com:formalverification/agda-native-air.git
cd agda-native-air
nix develop
make test
make eval-proof-completion-smoke
make help    # see what's available and working now
```

---

## Project scope

This project is **not**

+  a mere autocomplete plugin;
+  training local models to compete with frontier models at open-ended reasoning;
+  a finished product.

This project **is**

+  an Agda-native reasoning environment;
+  a research platform;
+  a place to experiment seriously with AI-assisted proof development in Agda.

---

## Collaboration

We welcome contributors interested in

+  Agda tooling;
+  proof assistant infrastructure;
+  corpus extraction and representation;
+  retrieval and local specialist models;
+  evaluation and benchmarking;
+  constructive, algebraic, category theoretic mathematics, general type theory and/or HoTT.

If you want to join us, please start by reading [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## Licensing

Three kinds of thing live here and they are licensed differently.

+  **Code** — [Apache License 2.0](LICENSE).  Everything under `agda-strux/`,
   `agda-mcp/`, `strux-driver/`, `ml-pipeline/`, `agda-dojang/`, and `scripts/`.
   It permits commercial use, redistribution, and use in training or evaluating
   machine-learning models, asking only that you keep the notices, include the
   license, and say what you changed.
+  **Documentation written here** — [CC-BY-4.0](LICENSE-docs).  This covers
   `docs/` *except* for material imported from elsewhere, which this project has
   no standing to license.  There is one such file today:
   [`docs/feedback/flrp-agda-mcp-improvements.md`](docs/feedback/flrp-agda-mcp-improvements.md),
   imported verbatim from [`ualib/agda-algebras`](https://github.com/ualib/agda-algebras)
   and licensed by that project; its own header records the provenance.
+  **Data** — [Apache License 2.0](LICENSE) by default, and per dataset where a
   dataset says otherwise.  See below, because the default is not arbitrary.

### Why data defaults to the code license

Everything committed under `data/` is one of two things, and both land on
Apache-2.0 by different routes.

+  **Agda source written here.**  The benchmark obligations and gold solutions
   under `data/benchmarks/` are Agda modules; they are code, and the code license
   covers them.
+  **Material extracted from an Apache-2.0 library.**  A corpus, or a golden
   snapshot such as `data/agda/agda-algebras-regressions/Noether.jsonl`, consists
   of another library's types and proof terms rendered differently.  That makes it
   a derivative work of that library, and this project cannot relicense it.

So the default is Apache-2.0, and it is *not* a claim that this project owns the
contents — for extracted material it is the upstream license passing through, and
the required attribution is upstream's.

Two refinements sit on top of the default.

+  **A published corpus states its own terms** in its dataset card under
   [`docs/corpora/`](docs/corpora/), together with the upstream commit and the
   citation.  The card governs; the default applies to committed data that has no
   card.
+  **Artifacts derived from a corpus inherit that corpus's terms.**  The
   statistics, indices, and digests computed from a corpus are computed from its
   rows, so they travel with it.  Only a dataset with no upstream-derived content
   at all can be dedicated to the public domain under
   [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/), and where that
   is done its card says so.

### What this changed, and for whom

Before this policy, `LICENSE-docs` stated that `data/` was CC-BY-4.0.  That claim
is withdrawn, because it was not this project's to make for extracted material.
Two consequences worth stating plainly rather than leaving to be inferred:

+  For **extracted** data the CC-BY claim was never effective; the upstream
   license always governed, and now the files say so.
+  For any **project-authored** data the terms do change, from CC-BY-4.0 to
   Apache-2.0.  A licence already granted cannot be withdrawn: **anyone who
   received data from this repository under CC-BY-4.0 may continue to rely on
   that grant** for the copy they received.

### If you are assembling training data

Read the card for the corpus you want — it names the upstream commit, the
governing license, and the citation.  For the corpora published so far that
license is Apache-2.0, which does not obstruct training, evaluation, or
redistribution.  A corpus inherited from a library with different terms would say
so in its card, so check there rather than assuming this section covers every
future case.

If a license here is in your way, please open an issue saying which one and why.
That would be a bug in how we have set this up, not a position we are defending.

---

## Citation / publication status

Publication drafts are in progress.  For now, please cite the repository URL and
reference the relevant docs in `docs/`.

---

## A note on history

This public repository is a curated continuation of prior private development.
See [`docs/public-history.md`](docs/public-history.md) for migration notes.


