<!-- File: agda-native-air/docs/architecture.md -->

# Architecture — Agda-Native AI Reasoning Environment

This document describes the high-level architecture of the `agda-native-air`
system: how the major components fit together and which layer each one belongs to.

For the full system context see [`PLAN.md`](PLAN.md) (what/when/how) and
[`roadmap.md`](roadmap.md) (milestone schedule).

---

## Overview

The system is organized around three layers that connect a frontier AI agent to
the Agda type-checker:

```
  ┌──────────────────────────────────┐
  │  Frontier AI Agent               │
  │  (Claude Code / Codex CLI / ...) │
  └────────────┬─────────────────────┘
               │  MCP (JSON-RPC over stdio)
               ▼
  ┌──────────────────────────────────┐
  │  Bridge Layer                    │
  │  agda-mcp  (Haskell MCP server)  │
  └────────────┬─────────────────────┘
               │  Haskell library calls
               ▼
  ┌──────────────────────────────────┐
  │  Interaction Layer               │
  │  agda-dojang                     │
  └────────────┬─────────────────────┘
               │  Agda as a library
               ▼
  ┌──────────────────────────────────┐
  │  Agda type-checker               │
  └──────────────────────────────────┘
```

A fourth component, `agda-strux`, feeds the **Retrieval Layer**: it extracts a
structured corpus from Agda source files so that `agda-mcp`'s search tools can
look up definitions by name or type.

---

## Components

| Component | Layer | Description |
|-----------|-------|-------------|
| [`agda-mcp`](../agda-mcp/README.md) | Bridge | MCP server exposing Agda proof-state interaction to any MCP-compatible agent; see its README for the planned tool surface, language choice, transport, and roadmap. |
| `agda-dojang` | Interaction | Haskell library that wraps Agda-as-a-library; provides goal inspection, hole filling, and diagnostics. |
| `agda-strux` | Retrieval | Extracts JSONL from Agda source; backs the name/type search tools in `agda-mcp`. |
| `strux-driver` | Retrieval | ETL pipeline that converts `agda-strux` JSONL into retrieval-friendly indices. |

---

## Data flow

1. The agent invokes `agda-mcp` as a subprocess and exchanges JSON-RPC messages
   over stdio (MCP protocol).
2. `agda-mcp` translates tool calls into `agda-dojang` API calls and returns
   structured responses.
3. `agda-dojang` drives the Agda type-checker directly (Agda-as-a-library).
4. Search tools in `agda-mcp` are backed by the corpus index built by
   `agda-strux` + `strux-driver`.

---

## Related documents

- [`agda-mcp/README.md`](../agda-mcp/README.md) — Bridge layer: MCP tool surface, Haskell rationale, transport, interaction model, directory structure, and roadmap.
- [`docs/representation.md`](representation.md) — Data contract for `agda-strux` JSONL output and derived views.
- [`docs/PLAN.md`](PLAN.md) — Project plan with milestone breakdown and component descriptions.
- [`docs/roadmap.md`](roadmap.md) — GitHub project roadmap with issue-level detail.

