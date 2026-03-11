<!-- File: docs/PLAN.md -->

# PLAN.md — Agda-Native AI Reasoning Environment

**Version**: 2.2 (living document)

**Date**: 2026-03-07

**Companion docs**:

+  [`MANIFESTO.md`][MANIFESTO] (why — the Agda-native AI reasoning environment vision)
+  `PLAN.md` (this document: what / when / how) 
+  [`docs/representation.md`][representation] (data contracts)
+  [`docs/HowToRun.md`][HowToRun] (how to run)

---

## 0. North Star

Build the **Agda-native reasoning environment**, an interaction layer
between frontier AI models and the Agda proof assistant, augmented by *local,
specialized models* for retrieval, ranking, and routine proof completion.
Create an environment where any sufficiently capable LLM can reason effectively
with Agda.

In practical terms, this will be achieved by developing and integrating four essential components.

1. **interaction** — a programmatic interface to Agda proof states and hole filling;
2. **retrieval** — a structured corpus and search layer over Agda libraries;
3. **evaluation** — deterministic fixtures, logs, and success metrics;
4. **selective learning** — local specialist models for narrow tasks where they are genuinely useful.

The long-term horizon remains ambitious,

> *an AI system that assists with proof development, library growth, counterexample discovery, and eventually mathematical exploration*,

but the near-term deliverable is much sharper,

> *a reproducible, publishable Agda-native environment in which Agda remains the final oracle of correctness*.


### What success looks like

1.  **Interaction foundation**.  `agda-dojang` exposes a stable, testable action surface for goal inspection, hole filling, and diagnostics.
2.  **Bridge foundation**.  `agda-mcp` lets frontier agents interact with Agda through a standard protocol.
3.  **Retrieval foundation**.  Canonical corpus extraction and derived views support useful search over theorems, definitions, dependencies, and interfaces.
4.  **Evaluation foundation**.  A fixed benchmark of proof obligations runs deterministically and produces machine-readable reports.
5.  **Demonstration**.  Real proofs in `agda-algebras` and fixture modules are completed with AI assistance and typecheck reproducibly.
6. **Publication**.  At least one tool paper and one empirical paper emerge from the above.

---

## 1. Guiding Principles

### 1.1 Build the environment, not the brain

Frontier LLMs improve monthly.  Our job is to give them the best possible interface
to Agda, not to train a competing general reasoner.

The environment consists of four main components.

+  **interaction layer** (`agda-dojang`),
+  **bridge layer** (`agda-mcp`),
+  **retrieval layer** (structured corpus, search, premise selection)
+  **evaluation layer** (fixtures, metrics, deterministic reports, benchmarks,
   typecheck-based scoring).

This will provide a laboratory for Agda-native AI experimentation.

### 1.2 Local models are specialist tools

We still care about local models — but only where they are well motivated.

Where a small, domain-specific model outperforms a general LLM — premise selection,
proof-term ranking, type-aware embeddings, routine proof completion — we train and
run locally.  These models are **tools in the MCP server's toolkit**, not
replacements for the frontier model.

Target hardware: NVIDIA Jetson AGX Orin 64GB (or equivalent desktop GPU).  This
constrains us to models ≤ 7B–13B (QLoRA fine-tuning) or ≤ 30B (quantized inference).
For specialized tasks (ranking, embeddings), 1B–3B models are likely sufficient.

### 1.3 Keep the canonical schema tiny

The canonical JSONL row should remain small and stable:

+  identity (`prettyQname`, module, location),
+  statement (`type`, `typeAst`, `typeAstVersion`),
+  optional proof body (`body`, `hasBody`),
+  minimal dependencies (`dependencies`).

Anything richer is a **derived view** produced by ETL.

### 1.4 Version anything structural

Structural encodings must be explicitly versioned.  We prefer additive evolution to
breaking change.

For instance, `typeAstVersion` already exists; we'll keep that approach, but add
future versions as new fields or values, limiting breaking changes to major
milestones/versions.


### 1.5 Agda remains the final arbiter

All external tools — frontier LLMs, local models, SMT solvers, retrieval
engines — are *supporting actors*.  They propose candidates; **Agda verifies**.

Frontier models propose, local models rank or retrieve, other tools may suggest
examples or counterexamples, but Agda is the source of truth.

### 1.6 Publishable increments matter

