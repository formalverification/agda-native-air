# Toward an Agda-Native AI Reasoning Environment

*MANIFESTO for agda-ai-prover (v2.0)*

## 1. Motivation

AI-assisted formal theorem proving is advancing rapidly.  Systems like AlphaProof,
DeepSeek-Prover-V2, Goedel-Prover-V2, Aristotle, and Numina-Lean-Agent have achieved
gold-medal performance on the International Mathematical Olympiad and solved all
twelve 2025 Putnam problems.  All of these systems target the **Lean 4** proof
assistant language.

The emergence of a winning paradigm is clear: **general-purpose coding agents**
(Claude Code, Codex CLI) interact with proof assistants through programmatic
interfaces (MCP servers, LSP wrappers), using the type-checker as a correctness
oracle in a propose–check–refine loop.  Specialized prover models are giving way to
frontier LLMs augmented with retrieval tools and proof-assistant feedback.

**Agda has no equivalent tooling.**  Despite having some unique technical
advantages---proof terms rather than tactic scripts, a mature ecosystem for
constructive and homotopy-type-theoretic mathematics, and native cubical type
theory---Agda is invisible in the current AI-for-math landscape.  If this gap is not
closed, Agda risks irrelevance precisely when formal methods are receiving
unprecedented attention and investment.

This project builds the **missing interaction layer** between frontier AI models and
the Agda proof assistant.  The goal is not to train a custom prover model, but to
create an environment in which any sufficiently capable LLM can reason effectively
with Agda---exploiting its unique type-theoretic features rather than working around
them.

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
   proofs with sub-type-level resolution; a structure-aware neural architecture for
   premise selection based on structural (not nominal) principles.
+  **MLFMF** (Bauer, Petković & Todorovski, NeurIPS 2023): benchmark datasets for
   Agda (stdlib, agda-unimath, TypeTopology) and Lean.
+  **This project (agda-native-air)**: a Haskell-based structured data extractor and
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

### 3.1 Proof Terms as First-Class Training Data

In Lean, proofs are typically written as tactic scripts---imperative sequences whose
meaning depends on the prover's internal state at each step.  The underlying proof
terms exist but are **secondary** artifacts.  In Agda, **the proof term is the
proof**.  There is no indirection layer.

For AI, this difference is significant:

+  The dependency structure of a proof is directly visible in the syntax.
+  Proof search is equivalent to **program synthesis** in a dependently typed
   language---a well-studied problem with clear formal semantics.
+  A model trained on (or retrieving from) Agda proofs works with a **direct
   representation of logical structure**, not an intermediate control language whose
   semantics is opaque without replaying the elaborator.

The Kogkalidis et al. work demonstrates this concretely: their structure-aware neural
architecture for premise selection was possible precisely because Agda proofs are
terms with explicit, inspectable structure.

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

The system has three layers, each independently useful.

### 4.1 Interaction Layer: AgdaJang

AgdaJang provides programmatic access to Agda's proof engine.

+  **Goal inspection**.  Query the type of a hole, its local context, and available
   definitions.
+  **Hole filling**.  Propose a candidate term for a hole and receive type-checker
   feedback (success, error with location and message).
+  **Iterative refinement**.  Fill a hole partially (introducing new sub-holes) and
   continue interacting.
+  **Module-level operations**. Load files, check imports, inspect dependency graphs.

AgdaJang is the Agda analog of LeanDojo for Lean. It is the foundation on which all
AI interaction is built.

### 4.2 Bridge Layer: agda-mcp

An Model Context Protocol (MCP) server that wraps AgdaJang and exposes Agda
interaction to any MCP-compatible coding agent (Claude Code, Codex CLI, Cursor,
etc.).  The server provides

+  **proof state tools**: get goal, fill hole, check file, get diagnostics;
+  **search/retrieval tools**: find definitions by type signature, search the corpus
   by name or structure, retrieve relevant lemmas for a given goal.
+  **context tools**: get file contents, navigate module structure, inspect the
   dependency graph.

This is the thinnest possible layer; it translates MCP requests into AgdaJang calls
and formats responses for the agent.

