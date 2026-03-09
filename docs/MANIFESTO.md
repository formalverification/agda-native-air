<!-- File: MANIFESTO.md -->

# Toward an Agda-Native AI Reasoning Environment

*A manifesto for agda-native (v2.2)*

**The Project in One Sentence**. *A research program for building the missing
interaction, retrieval, and evaluation infrastructure that allows modern AI agents to
reason and interface effectively with Agda.*

## 1. Motivation

AI-assisted formal theorem proving is moving quickly.  In the Lean ecosystem, the
most successful recent systems are not just standalone theorem provers; they are
**agentic environments** in which a strong language model interacts with the prover
through a programmatic interface, consults retrieval tools, proposes candidate proof
steps, and relies on the prover itself as the final oracle of correctness.

**Agda has no equivalent tooling.**  Despite having some unique technical
advantages---proof terms rather than tactic scripts, a mature ecosystem for
constructive and homotopy-type-theoretic mathematics, and native cubical type
theory---Agda is practially invisible in the current AI-for-math landscape.  If this
gap is not closed, the language risks irrelevance precisely when formal methods are
receiving unprecedented attention and investment.

This project builds the **missing interaction layer** between frontier AI models and
the Agda proof assistant, augmented by **small, locally-trained models** for
domain-specific tasks where specialized knowledge outperforms general reasoning.  The
goal is to create an environment in which any sufficiently capable LLM can reason
effectively with Agda---exploiting its unique type-theoretic features rather than
working around them---while local models handle retrieval, ranking, and routine proof
obligations cheaply and privately.

Our starting point is the following pair of observations:

1.  **Formal mathematics is not just text**.  It is structured, typed, elaborated,
    and executable.
2.  **Agda is not just another proof assistant**.  Its proof terms, reflection
    facilities, constructive foundations, and cubical mode make it a particularly
    interesting platform for research on machine-assisted reasoning.

Our goal is therefore not merely to bolt autocomplete onto Agda, nor to chase
benchmark numbers for their own sake. It is to build an **Agda-native reasoning
environment** in which frontier models, local specialist models, and Agda itself
cooperate productively.

The long-range dream remains ambitious---an AI system that can help mathematicians
learn from formal corpora, extend formal libraries, and participate meaningfully in
mathematical discovery---but the near-term path is sharper and more grounded: build
the interaction layer, the retrieval layer, and the evaluation layer that make such
systems possible for Agda.

---

## 2. The Architectural Vision: Agda-Native AI Reasoning Environment

The system has five components.

+  Interaction layer: `agda-dojang`
+  Bridge layer: `agda-mcp` 
+  Extraction layer: `agda-strux` structured Agda corpus extraction
+  Intelligence layer: retrieval + reasoning
+  Local specialized models

The first four layers are independently useful; the fifth component is a performance
and autonomy enhancement that becomes viable as the system matures.

### 2.1 Interaction Layer: `agda-dojang`

*AgdaDojang provides programmatic access to Agda's proof engine.*

+  **Goal inspection**.  Query the type of a hole, its local context, and available
   definitions.
+  **Hole filling**.  Propose a candidate term for a hole and receive type-checker
   feedback (success, error with location and message).
+  **Iterative refinement**.  Fill a hole partially (introducing new sub-holes) and
   continue interacting under Agda's supervision.
+  **Module-level operations**. Load files, check imports, inspect dependency graphs.

(AgdaDojang is the Agda analog of LeanDojo for Lean.)

This is the foundation on which all AI interaction is built.  Intentionally small,
explicit, and inspectable, it is not a giant tactic language; it merely exposes a
**learnable, debuggable action space** for humans and machines.

### 2.2 Bridge Layer: `agda-mcp`

*`agda-mcp` is an MCP server wrapping `agda-dojang`; it exposes Agda interaction to
any MCP-compatible coding agent (Claude Code, Codex CLI, Cursor, etc.).*

The **model context protocol** (MPC) layer is the bridge that lets modern
coding agents interact with Agda through standard tool calls rather than fragile
screen-scraping or ad hoc prompting.

