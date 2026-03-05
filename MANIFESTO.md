<!-- File: MANIFESTO.md -->

# Toward an Agda-Native AI Reasoning Environment

*MANIFESTO for agda-native (v2.1)*

## 1. Motivation

AI-assisted formal theorem proving is advancing rapidly.  Systems like AlphaProof,
DeepSeek-Prover-V2, Goedel-Prover-V2, Aristotle, and Numina-Lean-Agent have achieved
gold-medal performance on the International Mathematical Olympiad and solved all
twelve 2025 Putnam problems.  All of these systems target the **Lean 4** proof
assistant language.

A winning paradigm is emerging: **general-purpose coding agents** (Claude Code, Codex
CLI) interact with proof assistants through programmatic interfaces (MCP servers, LSP
wrappers), using the type-checker as a correctness oracle in a propose–check–refine
loop.  Specialized prover models are giving way to frontier LLMs augmented with
retrieval tools and proof-assistant feedback.

**Agda has no equivalent tooling.**  Despite having some unique technical
advantages---proof terms rather than tactic scripts, a mature ecosystem for
constructive and homotopy-type-theoretic mathematics, and native cubical type
theory---Agda is invisible in the current AI-for-math landscape.  If this gap is not
closed, Agda risks irrelevance precisely when formal methods are receiving
unprecedented attention and investment.

This project builds the **missing interaction layer** between frontier AI models and
the Agda proof assistant, augmented by **small, locally-trained models** for
domain-specific tasks where specialized knowledge outperforms general reasoning.  The
goal is to create an environment in which any sufficiently capable LLM can reason
effectively with Agda---exploiting its unique type-theoretic features rather than
working around them---while local models handle retrieval, ranking, and routine proof
obligations cheaply and privately.

---

## 2. The Current Landscape

To position this work, we briefly survey what exists.

### 2.1 Lean Ecosystem (extensive)

+  **LeanDojo** (Yang et al., NeurIPS 2023): programmatic interaction with Lean,
   enabling retrieval-augmented theorem proving.
+  **lean-lsp-mcp**: MCP server exposing Lean's LSP to coding agents, with search
   tools (LeanSearch, Loogle, Lean Hammer).
+  **Numina-Lean-Agent** (Liu et al., 2026): Claude Code + MCP, solved 12/12 Putnam
   2025 problems; demonstrates the "general agent + tool interface" paradigm.
+  **DeepSeek-Prover-V2**, **Goedel-Prover-V2**, **Aristotle**, **Seed-Prover**,
   **Ax-Prover**: specialized or agentic provers achieving state-of-the-art on
   competition and (increasingly) research-level benchmarks.
+  **Mathlib**: 250,000+ theorems providing a massive retrieval corpus.

### 2.2 Agda Ecosystem (sparse)

+  **Kogkalidis, Melkonian & Bernardy** (NeurIPS 2024): first ML dataset of Agda
   proofs with sub-type-level resolution; a structure-aware neural architecture
   (QUILL) for premise selection based on structural (not nominal) principles.
+  **MLFMF** (Bauer, Petković & Todorovski, NeurIPS 2023): benchmark datasets for
   Agda (stdlib, agda-unimath, TypeTopology) and Lean.
+  **This project (agda-ai-prover)**: a Haskell-based structured data extractor and
   AgdaJang, a programmatic interaction interface; both described below.

### 2.3 The Gap

No MCP server, no agentic proof framework, no retrieval-augmented proving pipeline
exists for Agda.  This project fills that gap.

---

## 3. Why Agda?

We do not claim that Agda should replace Lean for all use cases.  Lean's ecosystem
breadth, tactic automation, and community momentum make it a natural choice for many
projects.  But Agda offers specific, concrete advantages that matter for AI research
on formal reasoning---advantages that are not merely aesthetic.

### 3.1 Proof Terms as First-Class Data

In Lean, proofs are typically written as tactic scripts---imperative sequences whose
meaning depends on the prover's internal state at each step.  The underlying proof
terms exist but are **secondary** artifacts.  In Agda, **the proof term is the
proof**.  There is no indirection layer.

For AI, this difference is significant:

+  The dependency structure of a proof is directly visible in the syntax.
+  Proof search is equivalent to **program synthesis** in a dependently typed
   language---a well-studied problem with clear formal semantics.