### 4.3 Intelligence Layer: Retrieval and Reasoning

The agent itself is a frontier LLM (not a custom model). Its effectiveness depends on
three main factors.

+  **Retrieval quality**.  Given a proof goal, which lemmas, definitions, and
   proof patterns from the corpus are most relevant?  This is where structure-aware
   representations (Kogkalidis et al.) provide an advantage over naive text matching.
+  **Proof strategy**:  decomposing a complex goal into sub-goals, choosing between
   direct construction, case analysis, induction, transport, etc.
+  **Error interpretation**: understanding Agda's type-checker feedback and using it
   to refine the current attempt.

*We do not build or train the LLM.  We build the environment that makes it effective.*

---

## 5. Structured Corpus Extraction

The starting point for retrieval (and for any future fine-tuning or evaluation work)
is a **structured corpus** extracted from Agda libraries.

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

The corpus is designed to be a **reusable research artifact**, useful for retrieval,
for training, for graph analysis, and for evaluation benchmarks.

---

## 6. Target Use Cases

### 6.1 Interactive Proof Assistance

Via editor integration (Emacs agda2-mode, VSCode, or a terminal agent).

1.  The user writes a theorem statement with a hole.
2.  The agent (via agda-mcp) inspects the goal, retrieves relevant lemmas, and
    proposes a candidate.
3.  Agda type-checks the candidate; on failure, the agent reads the error and
    refines.
4.  The loop continues until success or the agent reports an obstacle requiring human
    input.

This is the same workflow demonstrated by Numina-Lean-Agent for Lean, but targeting Agda.

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

+  **Not a custom prover model**.  We do not train LLMs.  Frontier models improve
   monthly; our job is to give them the best possible interface to Agda.
+  **Not a Lean competitor**.  We target domains where Agda's type theory provides
   genuine advantages.  We do not target competition math or large-scale
   formalizations in classical logic.
+  **Not a finished product.**  This is a research program with a prototype.  The goal
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

### Phase 2 — Structure-Aware Retrieval (medium-term)

+  Integrate premise selection (structural representations) into the retrieval
   pipeline.
+  Evaluate whether structure-aware retrieval improves proof success rate over naive
   prompting.
+  **Deliverable**: research paper comparing retrieval strategies.

### Phase 3 — Research Mathematics (long-term)

+  Apply the system to formalizing new results in universal algebra.
+  Conjecture generation and counterexample search.
+  Document the experience of AI-assisted research-level formalization.
+  **Deliverable**: mathematics paper with AI-assisted formal proofs.

Each phase produces a usable tool and a publishable result.

---

## 9. Research Orientation

This project is grounded in two *testable* hypotheses.

+  **H1**.  Agda's term-level proofs provide richer, more direct signals for
   AI-assisted proof search than tactic-level representations.

   *This is testable*.  Compare proof completion rates using structural (term-level)
   retrieval vs. text-level retrieval, on matched proof obligations.

+  **H2**.  Cubical Agda enables AI reasoning about equality, transport, and quotient
   constructions that is not possible in systems where these features are axiomatic.

   *This is testable*.  Identify proof tasks that require computational univalence or
   HITs and measure whether AI agents can handle them.

Both hypotheses may be wrong, but they are specific enough to be investigated, and
the infrastructure we build will be useful regardless of the outcome.

---

## 10. Relation to Prior and Concurrent Work

This project builds directly on the following:

+  **Kogkalidis, Melkonian & Bernardy (2024)**: their structural representations and
   premise selection model are a natural retrieval backend for our system.
+  **Numina-Lean-Agent (Liu et al., 2026)**: our architecture mirrors theirs (general
   agent + MCP + proof assistant), adapted for Agda.
+  **LeanDojo (Yang et al., 2023)**: AgdaJang serves the same role for Agda that
   LeanDojo serves for Lean.
+  **agda-algebras (DeMeo & Carette)** + **agda-categories (Carette)**: our primary
   test corpora and the mathematical domain driving design decisions.

We aim to complement, not duplicate, the Lean ecosystem.  Where the Lean tools
optimize for breadth and scale, we optimize for depth in domains where Agda's type
theory foundations matter.

