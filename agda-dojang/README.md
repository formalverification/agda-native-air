<!-- agda-ai-prover/agda-jang/README.md -->

# AgdaJang

**AgdaJang** is the interactive execution and experimentation layer of the **agda-ai-prover** project.

It provides a small, carefully designed vocabulary of *safe proof actions* inside Agda, together with external tooling that allows AI agents (and humans) to **interact with Agda's typechecker**, propose proof steps, and observe precise semantic feedback.

AgdaJang is where learned policies are *executed*, *validated*, and *debugged*.

---

## Role in the Overall System

Within the agda-ai-prover architecture, AgdaJang serves as

+  the **action space** for AI agents,
+  a bridge between statistical models and Agda's typechecker,
+  a sandbox for experimenting with interactive proof search.

While ProofParser focuses on *learning from existing mathematics*, AgdaJang focuses on **doing mathematics** — one proof step at a time — under Agda's supervision.

---

## Design Principles

AgdaJang is guided by a few core principles.

+  **Soundness first**: every action is checked by Agda.
+  **Small action vocabulary**: prefer a few well-understood primitives over a large tactic language.
+  **Transparency**: surface goals, contexts, and failures explicitly.
+  **Research-oriented**: optimize for inspectability and extensibility, not raw automation.

AgdaJang is not intended to compete with mature tactic languages; it is intended to be *learnable* by machines.

---

## Agda-side Components

### TC Monad Macros

At the core of AgdaJang is a collection of macros implemented in Agda's **TC monad**.

These macros operate *inside* Agda's type theory and can

+  inspect the current goal,
+  query the local context,
+  attempt to construct or apply terms,
+  report subgoals in a structured way.

Key macros include:

+  `refine⟨_⟩` — insert a candidate term into the goal,
+  `apply⟨_⟩` — apply a function or lemma and generate subgoals,
+  `applyWith⟨_,_⟩` — apply with explicit arguments,
+  `applyReport⟨_⟩` / `applySolveReport⟨_⟩` — apply while emitting structured goal reports,
+  `intro` — introduce a lambda when the goal is a function type.

Each macro is designed to be *deterministic*, *locally scoped*, and *easy to reason about in isolation*.

---

### AgdaJang Library Layout

```
agda-jang/
├── agda/
│   └── AgdaJang/
│       ├── Prelude.agda
│       ├── Refine.agda
│       ├── Apply.agda
│       ├── Debug.agda
│       └── Everything.agda
├── python/
│   └── tools/
│       ├── jang_try.py
│       ├── search.py
│       └── helpers.py
├── Makefile
└── README.md
```

The `Everything` module re-exports the full AgdaJang action vocabulary.

---

## Python-side Tooling

AgdaJang includes lightweight Python tools that orchestrate interaction with Agda.

### `jang_try.py`

This script

+  generates scratch Agda modules,
+  inserts candidate terms or macro invocations,
+  runs Agda on the generated code,
+  parses emitted goals and diagnostics.

It is primarily intended for **rapid experimentation** and debugging.

---

### `search.py`

This script implements simple proof-search strategies (e.g. BFS / beam search) over the AgdaJang action space.

Its purpose is not to be state-of-the-art, but to

+  demonstrate how an agent can interact with Agda step-by-step,
+  provide baselines for learned policies,
+  generate data for interactive learning.

---

## Typical Workflow

A typical AgdaJang session looks like this.

1.  Start from a goal (an Agda hole),
2.  Propose an action (e.g. `intro`, `apply⟨lemma⟩`),
3.  Let Agda check the result,
4.  Observe new goals or failure reports,
5.  Repeat until the proof is complete or abandoned.

Every step is validated by Agda.

---

## Running AgdaJang

### With Nix (recommended)

From the repository root:

```bash
nix develop
cd agda-jang
make check
```

This type-checks all AgdaJang macros.

---

### Demo Targets

From `agda-jang/`:

```bash
make demo1    # Simple refinement demo
make demo2    # Apply + subgoal reporting demo
```

These demos serve as executable documentation.

---

## Research Notes and Future Directions

+  Expand the action vocabulary (e.g. rewrite, structured intro).
+  Add richer goal and failure reporting for learning.
+  Integrate learned policies from `ml-pipeline`.
+  Deeper experimentation with reflective proof search.

*AgdaJang is intentionally minimal today, but designed to grow alongside the agents that use it.*

---

## See Also

* Root project README
* `proof-parser/README.md`
* `ml-pipeline/README.md`