+  Both frontier models (retrieving from Agda proofs as context) and local models
   (trained on Agda proof terms) work with a **direct representation of logical
   structure**, not an intermediate control language whose semantics is opaque without
   replaying the elaborator.

The Kogkalidis et al. work demonstrates this concretely: their structure-aware neural
architecture for premise selection was possible precisely because Agda proofs are
terms with explicit, inspectable structure.  A locally-trained premise selection model
can exploit this structure in ways that are unavailable for tactic-based systems.

### 3.2 Cubical Type Theory: Computational Equality

Cubical Agda is the most mature proof assistant with **native, computational
univalence** and a general schema of higher inductive types (HITs).  Equality proofs
in Cubical Agda are not opaque axiom invocations---they compute.  Function
extensionality, propositional extensionality, and quotient types all have
computational content.

For AI reasoning, this means

+  an agent can **normalize** equality proofs, obtaining canonical
   representations---something impossible when univalence is axiomatic;
+  quotient types and HITs are definable without escape hatches, enabling direct
   formalization of algebraic structures that require them (e.g., free algebras,
   group presentations, set-level truncations);
+  the type-checker provides richer feedback; not just "correct / incorrect" but
   fine-grained information about path structure and transport.

This is not a future possibility; it is the current state of Cubical Agda, used in
active research (synthetic homotopy theory, domain theory, algebraic effects,
constructive set theory).

### 3.3 Constructive Foundations for Universal Algebra

For the specific mathematical domains we target---universal algebra, lattice
theory, category theory and group theory---Agda offers

+  **universe-polymorphic dependent records** that naturally express algebraic
   signatures, algebras, homomorphisms, and congruences;
+  a constructive setting where existence proofs are programs, making formalized
   constructions directly executable;
+  the existing **agda-algebras** and **agda-categories** libraries, which already
   formalize substantial portions of universal algebra and category theory in this
   style.

---

## 4. Architecture: The Agda-Native AI Reasoning Environment

The system has four layers.  The first three are independently useful; the fourth
is a performance and autonomy enhancement that becomes viable as the system matures.

### 4.1 Interaction Layer: AgdaJang

AgdaJang provides programmatic access to Agda's proof engine.

+  **Goal inspection**.  Query the type of a hole, its local context, and available
   definitions.
+  **Hole filling**.  Propose a candidate term for a hole and receive type-checker
   feedback (success, error with location and message).
+  **Iterative refinement**.  Fill a hole partially (introducing new sub-holes) and
   continue interacting.
+  **Module-level operations**. Load files, check imports, inspect dependency graphs.

AgdaJang is the Agda analog of LeanDojo for Lean.  It is the foundation on which all
AI interaction is built.

### 4.2 Bridge Layer: agda-mcp

A Model Context Protocol (MCP) server that wraps AgdaJang and exposes Agda
interaction to any MCP-compatible coding agent (Claude Code, Codex CLI, Cursor,
etc.).  The server provides

+  **proof state tools**: get goal, fill hole, check file, get diagnostics;
+  **search/retrieval tools**: find definitions by type signature, search the corpus
   by name or structure, retrieve relevant lemmas for a given goal;
+  **context tools**: get file contents, navigate module structure, inspect the
   dependency graph.

This is the thinnest possible layer; it translates MCP requests into AgdaJang calls
and formats responses for the agent.

### 4.3 Intelligence Layer: Retrieval and Reasoning

The primary reasoning agent is a frontier LLM (not a custom model).  Its
effectiveness depends on three main factors.

+  **Retrieval quality**.  Given a proof goal, which lemmas, definitions, and
   proof patterns from the corpus are most relevant?  This is where structure-aware
   representations (Kogkalidis et al.) provide an advantage over naive text matching.
+  **Proof strategy**:  decomposing a complex goal into sub-goals, choosing between
   direct construction, case analysis, induction, transport, etc.
+  **Error interpretation**: understanding Agda's type-checker feedback and using it
   to refine the current attempt.

We do not build the frontier model.  We build the environment that makes it
effective.

### 4.4 Local Specialist Layer: Domain-Specific Models

For well-defined, narrow tasks, small locally-trained models can outperform frontier
LLMs---and they run cheaply, privately, and without network dependency.  This layer
is **optional**: the system works end-to-end with only Layers 4.1--4.3.  But local
models improve performance, reduce API costs, and enable offline use.

The local models we plan to train (in priority order):

