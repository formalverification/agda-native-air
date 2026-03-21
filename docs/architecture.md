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
| [`agda-dojang`](../agda-dojang/README.md) | Interaction | Haskell library that wraps Agda-as-a-library; provides goal inspection, hole filling, and diagnostics. |
| [`agda-strux`](../agda-strux/README.md) | Retrieval | Extracts JSONL from Agda source; backs the name/type search tools in `agda-mcp`. |
| [`strux-driver`](../strux-driver/README.md) | Retrieval | ETL pipeline that converts `agda-strux` JSONL into retrieval-friendly indices. |

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

## Language choice: Haskell

`agda-mcp` is implemented in Haskell for three reasons.

1.  Agda itself is implemented in Haskell, so the MCP server can call AgdaDojang's
    Haskell API directly with no subprocess boundary;
2.  the extraction backend (`agda-strux`) is already Haskell, giving shared types,
    shared build infrastructure (Cabal/Nix), and a single GHC version;
3.  key collaborators work primarily in Haskell and Agda.

### Alternatives considered and rejected

+  Rust (no Agda-as-library access)
+  Python (dynamically typed)
+  TypeScript (alien to the team).

See [PLAN.md §1](PLAN.md) for broader architectural context.

The v0 implementation uses a minimal hand-written MCP stdio transport rather than the
`mcp-server` Hackage library, which requires GHC 9.10+ while the project pins GHC
9.8.2 for Agda compatibility.

---

## Interaction model

A typical agent session follows a **propose–check–refine** loop.

1.  Agent calls `check_file` to load an Agda file with holes.
2.  Agent calls `get_goal` for a specific hole to inspect its type and context.
3.  Agent reasons about the goal (using its own knowledge, optionally augmented
    by search tools to find relevant lemmas).
4.  Agent calls `fill_hole` with a candidate term.
5.  If the term typechecks, the hole is filled (possibly creating sub-holes; go to 2).
6.  If the term fails, the agent reads the error, revises, and retries (go to 3).
7.  Repeat until all holes are filled or the agent gives up.

This is the same loop that AgdaDojang's scripted policy backend demo implements, but
driven by a frontier LLM instead of a fixed script.

---

## Related documents

- [`agda-mcp/README.md`](../agda-mcp/README.md) — Bridge layer: tool surface, transport, and module structure.
- [`docs/representation.md`](representation.md) — Data contract for `agda-strux` JSONL output and derived views.
- [`docs/PLAN.md`](PLAN.md) — Project plan with milestone breakdown and component descriptions.
- [`docs/roadmap.md`](roadmap.md) — GitHub project roadmap with issue-level detail.