The server provides

+  **proof state tools**: get goal/context, fill hole, check file, get diagnostics;
+  **search/retrieval tools**: find definitions by type signature, search the corpus
   by name or structure, retrieve relevant lemmas for a given goal;
+  **context tools**: get file contents, navigate module and depdency structure,
   inspect the dependency graph.

This is the thinnest layer; it merely translates MCP requests into AgdaDojang calls
and formats responses for the agent.  We do not want a monolithic bespoke system when
a narrow, clean protocol layer will do.

### 2.3 Extraction Layer: `agda-strux` structured Agda corpus extraction

*A useful reasoning environment needs more than an interaction loop: it needs data and
memory.*

We extract a structured corpus from Agda libraries using Agda as a semantic oracle.
The resulting data include

+  theorem and definition statements,
+  proof terms when present,
+  dependency information,
+  structural representations of types and terms,
+  derived graph-like views for retrieval and analysis.

This corpus supports three distinct activities:

1. **retrieval** of relevant definitions, lemmas, and proof patterns,
2. **evaluation** on curated proof obligations and fixtures,
3. **training** of narrow, local models for specialized subproblems.

The extraction layer is a reusable research artifact in its own right.

### 2.4 Intelligence Layer: retrieval + reasoning

The primary reasoning agent is a frontier LLM (not a custom model).  Its
effectiveness depends on three main factors.

+  **Retrieval quality**.  Given a proof goal, which lemmas, definitions, and
   proof patterns from the corpus are most relevant?  This is where structure-aware
   representations (Kogkalidis et al.) provide an advantage over naive text matching.
+  **Proof strategy**:  decomposing a complex goal into sub-goals, choosing between
   direct construction, case analysis, induction, transport, etc.
+  **Error interpretation**: understanding Agda's type-checker feedback and using it
   to refine the current attempt.

We do not build or train our own frontier models.  We build the environment that makes
such models effective for formal verification work in Agda.

### 2.5 Local Specialist Layer: Domain-Specific Models

We do not expect a small local model to replace a frontier model for open-ended
mathematical reasoning.  We do expect that, for well-defined, narrow tasks, small
locally-trained models can outperform frontier LLMs---and they run cheaply,
privately, and without network dependency.

This layer is **optional**; the system works end-to-end with only Layers 2.1--2.4,
but local models improve performance, reduce API costs, and enable offline use.

Some examples of the first local models we plan to develop and train are the following:

1.  **Premise selection**.  Given a goal type, rank which library lemmas are most
    likely relevant; this is a classification/ranking task---exactly the kind of
    narrow problem where domain-specific training data and a small architecture
    (cf. QUILL) beat general-purpose models.

2.  **Type-aware embeddings and semantic search**.  A small encoder producing vector
    representations where semantically similar Agda definitions are close in
    embedding space; powers fast approximate search in the retrieval layer.

3.  **Proof-term ranker**.  Given several candidate proof terms (proposed by the
    frontier model), quickly rank them by likelihood of type-checking---a cheap
    filter that reduces the number of expensive Agda invocations.

4.  **Routine proof completer**.  A fine-tuned 7B model (QLoRA) that handles
    predictable proof obligations (e.g., showing a construction preserves a
    property) without calling the frontier model; viable once sufficient training
    data has been collected from the propose–check–refine loop.

These models are **tools in the MCP server's toolkit**---called by the agent when
useful, not replacements for the agent's reasoning.

This hybrid architecture matters for the following practical and scientific reasons:

+  It reduces API dependence,
+  enables some degree of private and local use,
+  makes use of modest hardware such as a Jetson-class device, and
+  lets us ask sharper research questions about what should be learned locally
   and what should be delegated to a frontier agent.

**Potential target hardware**: NVIDIA Jetson AGX Orin 64GB, supporting QLoRA
fine-tuning up to ~13B and quantized inference up to ~30B parameters.  For
specialized tasks (ranking, embeddings), 1B--3B models are likely sufficient.


---

## 3. Why Agda?