1.  **Premise selection**.  Given a goal type, rank which library lemmas are most
    likely relevant.  This is a classification/ranking task---exactly the kind of
    narrow problem where domain-specific training data and a small architecture
    (cf. QUILL) beat general-purpose models.

2.  **Type-aware embeddings**.  A small encoder producing vector representations
    where semantically similar Agda definitions are close in embedding space.
    Powers fast approximate search in the retrieval layer.

3.  **Proof-term ranker**.  Given several candidate proof terms (proposed by the
    frontier model), quickly rank them by likelihood of type-checking---a cheap
    filter that reduces the number of expensive Agda invocations.

4.  **Routine proof completer**.  A fine-tuned 7B model (QLoRA) that handles
    predictable proof obligations (e.g., showing a construction preserves a
    property) without calling the frontier model.  Viable once sufficient training
    data has been collected from the propose–check–refine loop.

These models are **tools in the MCP server's toolkit**---called by the agent when
useful, not replacements for the agent's reasoning.

**Target hardware**: NVIDIA Jetson AGX Orin 64GB, supporting QLoRA fine-tuning
up to ~13B and quantized inference up to ~30B parameters.  For specialized tasks
(ranking, embeddings), 1B--3B models are likely sufficient.

---

## 5. Structured Corpus Extraction

The starting point for retrieval (and for local model training and evaluation) is a
**structured corpus** extracted from Agda libraries.

The extraction tool (agda-backend-jsonl) uses Agda as a Haskell library to produce
JSONL records containing five main features.

+  **Identity**: qualified name, module, source location.
+  **Statement**: the type, as both a human-readable string and a structural AST with
   version tag.
+  **Proof body**: the term (when present), with a flag indicating whether the
   definition has computational content.
+  **Dependencies**: references from the type and body, enabling dependency graph
   construction.
+  **Derived views** (optional): port/wire decompositions, interface signatures, edge
   lists for graph experiments.

The corpus serves three distinct purposes:

1.  **Retrieval**.  The MCP server's search tools query a structured index built from
    canonical JSONL rows.  This is the primary consumer.
2.  **Specialized training**.  Premise selection, embedding, and ranking models are
    trained on corpus-derived datasets.  These are narrow tasks---not general
    reasoning.
3.  **Evaluation**.  Measuring system performance requires a catalogue of proof
    obligations with known solutions.

### 5.1 Relationship to AGDA2TRAIN

Our extractor and the Kogkalidis et al. AGDA2TRAIN tool are complementary.
AGDA2TRAIN captures **sub-term-level proof states**---many interaction snapshots per
definition, recording the full typing context at each point.  This data is optimized
for training neural proof-step predictors (like QUILL).

Our extractor captures **definition-level structural summaries**---one compact,
human-readable row per definition, optimized for retrieval, graph construction, and
as context that can be included in an LLM prompt.

A combined system uses AGDA2TRAIN's output to train premise selection models and our
output to power the retrieval and search tools in the MCP server.

---

## 6. Target Use Cases

### 6.1 Interactive Proof Assistance

Via editor integration (Emacs agda2-mode, VSCode, or a terminal agent).

1.  The user writes a theorem statement with a hole.
2.  The agent (via agda-mcp) inspects the goal, retrieves relevant lemmas
    (using local premise selection if available), and proposes a candidate.
3.  Agda type-checks the candidate; on failure, the agent reads the error and
    refines.
4.  The loop continues until success or the agent reports an obstacle requiring human
    input.

For routine obligations, a local proof completion model may fill the hole directly,
without invoking the frontier model---providing faster response and zero API cost.

### 6.2 Library Development Assistance

For building up formalization libraries (e.g., extending agda-algebras,
agda-categories, etc.).

+  Filling routine proof obligations (e.g., show a construction preserves a property).
+  Suggesting missing definitions or lemmas based on the dependency graph.
+  Detecting opportunities for generalization or refactoring.

### 6.3 Research-Level Mathematics

For working mathematicians who use Agda.

+  **Formalize proof sketches**. The user provides an informal argument, the agent
   attempts to formalize each step.
+  **Conjecture exploration**.  Given a set of results, suggest plausible extensions
   and attempt to prove or refute them.
+  **Counterexample search**.  For a claimed property, search for structures that
   violate it (using computational content of constructive proofs, or external tools
   like GAP, Mace4, or SMT solvers).

---

## 7. What This Project Is Not