Each phase should produce something that is independently useful — a tool, a dataset,
an evaluation result, or a paper-ready experiment.

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    User / Editor                         │
│            (Emacs agda2-mode / VSCode / CLI)             │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│              Frontier LLM Agent                          │
│         (Claude Code / Codex CLI / etc.)                 │
│                                                          │
│  Handles: strategy, planning, novel reasoning,           │
│           error interpretation, proof decomposition      │
└──────────────────────┬───────────────────────────────────┘
                       │ MCP
                       ▼
┌──────────────────────────────────────────────────────────┐
│                   agda-mcp server                        │
│                                                          │
│ Proof state tools:   get-goal, fill-hole, check-file,    │
│                      get-diagnostics                     │
│                                                          │
│ Search / retrieval   find-by-type, find-by-name,         │
│   tools:             dependency-neighbors,               │
│                      premise-select (neural)             │
│                                                          │
│  Context / file      get-file, list-modules,             │
│    tools:            inspect-dependency-graph            │
└────────┬────────────────────────────┬────────────────────┘
         │                            │
         ▼                            ▼
┌─────────────────┐     ┌───────────────────────────────────┐
│   AgdaDojang    │     │  Local models (GPU / Jetson)      │
│                 │     │                                   │
│ Programmatic    │     │  |- premise selector (QUILL-like) │
│ interaction     │     │  |- type-aware embeddings         │
│ with Agda:      │     │  |- proof-term ranker             │
│ |- get goal     │     │  |- routine proof completer (7B)  │
│ |- fill hole    │     │                                   │
│ |- type-check   │     │  (Optional — system works         │
│ |- diagnostics  │     │   without these, just slower)     │
└────────┬────────┘     └───────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│      Agda       │
│  (typechecker   │
│   = oracle)     │
└─────────────────┘
```

**Key design property**.  The system works end-to-end with just `agda-dojang`,
`agda-mcp`, and a frontier LLM; local models are optional accelerators and
experimental components — they can improve performance and retrieval quality, reduce
API costs, and enable offline/low-connectivity use — but they are not prerequisites. 

---

## 3. Data Extraction and Representation

### 3.1 Why extract data?

Data extraction serves three purposes (none of which is "to train a general-purpose prover").

1.  **Retrieval corpus**.  `agda-mcp` server's search tools need a structured, queryable
    index of Agda libraries (types, dependencies, interfaces) for search, navigation,
    and prompt context; this is the primary consumer of canonical JSONL rows.

2.  **Specialized model training**.  Premise selection, embedding, and ranking models
    are trained on corpus data; these are narrow tasks where small models trained on
    domain-specific data can outperform general LLMs.

3.  **Evaluation and benchmarking.**  Measuring whether the system works requires a
    catalogue of proof obligations with known solutions.


### 3.2 Canonical rows vs. derived views

**Canonical definition rows** are the stable base layer.
They are designed to support indexing, joins, debugging, derived dataset
construction, and compatibility across experiments.

**Derived views** are where experimentation happens.  Some planned or existing
examples are the following:

+  structural AST views;
+  ports / wires / interface descriptions;
+  graph edge lists;
+  fixture proof-completion datasets;
+  embedding pairs;
+  candidate-ranking examples.

### 3.4 Relationship to Agda2Train

Our extractor (`agda-strux`) and Agda2Train are complementary rather than redundant.

+  **agda-native extraction pipeline** (`agda-strux` + Scala driver) is
   definition-level, compact, stable, and retrieval-friendly.
+  **Agda2Train** is interaction-state-level, larger, and ideal for premise-selection
   or proof-step learning.

|                       | `agda-strux`                                | `agda2train`                                |
|-----------------------|---------------------------------------------|---------------------------------------------|
| **Granularity**       | One row per definition                      | Many states per definition (sub-term level) |
| **Primary use**       | Retrieval, graph, LLM context               | Training neural proof-step predictors       |
| **Unique strength**   | Ports/wires, dependency graph, clean schema | Full typing context at every sub-term       |
| **Output size**       | Compact                                     | Very large                                  |
| **Human readability** | High                                        | Low                                         |


A combined system would use Agda2Train's data to train premise selection models
(like QUILL) and our data to power the retrieval/search tools in the MCP server.
This is the basis for potential collaboration.

---

## 4. Roadmap

### Phase 0 — Solid infrastructure (current)

**Goal**.  Make corpus extraction, validation, and evaluation boringly reliable.

**Deliverables**.

+  canonical JSONL extraction works on `agda-algebras` and stdlib slices;
+  extraction can resume and emit diagnosable manifests/logs;
+  `docs/representation.md` is current and accurate;
+  the deterministic proof-completion evaluator works on committed fixtures;
+  CI passes; `clone → nix develop → tests → extraction → eval` is documented and
   reproducible.

**Existing issue threads carried forward**.

+  extraction reliability / resumability / docs;
+  structural AST and ETL chain;
+  schema correctness (`prettyQname`, operator cases);
+  evaluator + fixture policy + bridge integration.

**Exit criterion**.  A new collaborator can reproduce the extraction and fixture
evaluation story without tribal knowledge.

---

### Phase 1 — agda-dojang + agda-mcp + first end-to-end proofs (near-term, 2–4 weeks)

**Goal**.  Build the MCP server, connect Claude Code to Agda, get real proofs type-checking.

**Deliverables**.

1.  **Rename and stabilize AgdaDojang**.

    +  rename `agda-jang` → `agda-dojang`;
    +  preserve the existing deterministic bridge/evaluator behavior;
    +  tighten tests around the goal/context reporting and candidate-check loop.

2.  **Implement `agda-mcp`**.  A thin MCP wrapper over AgdaDojang with tools such as:

    + `get-goal`: inspect the type of a hole and its local context;
    + `fill-hole`: propose a candidate term and get typecheck feedback;
    + `check-file`: load/reload a file and get all diagnostics;
    + `search-by-name`: find definitions matching a name pattern;
    + `search-by-type`: find definitions with compatible type signatures;
    + `get-dependencies`: retrieve the dependency neighborhood of a definition.
    + `get-diagnostics`: retrieve error/success rates, other candidate feedback.

3.  **Frontier-agent integration**. Demonstrate Claude Code or another MCP-capable
    agent using `agda-mcp` to solve holes in fixture modules and a small
    `agda-algebras` slice.  Document what works and what doesn't.

4.  **Baseline benchmark**.  Curate 20–50 proof obligations from agda-algebras (holes
    with known solutions). Measure: success rate, number of iterations, wall-clock time.

5.  **Tool paper draft**.  Working title: "AgdaDojang / AgdaMCP: An Agda-Native
    Environment for AI-Assisted Proof Development."

**Exit criterion**. A frontier agent can solve a nontrivial benchmark slice through
the `agda-mcp` interface with reproducible reports.

**Issue mapping**.

+ Update #23 (AgdaDojang ↔ policy integration) to target MCP protocol.
+ New issue: agda-mcp server implementation.
+ New issue: baseline evaluation benchmark (20–50 proof obligations).
+ New issue: Claude Code integration testing and documentation.


---


### Phase 2 — Retrieval and local specialists (medium-term, 4–10 weeks)

**Goal**. Improve proof success and usability through better, structure-aware
retrieval and training specialized, targeted local models.

**Deliverables**.

1.  **Ports / wires / graph layer**.  Carry forward the current ports/wires issue
    into the new public repo.

    **Output**: interface descriptions, body references, dependency edges,
    retrieval-friendly derived tables.

2.  **Retrieval inside `agda-mcp`**.  Build search tools using

    + exact and fuzzy name search,
    + type-signature matching,
    + graph-based retrieval and dependency neighborhoods,
    + later: structure-aware (neural) premise selection.

3.  **Train Local Models**.  For each of the examples below, try running it locally
    on Jetson or equivalent desktop GPU, and through the MCP interface, to see if it improves
    retrieval quality and proof success.  Compare with CPU performance.

    +  **Local premise selector**.  Train or adapt a QUILL-like premise selector for
       Agda corpora.

    +  **Proof-term ranker**.  Train/fine-tune a lightweight model (1B–3B) to rank
       candidate proof terms by likelihood of type-checking and predicts which
       candidates are most promising before invoking Agda.  This reduces Agda
       invocations in the propose-check-refine loop.

    +  **Type-aware embeddings**.  Build a small embedding model for semantic
       similarity across Agda types/definitions.

4.  **Comparative evaluation**.  Measure improvement from retrieval and local models
    vs. Phase 1 baseline (frontier model alone).

    Compare

    +  text-only retrieval,
    +  type-based retrieval,
    +  graph-based retrieval,
    +  local-model-enhanced retrieval,
    +  hybrid frontier + local systems.

5.  **Research paper draft**.  Working title: "Structure-Aware Retrieval for
    AI-Assisted Proof Development in Agda" — compare retrieval strategies (text-based
    vs. type-based vs. neural premise selection) on proof completion tasks.



**Exit criterion**.  Retrieval and ranking measurably improve the baseline benchmark
over Phase 1.


---

### Phase 3 — Research mathematics and counterexample workflows (longer-term)

**Goal**.  Use the system to do real mathematics — formalize new results in universal
algebra and related areas with AI assistance.

**Deliverables**.

1.  **AI-assisted extension of `agda-algebras`**.   Use the environment to formalize
    and streamline results relevant to your active mathematical agenda; e.g., formalize
    results relevant to the finite lattice representation problem (FLRP).  Document
    the experience.

2.  **Conjecture and lemma exploration**.  Given a set of results, use the agent to suggest
    plausible extensions and attempt to prove or refute them; this can be an experimental
    capability, rather than a primary deliverable.

3.  **Counterexample search hooks**. Integrate optional external tools such as GAP,
    Mace4, or SMT-based finite-model search where appropriate, as additional MCP
    tools for searching for finite countermodels.

4.  **Mathematics Paper** or **Case-study Writeup**.  Write a paper with AI-assisted
    formal proofs, demonstrating the system on real research-level mathematics, and/or
    document what the system can and cannot do on research-flavored problems.

**Exit criterion**. At least one credible AI-assisted formalization case study exists
beyond fixture demos.

---

### Phase 4 — Routine local proof completion (stretch)

**Goal**.  Train a local 7B model (QLoRA on Jetson) that handles routine proof
obligations without calling the frontier model; support a local-only or mostly-local
mode for predictable obligations.

This is viable once we have enough successful proof completions from Phases 1–3 to
generate training data.  The model learns patterns like "this is a homomorphism
proof, apply the standard strategy" and handles the predictable 60% of proof
obligations locally, reserving the frontier model for genuinely novel situations.

**Deliverable**.  A local proof completion model that runs on Jetson (or equivalent
desktop GPU), with measured success rate on routine obligations vs. frontier model;
compare local-only, frontier-only, and hybrid modes; assess practical value on modest
hardware.

**Exit criterion**. A local routine-completion model is useful enough to justify its maintenance cost.

---


## 5. Current Issue Map: What Carries Forward

We do **not** want to drag the entire old issue tracker into the public repo unchanged. We do want to preserve the best technical threads.

### Carry forward directly

+  structural AST / converter / ETL chain;
+  `prettyQname` correctness fixes;
+  extraction reliability / resumability / docs;
+  deterministic evaluator + fixture policy backend;
+  ports / wires / graph-view experiments;
+  AgdaJang-to-policy integration, reframed as AgdaDojang + MCP.

### Reframe or merge

+  FastAPI model-server issues → merge into `agda-mcp` / bridge discussion;
+  tactic-vocabulary / next-tactic / distribution-target issues → reframe as optional local-model experiments;
+  higher-level "AI mathematician" issues → move to longer-term research backlog.

### Defer

+  SMT-as-oracle-tactic work;
+  deep reflection-driven automation;
+  grand conjecture-generation pipelines;
+  anything that presumes a general-purpose locally trained prover.

---

## 6. Dependency Graphs


### Version 0.1

```mermaid
graph TD
  A[Phase 0: Extraction + infrastructure] --> B[agda-mcp server]
  A --> C[Corpus index for retrieval]

  B --> D[Claude Code integration]
  D --> E[Baseline evaluation: 20-50 proofs]
  E --> F[Tool paper: AgdaMCP]

  C --> G[Ports/wires + graph index]
  G --> H[Retrieval tools in agda-mcp]
  H --> I[Comparative evaluation]

  G --> J[Local premise selection model]
  J --> H
  I --> K[Research paper: retrieval strategies]

  E --> L[Formalize UA results with AI]
  H --> L
  L --> M[Conjecture exploration]
  M --> N[Counterexample search: GAP/Mace4/SMT]
  L --> O[Mathematics paper]

  E --> P[Collect training data from successful proofs]
  P --> Q[Local proof completion model on Jetson]
