# Contributing to agda-native-air

Thank you for your interest in contributing to `agda-native-air`!

This project is still in an early phase.  The codebase is real and already
useful, but parts of it are being reorganized and clarified as we move
away from a private research repository and into a public collaboration space.

The goal of this document is to make contribution easier and less intimidating.

---

## What kinds of contributions are welcome?

We welcome help with

- Agda tooling and interaction workflows;
- `agda-dojang` and proof-state tooling;
- `agda-mcp` bridge design and implementation;
- `agda-strux` extraction, ETL, and schema validation;
- retrieval and graph-based views;
- fixture and benchmark design;
- tests, CI, and developer experience;
- documentation and onboarding;
- local specialist models for narrow tasks;
- mathematically informed case studies.

---

## Ground rules

### 1. Agda is the oracle

All AI components are supporting actors. Proposals are cheap; type-checked results
matter.

### 2. Prefer small, reviewable changes

Small PRs are easier to review, test, and merge.

### 3. Preserve clarity over cleverness

This project is a research environment, not just a pile of scripts.
We value explicit structure, readable docs, and reproducible workflows.

### 4. Keep experiments isolated

Exploratory work is welcome, but please put it in a clearly named place
(e.g., `experiments/`) unless it is part of the core environment.

### 5. Update docs when behavior changes

If you change setup, workflow, naming, paths, or architecture, update the relevant
docs.

---

## First-time contributor suggestions

Good early contributions include

- docs cleanup;
- test improvements;
- fixture additions;
- benchmark curation;
- CI polish;
- command-line usability improvements;
- public-facing architecture diagrams.

---

## Development setup

See `docs/HowToRun.md`.

Typical setup:

```sh
git clone git@github.com:formalverification/agda-native-air.git
cd agda-native-air
nix develop
make test
```

If a workflow depends on the Nix shell, say so clearly in docs and PR descriptions.

---

## Issues, branching, pull requests

### Issues

We prefer issues with a clear

+  problem statement
+  motivation and scope
+  acceptance criteria

Adding a list of non-goals can be helpful.

The issue tracker should support the plan, not replace it.

---

### Branch names

Use descriptive names, ideally with an issue number when applicable.

**Examples**.

+  `18-add-mcp-tool-schema`
+  `22-fix-fixture-demo-docs`

It's best if there's a GitHub issue that describes the purpose of a branch;
in that case, if the branch is created using the link on the right-hand side of the
issue page, then GitHub will propose a good branch name for you.

### Pull request guidelines

A good PR should answer the following questions:

+  What changed?
+  Why did it change?
+  How was it tested?
+  What docs were updated?
+  Does it close or relate to an issue?

---

## Testing expectations

At minimum, contributors should run the tests relevant to the changed component.

Examples include

+  fixture demo / evaluator tests;
+  extraction / ETL tests;
+  unit tests for `agda-dojang`, `agda-strux`, `agda-mcp`;
+  CI-related smoke tests.

If a change affects reproducibility or setup, please mention exactly what you ran.

---

## Documentation expectations

Relevant docs include

+  `README.md`
+  `docs/MANIFESTO.md`
+  `docs/PLAN.md`
+  `docs/representation.md`
+  `docs/HowToRun.md`
+  `docs/architecture.md`
+  `docs/public-history.md`

If your change affects any of these, please update them in the same PR.

---

## Coding style

We use multiple languages and tools in this repository, including Agda, Haskell,
Rust, Scala, Spark, and Python.  In general,

+  prefer explicit, maintainable code;
+  prefer deterministic behavior in evaluation tooling;
+  isolate experimental code from core infrastructure;
+  keep schemas versioned;
+  avoid silently changing public interfaces.

For language-specific conventions, follow the style already used in the relevant
subproject.

---

## Research directions

Some research directions are intentionally deferred while the environment is
stabilizing; these including the following:

+  deep reflection-driven automation;
+  deep SMT / reflection integration;
+  broad conjecture-generation workflows.

These remain interesting and encouraged as future research directions; they are
simply not a primary focus during the current public bootstrap phase.

---

## Questions

If you are unsure where a contribution belongs, open an issue or draft PR and ask.
That is much better than guessing wrong in silence.  We would rather help shape a
good contribution early than untangle a large one late.