This project is about building the environment that makes sense **for Agda**, and
using Agda’s strengths to investigate research questions that are harder to pose
elsewhere.

We do not claim that Agda should displace Lean for all use cases.  Lean's ecosystem
breadth, tactic automation, and community momentum make it a natural choice for many
projects.  But Agda offers specific, concrete advantages that matter for AI research
on formal reasoning---advantages that are not merely aesthetic.

### 3.1 Proof Terms as First-Class Data

*In Agda, the proof term is not hidden behind a tactic script. It is the proof.*

In Lean and Rocq, proofs are typically written as tactic scripts---imperative
sequences whose meaning depends on the prover's internal state at each step.  The
underlying proof terms exist but are secondary artifacts.  In Agda, the proof term
*is* the proof.  **There is no indirection layer.**

For AI, this distinction is significant.

+  The dependency structure of a proof is directly visible in the syntax.
+  Proof search is equivalent to program synthesis in a dependently typed
   language---a well-studied problem with clear formal semantics.
+  Both frontier models (retrieving from Agda proofs as context) and local models
   (trained on Agda proof terms) work with a **direct representation of logical
   structure**, not an intermediate control language whose semantics is opaque without
   replaying the elaborator.

The Kogkalidis et al. work demonstrates this concretely: their structure-aware neural
architecture for premise selection was possible precisely because Agda proofs are
terms with explicit, inspectable structure.  A locally-trained premise selection model
can exploit this structure in ways that are unavailable for tactic-based systems.

This does not mean tactic systems are uninteresting or unusable. It means Agda offers
a distinctly direct representation of proof structure.


### 3.2 Cubical Type Theory: Computational Equality

*Cubical Agda gives computational content to ideas that are often treated
axiomatically elsewhere.*

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

For our purposes, it presents a serious opportunity for AI-for-proof research,
especially in areas where equality reasoning is central.

### 3.3 Constructive Foundations for Universal Algebra

*Agda's constructive foundations make formal objects and existence proofs
computationally meaningful.*

For the specific mathematical domains that originally motivated our work (e.g.,
universal algebra, lattice theory, category theory, homotopy type theory, as well as
computability and computational complexity), Agda offers

+  **universe-polymorphic dependent records** that naturally express algebraic
   signatures, algebras, homomorphisms, and congruences;
+  a constructive setting where existence proofs are programs, making formalized
   constructions directly executable;
+  the existing **agda-algebras** and **agda-categories** libraries, which already
   formalize substantial portions of universal algebra and category theory in this
   style.

For this project, and for mathematics research in general, Agda is not just a proving
backend; it is a mathematical medium.


---


## 4. Structured Corpus Extraction

The starting point for retrieval (and for local model training and evaluation) is a
**structured corpus** extracted from Agda libraries.

The extraction tool we are developing (`agda-strux`) uses Agda as a Haskell library
to produce JSONL records containing five main features.

+  **Identity**: qualified name, module, source location.
+  **Statement**: the type, as both a human-readable string and a structural AST with
   version tag.
+  **Proof body**: the term (when present), with a flag indicating whether the
   definition has computational content.
+  **Dependencies**: references from the type and body, enabling dependency graph
   construction.
+  **Derived views** (optional): port/wire decompositions, interface signatures, edge
   lists for graph experiments.

The corpus serves three distinct purposes.

1.  **Retrieval**.  The MCP server's search tools query a structured index built from
    canonical JSONL rows.  This is the primary consumer.
2.  **Specialized training**.  Premise selection, embedding, and ranking models are
    trained on corpus-derived datasets.  These are narrow tasks---not general
    reasoning.
3.  **Evaluation**.  Measuring system performance requires a catalogue of proof
    obligations with known solutions.

### 4.1 Relationship to Agda2Train

Our `agda-strux` extractor and the Kogkalidis et al. Agda2Train tool are complementary.

+  `agda2train` captures **sub-term-level proof states**---many interaction snapshots per
   definition, recording the full typing context at each point.  This data is optimized
   for training neural proof-step predictors (like QUILL).