```

### Version 0.2

```mermaid
graph TD
  A[Infrastructure: extraction + docs + CI + evaluator] --> B[AgdaDojang stabilization]
  B --> C[agda-mcp]
  A --> D[Corpus index]
  D --> E[Retrieval tools]
  C --> F[Frontier agent integration]
  E --> F
  F --> G[Benchmark + reports]
  G --> H[Tool paper]

  D --> I[Ports / wires / graph index]
  I --> E
  I --> J[Local premise selector]
  D --> K[Type-aware embeddings]
  G --> L[Proof-term ranker]
  J --> M[Comparative retrieval evaluation]
  K --> M
  L --> M
  M --> N[Empirical paper]

  G --> O[AI-assisted agda-algebras case study]
  M --> O
  O --> P[Research mathematics / FLRP support]
  O --> Q[Counterexample search hooks]
```

---

## 7. Now / Next / Later

### NOW (1–2 weeks)

1.  Finalize manifesto / plan / public narrative.
2.  Decide the new public repository structure (`agda-native-air`).
3.  Rename `agda-jang` → `agda-dojang` in docs and package names.
4.  Preserve and verify the deterministic evaluator and fixture demo.
5.  Finish or cleanly restate the extraction / ETL / representation chain: #57 → #58 → #59.
6.  Sketch the `agda-mcp` server API (what operations, what MCP tool definitions, what
    response formats).
7.  Try Claude Code on agda-algebras *without* MCP — document what works and what
    doesn't.  This establishes the baseline that `agda-mcp` needs to beat.

### NEXT (2–6 weeks)

1.  Create the curated public repository.
2.  Build agda-mcp: the thinnest possible MCP wrapper around AgdaDojang.
3.  Connect Claude Code via agda-mcp; get the first 2–3 proofs type-checking.
4.  Run agent experiments on fixtures and a small `agda-algebras` slice.
5.  Curate the evaluation benchmark (20–50 proof obligations).
6.  Talk to Carlos, Orestis, and Kokos about collaboration.
7.  Start the tool paper outline.

### LATER (6+ weeks)

1.  Implement ports/wires (#61) and graph-based retrieval.
2.  Explore collaboration to Train/adapt premise selection model for retrieval.
3.  Train first local specialist models.
4.  Counterexample search integration.
5.  Local proof completion model (Jetson).
6.  Build a research-level case study in universal algebra.

---

## 7. Data Representation and Derived Views

The data contract is specified in `docs/representation.md`.  Here we summarize what
views exist, what they're for, and how they feed into the system.

### 7.1 Canonical JSONL rows (backend output)

One row per definition.

**Always present**: identity, type string, structural AST, dependencies, optional body.

**Used for**: retrieval index, graph construction, evaluation benchmark source, LLM prompt context.

### 7.2 Derived views

**Retrieval layer**.

+  **Graph edge list**: `(prettyQname, dep, depKind)` — for retrieval, curriculum,
   and dependency analysis.
+  **Ports/wires** — interface descriptions for type-aware search and compatibility
   matching.

**Evaluation layer**.

+  **Proof-completion dataset**: `(goal, context) → target` — for training the local
   proof completion model and for evaluation.
+  **Other uses**: candidate logs, solved outputs, failure categories, success-rate dashboards.

**Training layer**.

+  **Embedding training pairs**: premise-selection pairs (goal, relevant-lemma) for training
   type-aware embedding models, candidate-ranking examples, routine-completion traces.


### 7.3 What we do NOT extract (and why)

**Sub-term proof states** (Agda2Train's specialty).  These are needed for training
neural proof-step predictors (QUILL-like models) but are not needed for retrieval
or LLM prompting.  If we collaborate with Kogkalidis/Melkonian, we use their tool
for this purpose rather than duplicating it.


---

## 8. Local model training plan

### 8.1 Models to train (ordered by priority)

1.  **Type-aware embedding model** (Phase 2)

    +  Architecture: sentence-transformer variant, fine-tuned on (type, relevant-lemma) pairs from the corpus.
    +  Size: ~100M–400M parameters.
    +  Purpose: powers semantic search in agda-mcp.
    +  Training data: derived from dependency graph + proof bodies.

2.  **Premise selection model** (Phase 2)

    +  Architecture: QUILL (Kogkalidis et al.) or a simpler classifier/ranker.
    +  Size: custom architecture, relatively small.
    +  Purpose: given a goal, rank which lemmas are most likely useful.
    +  Training data: AGDA2TRAIN output (collaboration with Melkonian) or derived from our corpus.

3.  **Proof-term ranker** (Phase 2–3)

    +  Architecture: small classifier (1B–3B), fine-tuned to predict whether a candidate term will typecheck.
    +  Purpose: cheap filter before expensive Agda invocations.
    +  Training data: collected from Phase 1–2 propose-check-refine loops (both successes and failures).

4.  **Routine proof completion model** (Phase 4)

    +  Architecture: 7B LLM, QLoRA fine-tuned.
    +  Purpose: handle predictable proof obligations without API calls.
    +  Training data: successful proof completions from Phases 1–3.
    +  Hardware: NVIDIA Jetson AGX Orin 64GB.

### 8.2 What we do NOT train

+  A general-purpose Agda theorem prover.
+  A model intended to compete with frontier LLMs on open-ended reasoning.
+  Anything requiring datacenter-scale compute.

---

## 9. Collaboration: Kogkalidis, Melkonian & Bernardy (KMB)

### 9.1 What they have

+  Agda2Train: sub-term-level proof state extraction.
+  QUILL: structure-aware neural architecture for premise selection.
+  Algebraic Positional Encodings: tree-structure-aware attention.
+  A published, evaluated system (NeurIPS 2024).

### 9.2 What we have

+  `agda-strux`: definition-level structural corpus extraction.
+  `agda-dojang`: programmatic interaction with Agda (goals, holes, diagnostics).
+  agda-algebras: a substantial universal algebra formalization.
+  (planned) ports/wires knowledge-graph view.

### 9.3 The combination

+  **QUILL** becomes a retrieval tool behind our **agda-mcp** server.
+  **AGDA2TRAIN** generates training data for premise selection.
+  `agda-stux` generates the retrieval index and LLM context.
+  `agda-dojang` provides the LLM interaction loop.

The resulting system is the Agda equivalent of Numina-Lean-Agent, but with
structure-aware retrieval that Lean tools lack.

---


## 10. Research questions

+  **H1**. Agda's term-level proofs provide richer, more direct signals for
   AI-assisted proof search than tactic-level representations.

   *Testable*.  Compare proof completion rates using structural (term-level)
   retrieval vs. text-level retrieval on matched proof obligations.

+  **H2**.  Cubical Agda enables AI reasoning about equality, transport, and quotient
   constructions that is not possible in systems where these features are axiomatic.

   *Testable*.  Identify proof tasks requiring computational univalence or HITs and
   test whether AI agents can handle them.

+  **H3**.  A hybrid architecture combining frontier LLMs (for reasoning) with local
   specialized models (for retrieval and ranking) outperforms either component alone
   on Agda proof completion.

   *Testable*. Compare success rates across configurations: frontier-only,
   local-only, and hybrid.



## 11. Maintenance

+  Every issue declares: inputs/outputs, acceptance criteria, which phase it belongs to.
+  PLAN.md is updated when: a phase milestone closes, a new research direction gains
   a concrete hook, or the architecture changes.
+  The GitHub issue list is generated dynamically (see Appendix A of the original
   PLAN.md for the `gh` command).


---


## 12. Dropped or deferred from v1

The following items from PLAN v1 are explicitly **not** in the current plan.  They
may be revisited if circumstances change.

+  **Custom general-purpose prover model**.

   Replaced by frontier LLM + MCP architecture.  Training a general Agda prover is
   not competitive with frontier models and not a good use of limited resources.

+  **Fine-tuning pipeline for next-tactic/next-step prediction**.

   The "Workstream E" from v1 assumed we'd train a model to predict proof steps from
   definition rows.  This is subsumed by (a) using frontier models for reasoning and
   (b) training narrow local models for specific tasks (premise selection, ranking).

+  **SMT as oracle tactic / reflection-based tactics** (Phases 2–3 of v1).

   Interesting but premature.  Counterexample search  via external tools (GAP,
   Mace4, SMT) is retained as a Phase 3 stretch goal, but deep Agda-reflection
   integration is deferred.

+  **FastAPI model server**.

   Replaced by MCP server.  The MCP protocol is the standard that coding agents
   (Claude Code, Codex CLI) already speak.

+  **Heyting/entailment derived views, Abramsky/GoI wiring semantics**.

   Intellectually interesting research directions, but not blocking any phase.
   Retained as "safe to explore" side investigations if time permits.

These directions are deferred for sequencing reasons, in light of the current
AI-for-theorem-proving environment---not because they are uninteresting; in fact,
they might later become some of the most Agda-distinctive research directions once
the core environment is stable.

[MANIFESTO]: https://github.com/formalverification/agda-native-air/blob/main/docs/MANIFESTO.md
[representation]: https://github.com/formalverification/agda-native-air/blob/main/docs/representation.md
[HowToRun]: https://github.com/formalverification/agda-native-air/blob/main/docs/HowToRun.md
