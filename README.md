<!-- File: agda-native-air/README.md -->

# Agda-native AIR

*Agda-native Artificial Intelligence Reasoning environment*

`agda-native-air` is a research project for building the interaction, retrieval, and
evaluation infrastructure that allows modern AI agents to work effectively with
**Agda**.

The project is organized around four core components.

1. **Interaction** — programmatic access to Agda proof states and hole filling;
2. **Bridge** — an MCP-based interface for AI agents;
3. **Retrieval** — structured corpus extraction and search over Agda libraries;
4. **Evaluation** — deterministic fixtures, logs, and reproducible proof-completion reports.

Agda remains the final arbiter of correctness.

---

## Why this project exists

AI-assisted theorem proving is advancing rapidly, but most recent infrastructure
and benchmarks are concentrated in the Lean ecosystem.

Agda deserves its own serious path into AI-assisted formal reasoning.

This repository focuses on building that path:

- **AgdaDojang** — programmatic interaction with Agda;
- **agda-mcp** — MCP bridge for frontier coding agents;
- **structured extraction** — retrieval- and analysis-friendly Agda corpus data;
- **deterministic evaluation** — reproducible proof-completion and benchmarking workflows.

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

This repository is the public continuation of a longer private development effort.

The following already exist in working form:

+  deterministic fixture-based proof completion;
+  Agda-in-the-loop propose → check workflows;
+  structured extraction and ETL foundations;
+  schema documentation and evaluation reports.

The following is currently under development:

+  `agda-mcp`;
+  retrieval over structured Agda corpora;
+  local specialist models for narrow tasks such as premise selection and candidate ranking.

For details, see:

+  [`docs/MANIFESTO.md`](docs/MANIFESTO.md)
+  [`docs/PLAN.md`](docs/PLAN.md)
+  [`docs/public-history.md`](docs/public-history.md)

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

## Citation / publication status

Publication drafts are in progress.  For now, please cite the repository URL and
reference the relevant docs in `docs/`.

---

## A note on history

This public repository is a curated continuation of prior private development.
See [`docs/public-history.md`](docs/public-history.md) for migration notes.