+  `agda-strux` captures **definition-level structural summaries**---one compact,
   human-readable row per definition, optimized for retrieval, graph construction, and
   as context that can be included in an LLM prompt.

A combined system could use Agda2Train's output to train premise selection models and our
output to power the retrieval and search tools in the MCP server.


---

## 5. The Architectural Principle

The central principle of the project is simple.

> *Agda remains the final arbiter of correctness.*

Everything else is a supporting actor.

+  Frontier models suggest strategies and candidates.
+  Extraction and retrieval surfaces context.
+  Local specialist models rank, filter, or complete routine tasks.
+  External tools may help search for examples or counterexamples.

But, at the end of the day, *Agda checks the result*.

This gives the project scientific discipline.  It lets us experiment aggressively
without sacrificing soundness.


---

## 6. The Near-Term Deliverable

The near-term goal is a credible, publishable Agda-native reasoning environment with

+  a working interaction layer (`agda-dojang`),
+  a standard mcp bridge for agent access (`agda-mcp`),
+  retrieval over a structured Agda corpus (`agda-strux` + planned search/retrieval tool),
+  deterministic evaluation on committed fixtures,
+  some compelling end-to-end demonstrations.

That is already valuable and would give the Agda community something it currently
lacks---a serious foundation on which both tool builders and mathematicians can
experiment.

---

## 7. The Long-Term Vision

This project remains ambitious and the long-term vision is unchanged.  Its ambition,
however, is now better sequenced.

We are not trying to jump directly from corpus extraction to a fully autonomous AI
mathematician.  Instead we are building up the layers that make serious progress
plausible: extraction, interaction, retrieval, evaluation, and then selective
learning where it is justified.

We still care about systems that can

+  learn a mathematical specialty from formal corpora,
+  reason about new claims,
+  propose proof strategies,
+  detect when counterexamples are needed,
+  suggest useful intermediate lemmas,
+  and eventually generate conjectures worth exploring,

but we do not treat all of those as immediate engineering deliverables.  Instead, we
treat them as the horizon toward which the infrastructure points.  The environment
comes first.  More autonomous mathematical behavior comes later.


---

## 8. Target Use Cases

### 8.1 Interactive Proof Assistance

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

### 8.2 Library Development Assistance

For building up formalization libraries (e.g., extending agda-algebras,
agda-categories, etc.).

+  Filling routine proof obligations (e.g., show a construction preserves a property).
+  Suggesting missing definitions or lemmas based on the dependency graph.
+  Detecting opportunities for generalization or refactoring.

### 8.3 Research-level Mathematics

In the longer run, the system should support working mathematicians who use Agda.

+  **Formal-proof-from-sketch**.  The user provides an informal argument, the agent
   attempts to formalize each step.
+  **Conjecture exploration**.  Given a set of results, suggest plausible extensions
   and attempt to prove or refute them.
+  **Counterexample search**.  For a claimed property, search for structures that
   violate it (using computational content of constructive proofs, or external tools
   like GAP, Mace4, or SMT solvers).
+  **Document AI-assisted formalization workflows**.

(This is particularly important for the motivating mathematical programs behind the
project, including universal algebra and the finite lattice representation problem.)

---

## 9. Research Hypotheses

The project is grounded in several hypotheses that are specific enough to test.

### H1. Structural representations of Agda proofs and types improve retrieval and proof assistance.

Compare text-based retrieval with structure-aware retrieval on matched proof obligations.

### H2. Agda’s proof terms and cubical features expose forms of semantic feedback that are especially useful for AI-assisted reasoning.

Evaluate this on tasks involving equality, transport, and quotient-like constructions.

### H3. A hybrid architecture outperforms either extreme.

Compare three modes:

* frontier-model-only,
* local-model-only,
* and hybrid frontier + local specialist models + Agda.

### H4. Tooling matters.

A good interaction layer and evaluation harness can be as important as model choice.

This is perhaps the most pragmatic hypothesis of all: before training a better reasoner, we may need to build a better laboratory.



## 9. Research Orientation

