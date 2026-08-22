<!-- File: agda-native-air/README.md -->

# Agda-native AIR
[![CI](https://github.com/formalverification/agda-native-air/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/formalverification/agda-native-air/actions/workflows/ci.yml) [![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Docs: CC-BY 4.0](https://img.shields.io/badge/Docs-CC--BY_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/) [![Agda](https://img.shields.io/badge/Agda-2.8.0-4e9a06.svg)](https://wiki.portal.chalmers.se/agda) [![Haskell](https://img.shields.io/badge/Haskell-GHC_9.10.3-5e5086.svg)](https://www.haskell.org/) [![Scala](https://img.shields.io/badge/Scala-2.13-dc322f.svg)](https://www.scala-lang.org/)

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
├── LICENSE
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── docs/
│   ├── MANIFESTO.md
│   ├── PLAN.md
│   ├── GITHUB_PROJECT.md
│   ├── roadmap.md
│   ├── representation.md
│   ├── architecture.md
│   ├── HowToRun.md
│   └── public-history.md
├── agda-dojang/
├── agda-strux/
├── agda-mcp/
├── data/
├── experiments/
└── scripts/
```

### Main components

+  `agda-dojang/`

   + Agda interaction and evaluation tooling
   + goal/context reporting
   + hole filling and candidate checking
   + fixture-based proof-completion demo

+  `agda-strux/`

   + structured corpus extraction
   + ETL and derived views
   + schema and validation tooling

+  `agda-mcp/`

   + bridge layer
   + agent-facing tool definitions and implementations

+  `data/`

   + committed fixtures and benchmark slices

+  `experiments/`

   + local models
   + retrieval experiments
   + archived exploratory work

---

## Current status

This repository is the public continuation of a private proof-of-concept development effort.

The following already exist in working form:

+  deterministic fixture-based proof completion;
+  Agda-in-the-loop propose → check workflows;
+  structured extraction and ETL foundations;
+  schema documentation and evaluation reports.

The following is currently under development:

+  `agda-mcp`;
+  retrieval over structured Agda corpora;
+  local specialist models for narrow tasks such as premise selection and candidate ranking.

For details, see

+  [`docs/MANIFESTO.md`](docs/MANIFESTO.md): motivation and vision for the project
+  [`docs/PLAN.md`](docs/PLAN.md): project plan
+  [`docs/GITHUB_PROJECT.md`](docs/GITHUB_PROJECT.md): living project roadmap (milestones and issues, synced with GitHub)
+  [`docs/roadmap.md`](docs/roadmap.md): the frozen bootstrap plan the repository's issues were populated from
+  [`docs/representation.md`](docs/representation.md): data contracts / schemas
+  [`docs/architecture.md`](docs/architecture.md): system architecture overview
+  [`docs/public-history.md`](docs/public-history.md): notes on the early history of this repository

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

Three kinds of thing live here and they are licensed differently, so the split is
worth stating plainly.

+  **Code**: [Apache License 2.0](LICENSE).  This covers everything under
   `agda-strux/`, `agda-mcp/`, `strux-driver/`, `ml-pipeline/`, `agda-dojang/`,
   and `scripts/`.  It permits commercial use, redistribution, and use in
   training or evaluating machine-learning models, asking only that you keep the
   notices, include the license, and say what you changed.
+  **Documentation**: [CC-BY-4.0](LICENSE-docs).  Everything under `docs/`.
+  **Datasets**: *per dataset, named in the dataset's own card* under
   [`docs/corpora/`](docs/corpora/).  Not per repository, because this project
   does not own all of what it extracts.

That last point is the one that surprises people, so here is the reasoning.  A
corpus extracted from another Agda library is a derivative work of that library's
source: its rows are that library's types and proof terms, rendered differently.
This project cannot relicense them, so such a corpus is redistributed under the
upstream license, with the attribution that license requires.  The
[agda-algebras corpus](docs/corpora/agda-algebras-v0.md) is Apache-2.0 for
exactly this reason, inherited from
[`ualib/agda-algebras`](https://github.com/ualib/agda-algebras).  A corpus this
project authors outright — one derived from fixtures written here, or a purely
statistical summary — is dedicated to the public domain under
[CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/), which is the
least friction we can offer.

**If you are assembling training data**, none of the above should slow you down:
Apache-2.0 and CC0-1.0 are both standard permissive choices, and each corpus's
card gives you the upstream commit and the citation to reproduce and credit it.
If a license here is nonetheless in your way, open an issue and say which one and
why; that is a bug in how we have set this up, not a position we are defending.

---

## Citation / publication status

Publication drafts are in progress.  For now, please cite the repository URL and
reference the relevant docs in `docs/`.

---

## A note on history

This public repository is a curated continuation of prior private development.
See [`docs/public-history.md`](docs/public-history.md) for migration notes.


