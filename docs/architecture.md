<!-- File: agda-native-air/docs/architecture.md -->

# Architecture — Agda-Native AI Reasoning Environment

This document describes the high-level architecture of the `agda-native-air`
system: the components, which layer each one belongs to, how data flows between
them, and what is implemented today versus planned.

For the vision and rationale see [`MANIFESTO.md`](MANIFESTO.md); for the full
plan and milestone schedule see [`PLAN.md`](PLAN.md) and
[`roadmap.md`](roadmap.md).

---

## Overview

The system connects a frontier AI agent to the Agda type-checker through a small
stack of purpose-built layers.  The agent supplies strategy and reasoning; Agda
is the oracle that decides what is actually correct; the layers in between let the
agent inspect proof state, propose terms, and retrieve relevant definitions.

```
  ┌────────────────────────────────────────────────┐
  │  User / editor  (Emacs agda-mode, VS Code, …)  │
  └───────────────────────┬────────────────────────┘
                          ▼
  ┌────────────────────────────────────────────────┐
  │  Frontier LLM agent  (Claude Code, Codex, …)   │  strategy, planning,
  │                                                │  error interpretation
  └───────────────────────┬────────────────────────┘
                          │  MCP  (JSON-RPC over stdio)
                          ▼
  ┌────────────────────────────────────────────────┐     ┌────────────────────────────┐
  │  agda-mcp   — Bridge layer                     │◀────│  Retrieval corpus          │
  │  Haskell MCP server                            │ srch│  agda-strux → strux-driver │
  │  proof-state tools + corpus search tools       │     └────────────────────────────┘
  └───────────────────────┬────────────────────────┘
                          │  injects AgdaDojang macros and runs the agda binary
                          │  (v0: one subprocess per call)
                          ▼
  ┌────────────────────────────────────────────────┐
  │  agda-dojang  — Interaction layer              │  reportGoalCtx / reflection
  │  repo-local Agda library + Python harness      │  macros on the library path
  └───────────────────────┬────────────────────────┘
                          ▼
  ┌────────────────────────────────────────────────┐
  │  Agda type-checker  — the oracle               │
  └────────────────────────────────────────────────┘

  Optional (the system runs end-to-end without these):
  ┌────────────────────────────────────────────────┐
  │  Local specialist models  (GPU / Jetson)       │  premise selection, type-aware
  │  wired into agda-mcp as extra tools            │  embeddings, proof-term ranking,
  │                                                │  routine completion
  └────────────────────────────────────────────────┘
```

---

## Key design property: works without local models

The system works end-to-end with just three moving parts: `agda-dojang`,
`agda-mcp`, and a frontier LLM agent.  Local specialist models are **optional
accelerators**, not prerequisites — they can improve retrieval quality and proof
success, reduce frontier-API costs, and enable offline or low-connectivity use,
but nothing in the core loop depends on them.

This is a deliberate choice (see [`MANIFESTO.md`](MANIFESTO.md)): the primary
reasoning agent is always a frontier model, and the project builds the
*environment* around it rather than trying to replace it.  It keeps the baseline
reproducible on any machine — no GPU required — and lets the local-model work in
Milestones 2 and 4 proceed as measured, swappable enhancements behind the same
MCP tool interface.

---

## Components

| Component | Layer | Status | Role |
|-----------|-------|--------|------|
| [`agda-mcp`](../agda-mcp/README.md) | Bridge | Implemented (v0.2.0) | MCP server exposing Agda proof-state interaction and corpus search to any MCP-compatible agent. |
| [`agda-dojang`](../agda-dojang/README.md) | Interaction | Implemented | Repo-local Agda library (`AgdaDojang.Debug` reflection macros) plus a Python proof-completion harness; realizes goal inspection, hole filling, and diagnostics. |
| [`agda-strux`](../agda-strux/README.md) | Retrieval (extraction) | Implemented | Haskell backend linking Agda-as-a-library; its `agda-json` executable emits canonical JSONL from Agda source. |
| [`strux-driver`](../strux-driver/README.md) | Retrieval (ETL) | Implemented | Scala driver that runs `agda-json`, validates and transforms its JSONL, and hosts the M1-5 benchmark runner. |
| Local specialist models | Accelerators (optional) | Planned (M2 / M4) | Premise selection, type-aware embeddings, proof-term ranking, and routine completion, surfaced as extra `agda-mcp` tools. |

---

## Layers in detail

### Bridge — `agda-mcp`

+  **Role**.  Translate MCP tool calls from the agent into Agda interactions and
   corpus lookups, and return structured JSON.  It holds no proof-search strategy
   of its own — that belongs to the agent.
+  **Inputs**.  MCP requests (`initialize`, `tools/list`, `tools/call`) over
   JSON-RPC on stdio; an optional agda-strux JSONL corpus via `--corpus`.
+  **Outputs**.  Structured tool results: goal/context, typecheck verdicts,
   diagnostics, and search hits.