+  **Not a general-purpose prover model**.  We do not train an LLM to do open-ended
   mathematical reasoning.  The frontier model handles that.  We *do* train small,
   local models for narrow tasks (premise selection, ranking, embeddings, routine
   completion) where domain-specific training outperforms general reasoning.
+  **Not a Lean competitor**.  We target domains where Agda's type theory provides
   genuine advantages.  We do not target competition math or large-scale
   formalizations in classical logic.
+  **Not a finished product**.  This is a research program with a prototype.  The goal
   is to demonstrate feasibility, produce interesting/publishable results, and provide
   infrastructure for the Agda community.

---

## 8. Scope and Incremental Path

### Phase 0 — Infrastructure (current)

+  Reliable corpus extraction from agda-algebras + stdlib.
+  AgdaJang interaction working on small examples.
+  Schema documentation and validation.

### Phase 1 — MCP Server + First Proofs (near-term)

+  Build agda-mcp: the MCP wrapper around AgdaJang.
+  Demonstrate Claude Code filling holes in agda-algebras via agda-mcp.
+  Baseline evaluation: success rate on a curated set of proof obligations.
+  **Deliverable**: tool paper (AIM / ITP / CICM).

### Phase 2 — Retrieval + Local Models (medium-term)

+  Integrate structure-aware retrieval (type-based search, dependency graph,
   neural premise selection) into the MCP server.
+  Train local models: premise selector, type-aware embeddings, proof-term ranker.
+  Evaluate whether structure-aware retrieval and local models improve proof success
   rate over the Phase 1 baseline (frontier model alone).
+  **Deliverable**: research paper comparing retrieval strategies and measuring the
   contribution of local models.

### Phase 3 — Research Mathematics (long-term)

+  Apply the system to formalizing new results in universal algebra.
+  Conjecture generation and counterexample search.
+  Document the experience of AI-assisted research-level formalization.
+  **Deliverable**: mathematics paper with AI-assisted formal proofs.

### Phase 4 — Routine Proof Completion Model (stretch)

+  Train a local 7B model (QLoRA) on successful proof completions collected during
   Phases 1--3.
+  Handle predictable proof obligations locally, without frontier model API calls.
+  **Deliverable**: evaluation of local-only vs. hybrid vs. frontier-only proving.

Each phase produces a usable tool and a publishable result.

---

## 9. Research Orientation

This project is grounded in three *testable* hypotheses.

+  **H1**.  Agda's term-level proofs provide richer, more direct signals for
   AI-assisted proof search than tactic-level representations.
   *Testable:*  compare proof completion rates using structural (term-level)
   retrieval vs. text-level retrieval, on matched proof obligations.

+  **H2**.  Cubical Agda enables AI reasoning about equality, transport, and quotient
   constructions that is not possible in systems where these features are axiomatic.
   *Testable:*  identify proof tasks that require computational univalence or HITs and
   measure whether AI agents can handle them.

+  **H3**.  A hybrid architecture combining a frontier LLM (for reasoning) with
   locally-trained specialist models (for retrieval and ranking) outperforms either
   component alone on Agda proof completion tasks.
   *Testable:*  compare success rates across configurations---frontier-only,
   local-only, and hybrid---on a fixed benchmark of proof obligations.

All three hypotheses may be wrong.  But they are specific enough to be investigated,
and the infrastructure we build is useful regardless of the outcome.

---

## 10. Relation to Prior and Concurrent Work

This project builds directly on the following:

+  **Kogkalidis, Melkonian & Bernardy (2024)**: their structural representations and
   premise selection model (QUILL) are a natural retrieval backend for our system.
   Their AGDA2TRAIN extraction tool complements our definition-level extractor.  A
   collaboration combining AgdaJang + agda-mcp with AGDA2TRAIN + QUILL is a key
   strategic goal.
+  **Numina-Lean-Agent (Liu et al., 2026)**: our architecture mirrors theirs (general
   agent + MCP + proof assistant), adapted for Agda, and extended with
   structure-aware retrieval and local specialist models that Lean tools lack.
+  **LeanDojo (Yang et al., 2023)**: AgdaJang serves the same role for Agda that
   LeanDojo serves for Lean.
+  **agda-algebras (DeMeo & Carette)** + **agda-categories (Carette)**: our primary
   test corpora and the mathematical domain driving design decisions.

We aim to complement, not duplicate, the Lean ecosystem.  Where the Lean tools
optimize for breadth and scale, we optimize for depth in domains where Agda's type
theory foundations matter.