This project is grounded in several *testable* hypotheses.

+  **H1: Agda types and proofs improve retrieval and proof assistance.**

   Agda proof terms provide richer, more direct signals for AI-assisted proof
   search than tactic proofs.

   *Test*.  Compare proof completion rates using structural (term-level)
   retrieval vs. text-level retrieval, on matched proof obligations.

+  **H2: Agda's semantics are especially useful for AI-assisted reasoning.**

   Cubical Agda enables AI reasoning about equality, transport, and quotient
   constructions that is not possible in systems where these features are axiomatic.

   *Test*.  Identify proof tasks involving equality, transport, and quotient-like
   constructions and measure whether AI agents can handle them.

+  **H3: A hybrid architecture outperforms either extreme.**

   A hybrid architecture combining a frontier LLM (for reasoning) with
   locally-trained specialist models (for retrieval, ranking, and small or special
   proof obligations) outperforms either component alone on Agda proof completion
   tasks.

   *Test*.  Compare success rates across configurations---frontier-model-only,
   local-model-only, and hybrid frontier + local specialist model---on a fixed
   benchmark of proof obligations.

+  **H4: Tooling matters.**

   A good interaction layer and evaluation harness can be as important as model choice.

   This is perhaps the most pragmatic hypothesis of all: before training a better
   reasoner, we need to build a better laboratory.

All of these hypotheses may be wrong, but they are specific enough to be investigated,
and the infrastructure we build will be useful regardless of the outcome.



---

## 10. What This Project Is Not

This project is **not**

+  **a general-purpose prover model**.  We do not train an LLM to do open-ended
   mathematical reasoning.  The frontier model handles that.  We *do* train small,
   local models for narrow tasks (premise selection, ranking, embeddings, routine
   completion) where domain-specific training outperforms general reasoning.
+  **a Lean competitor**.  We target domains where Agda's type theory provides
   genuine advantages.  We do not target competition math or large-scale
   formalizations in classical logic.
+  **a finished product**.  This is a research program with a prototype.  The goal
   is to demonstrate feasibility, produce interesting/publishable results, and provide
   infrastructure for the Agda community.


---

## 11. Relation to Prior and Concurrent Work

This project is informed by, and intended to complement, several lines of existing work.

+  **Kogkalidis, Melkonian & Bernardy (2024)**: their structure-aware representations
   and premise selection model (QUILL) are a natural retrieval backend for our system.
   Their AGDA2TRAIN extraction tool complements our definition-level extractor.  Their
   work demonstrates that Agda-specific machine learning is both possible and
   scientifically interesting and a collaboration combining AgdaDojang + agda-mcp
   with AGDA2TRAIN + QUILL is a key strategic goal.
+  **Numina-Lean-Agent (Liu et al., 2026)**: our architecture mirrors theirs (general
   agent + MCP + proof assistant), adapted for Agda, and extended with
   structure-aware retrieval and local specialist models that Lean tools lack.
+  **LeanDojo (Yang et al., 2023)**: AgdaDojang serves the same role for Agda that
   LeanDojo serves for Lean.
+  **agda-algebras (DeMeo & Carette)** + **agda-categories (Carette)**: our primary
   test corpora and the mathematical domain driving design decisions.
+  Within this repository, the existing extraction tool `agda-strux`, deterministic
   proof-completion evaluator, and `agda-dojang` macros already point toward an
   environment-first architecture.

Our aim is not to duplicate the Lean ecosystem.  It is to ensure that Agda has its
own serious path into the era of AI-assisted formal reasoning.  Where the Lean tools
optimize for breadth and scale, we optimize for depth in domains where Agda's type
theory foundations matter.

---

## 12. The Invitation

We want this project to become a home for several kinds of contributors.

+  proof-assistant implementers,
+  Agda library authors,
+  machine learning researchers,
+  mathematically sophisticated users,
+  and collaborators interested in constructive, categorical, algebraic, or cubical mathematics.

The repository should therefore be judged not only by what it automates today, but by
whether it gives others a clear and welcoming platform on which to build.