+  **Status**.  v0.2.0.  Seven tools: four proof-state (`get_goal`, `fill_hole`,
   `check_file`, `get_diagnostics`) and three corpus-backed search tools
   (`search_by_name`, `search_by_type`, `get_dependencies`, registered only when a
   corpus is supplied).  The v0 implementation shells out to the `agda` binary once
   per call; an Agda-as-a-library API is future work.

### Interaction — `agda-dojang`

+  **Role**.  Define the proof actions the bridge wraps: extract `(goal, context)`
   at a hole, propose a candidate term, and report typecheck feedback.
+  **Inputs**.  An Agda source file with a `{!!}` hole, plus a macro injection
   (`reportGoalCtx`) on the Agda library path.
+  **Outputs**.  Marker blocks (`AGDADOJANG_REQ_BEGIN/END`) parsed from Agda's
   stderr output into structured goal/context data, and typecheck pass/fail results.
+  **Status**.  Implemented, including a deterministic scripted policy backend and
   the proof-completion evaluation harness used by the fixtures and benchmark.

### Retrieval — `agda-strux` + `strux-driver`

+  **Role**.  Turn Agda libraries into a structured, queryable corpus so the bridge
   can search by name, type, and dependency neighborhood without invoking Agda.
+  **Inputs**.  Agda source modules (`agda-strux`); the canonical JSONL those emit
   (`strux-driver`).
+  **Outputs**.  Canonical JSONL rows (name, type, dependencies, kind, …) and
   retrieval-friendly derived views; `strux-driver` also produces benchmark
   reports.
+  **Status**.  Implemented.  See [`representation.md`](representation.md) for the
   JSONL data contract.

### Accelerators — local specialist models

+  **Role**.  Cheap, domain-specific models for narrow subtasks: ranking premises,
   embedding types for nearest-neighbor search, pre-filtering candidate terms, and
   completing routine obligations without a frontier call.
+  **Status**.  Not yet implemented — planned for Milestones 2 and 4.  When added
   they attach to `agda-mcp` as additional tools, so the interface the agent sees
   does not change whether or not they are present.

---

## Data flow

1.  The agent starts `agda-mcp` as a subprocess and exchanges JSON-RPC messages
    over stdio (the MCP protocol).
2.  For a proof-state tool, `agda-mcp` applies the corresponding `agda-dojang`
    action — injecting the `reportGoalCtx` macro or substituting a candidate — and
    runs the `agda` binary with the AgdaDojang library on its path (v0: a fresh
    subprocess per call).
3.  Agda type-checks; `agda-mcp` parses the result (marker block or error) and
    returns structured JSON to the agent.
4.  For a search tool, `agda-mcp` answers from the in-memory corpus index built by
    `agda-strux` + `strux-driver` — no Agda invocation.
5.  When present, local models add ranking/completion tools alongside the above;
    the agent calls them the same way it calls any other tool.

---

## Interaction model

A typical agent session follows a **propose–check–refine** loop.

1.  Agent calls `check_file` to load an Agda file with holes.
2.  Agent calls `get_goal` for a specific hole to inspect its type and context.
3.  Agent reasons about the goal (using its own knowledge, optionally augmented by
    the search tools to find relevant lemmas).
4.  Agent calls `fill_hole` with a candidate term.
5.  If the term typechecks, the hole is filled (possibly creating sub-holes; go to 2).
6.  If the term fails, the agent reads the error, revises, and retries (go to 3).
7.  Repeat until all holes are filled or the agent gives up.

This is the same loop that AgdaDojang's scripted policy backend demo implements,
but driven by a frontier LLM instead of a fixed script.

---

## Language choice: Haskell

`agda-mcp` is implemented in Haskell for three reasons.

1.  Agda itself is implemented in Haskell, so a future version of the server can
    call an AgdaDojang Haskell API directly with no subprocess boundary (the v0
    implementation still shells out to the `agda` binary per tool call).
2.  The extraction backend (`agda-strux`) is already Haskell, giving shared types
    and shared build infrastructure (Cabal / Nix) under one toolchain.
3.  Key collaborators work primarily in Haskell and Agda.

Alternatives considered and rejected: Rust (no Agda-as-library access), Python
(dynamically typed), TypeScript (alien to the team).  The v0 server uses a minimal
hand-written MCP stdio transport covering the three methods it needs
(`initialize`, `tools/list`, `tools/call`) rather than pulling in a third-party
MCP library.

---

## Related documents

+  [`MANIFESTO.md`](MANIFESTO.md) — vision and the frontier-agent-plus-environment thesis.
+  [`PLAN.md`](PLAN.md) — architecture context, milestones, and the local-model plan.
+  [`roadmap.md`](roadmap.md) — GitHub project roadmap with issue-level detail.
+  [`agda-mcp/README.md`](../agda-mcp/README.md) — Bridge layer: tool surface, flags, transport, and module structure.
+  [`representation.md`](representation.md) — data contract for `agda-strux` JSONL output and derived views.
