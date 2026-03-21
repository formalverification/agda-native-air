<!-- File: agda-native-air/agda-mcp/README.md -->

# agda-mcp

> **Status: v0 implementation (M1-2).** Four core proof-state tools over stdio transport.

`agda-mcp` is a [Model Context Protocol][MCP] (MCP) server that exposes
[AgdaDojang]'s proof-state interaction to any MCP-compatible coding agent —
Claude Code, Codex CLI, Cursor, or any other tool that speaks MCP.

```
  ┌──────────────────────────────────┐
  │  Frontier AI Agent               │
  │  (Claude Code / Codex CLI / ...) │
  └────────────┬─────────────────────┘
               │
               │  MCP (JSON-RPC over stdio)
               ▼
  ┌──────────────────────────────────┐
  │  agda-mcp                        │  ◄── this component
  │  Haskell MCP server              │
  └────────────┬─────────────────────┘
               │
               │  subprocess calls
               ▼
  ┌──────────────────────────────────┐
  │  Agda type-checker               │
  │  (agda binary + AgdaDojang       │
  │   macros on the library path)    │
  └──────────────────────────────────┘
```

`agda-mcp` translates MCP tool calls into AgdaDojang operations and formats the
responses.  It does not contain proof-search logic, heuristics, or strategy — those
belong to the agent.


---


## Quick Start

### Build

```sh
nix develop .#backend   # required!  (default Nix shell has wrong GHC version)
cd agda-mcp
cabal build
```
### Run

```sh
cabal run agda-mcp -- \
  --agda-flags "-i ../agda-dojang/agda --library-file=../agda-dojang/agda/libraries -l agda-dojang -l standard-library"
```

The server reads JSON-RPC from stdin and writes to stdout.  It will wait for an MCP client to connect.

### Test

```sh
cabal test
```
Pure tests (marker parsing, hole finding) run without Agda.  Integration tests that
call Agda require `nix develop .#backend`.

For Claude Code setup and MCP client configuration, see [Configuring MCP Clients](#configuring-mcp-clients) below.

---

## Tool Surface (v0)

Four core proof-state tools are implemented (Milestone [M1-2]).  Search tools
(`search-by-name`, `search-by-type`, `get-dependencies`) and navigation tools are
planned for M1-3 and beyond; see [roadmap.md](../docs/roadmap.md).

### Core proof-state tools (Milestone 1 — [M1-2])

This is the minimum tooling required for an agent to do interactive proof development.

| Tool | Description |
|------|-------------|
| `get_goal`         | Inspect the goal type and local context at a hole. |
| `fill_hole`        | Substitute a candidate term into a hole and typecheck. |
| `check_file`       | Load/reload an Agda file and return all diagnostics. |
| `get_diagnostics`  | Lightweight summary: error/warning counts, open holes. |



---

## What we've implemented so far

### Module Structure

```
agda-mcp/
├── agda-mcp.cabal
├── README.md
├── app/
│   └── Main.hs                  ← CLI entry point
├── src/
│   └── AgdaMCP/
│       ├── Server.hs            ← MCP stdio transport (JSON-RPC)
│       ├── Types.hs             ← Stable JSON schema types
│       ├── Agda.hs              ← Agda subprocess interaction + marker parsing
│       └── Tools/
│           └── ProofState.hs    ← get_goal, fill_hole, check_file, get_diagnostics
└── test/
    └── Main.hs                  ← Pure + integration tests
```

### Core proof-state tools (Milestone 1)

#### `get_goal`

Given a file path and hole identifier, return the hole's expected type and its local context (bound variables with types); this is the primary "what am I trying to prove?" query.

**Input**.  
```json
{
  "filePath": "/path/to/Fixture01.agda",
  "holeIndex": 0
}
```

**Output**.  
```json
{
  "goal": "A",
  "context": [
    {"name": "x", "type": "A", "visibility": "visible", "index": 0},
    {"name": "A", "type": "Set₀", "visibility": "hidden", "index": 1}
  ],
  "module": "Fixture01.agda"
}
```

**How it works**.  Injects the `reportGoalCtx` macro into the hole, runs Agda, and parses the `AGDADOJANG_REQ_BEGIN/END` marker block from stderr.


#### `fill_hole`

Submit a candidate term for a hole and receive typecheck feedback: success (hole filled, possibly generating new sub-holes) or failure (error message with location).

**Input**.  
```json
{
  "filePath": "/path/to/Fixture01.agda",
  "holeIndex": 0,
  "candidate": "x"
}
```
**Output (success)**.  
```json
{
  "status": "ok",
  "candidate": "x",
  "remainingHoles": 1
}
```

**Output (failure)**.  
```json
{
  "status": "type_error",
  "candidate": "tt",
  "message": "A !=< ⊤ when checking that the expression tt has type A"
}
```

#### `check_file`

Load or reload an Agda file and return all diagnostics — errors, warnings, unsolved metas, and remaining holes.

**Input**.  
```json
{
  "filePath": "/path/to/Fixture01.agda"
}
```

**Output**.  
```json
{
  "success": false,
  "diagnostics": [
    {"severity": "error", "message": "...", "line": 7}
  ],
  "holesCount": 3
}
```

#### `get_diagnostics`

Retrieve the current diagnostic state without reloading: error count, warning count, list of open holes with their types.

**Input**.  
```json
{
  "filePath": "/path/to/Fixture01.agda"
}
```

**Output**.  
```json
{
  "filePath": "/path/to/Fixture01.agda",
  "errors": 0,
  "warnings": 1,
  "holes": [{"goal": "?", "context": []}]
}
 ```

---


## Transport

The initial implementation will use **stdio** transport (JSON-RPC over stdin/stdout).
This is the standard for local MCP servers invoked by coding agents and requires no
network configuration.

HTTP/SSE transport may be added later for remote or multi-session scenarios, but is
not planned for Milestone 1.


---


## Related Components

| Component | Role | Link |
|-----------|------|------|
| **agda-dojang**  | Interaction layer — provides the proof actions that `agda-mcp` wraps | [`agda-dojang/`](../agda-dojang/)   |
| **agda-strux**   | Extraction layer — produces the corpus data that backs search tools  | [`agda-strux/`](../agda-strux/)     |
| **strux-driver** | ETL layer — processes extracted data into retrieval-friendly formats | [`strux-driver/`](../strux-driver/) |


See [roadmap.md](../docs/roadmap.md) for milestones and issue tracking.

---

## Example Tests

``` sh
cabal run agda-mcp -- \
  --agda-flags "-i ../agda-dojang/agda --library-file=../agda-dojang/agda/libraries -l agda-dojang -l standard-library" \
  < test/resources/mcp-test-input.jsonl
```

> **Note:** The test input uses paths relative to `agda-mcp/` (e.g. `../agda-dojang/...`).
> Run from the `agda-mcp/` directory, or adjust paths if running from elsewhere.

---

## Configuring MCP Clients

### Claude Code / Claude Desktop

Add to your MCP configuration (`claude_desktop_config.json` or project `.mcp.json`):

```json
{
  "mcpServers": {
    "agda": {
      "command": "cabal",
      "args": [
        "run", "-v0", "agda-mcp", "--",
        "--agda-flags", "-i agda-dojang/agda --library-file=agda-dojang/agda/libraries -l agda-dojang -l standard-library"
      ],
      "cwd": "/path/to/agda-native-air"
    }
  }
}
```

### Cursor / Codex CLI

Similar configuration — point the MCP client at the `agda-mcp` binary with the appropriate `--agda-flags`.

---

## Architecture Notes

### v0: Subprocess-based

The v0 implementation calls the `agda` binary as a subprocess for each
tool invocation.  This mirrors how `agda-dojang`'s Python tooling
(`agent_bridge.py`) works and reuses the established marker protocol
(`AGDADOJANG_REQ_BEGIN/END`).

**Advantages:** simple, decoupled from Agda's GHC version, reuses all
existing AgdaDojang macros without modification.

**Limitations:** each tool call spawns a new Agda process (cold
typechecking, no persistent state).  This is acceptable for the v0 demo
and benchmark fixtures, but will need optimization for larger files.


### Future: Agda-as-a-library

The long-term plan is to use Agda as a Haskell library (persistent
interaction state, warm caches, sub-second latency).  This requires
AgdaDojang to expose a Haskell API, which is tracked in the roadmap.


### Interaction model

A typical agent session follows a propose-check-refine loop:

> `check_file` → `get_goal` → reason about the goal → `fill_hole` → read feedback → revise or advance.

This is the same loop that AgdaDojang's scripted policy backend demo implements, but
driven by a frontier LLM instead of a fixed script.


### MCP Transport

We implement a minimal MCP stdio transport (~200 lines in `AgdaMCP.Server`) rather
than using the `mcp-server` Hackage library, because that library requires `base >=
4.20` (GHC 9.10+) and the project pins GHC 9.8.2 for Agda compatibility.  The
transport handles the three methods we need: `initialize`, `tools/list`, `tools/call`.

---

## Related Documents

- [`agda-dojang/README.md`](../agda-dojang/README.md) — Action space reference (the macros this server wraps).
- [`docs/policy_contract.md`](../docs/policy_contract.md) — Policy backend JSON contract (compatible with our tool schemas).
- [`docs/architecture.md`](../docs/architecture.md) — System architecture overview.


## References

- [Model Context Protocol specification (2025-11-25)][MCP-spec]
- [MCP documentation and guides][MCP]
- [Haskell `mcp-server` library on Hackage][hackage-mcp-server]
- [Haskell `mcp` library on Hackage][hackage-mcp]
- [Rust MCP SDK (`rmcp`)][rust-sdk] — considered but not chosen; see above
- [MANIFESTO.md §2.2 — Bridge Layer][MANIFESTO]
- [PLAN.md — project roadmap][PLAN]


[MCP]: https://modelcontextprotocol.io/
[MCP-spec]: https://modelcontextprotocol.io/specification/2025-11-25
[hackage-mcp]: https://hackage.haskell.org/package/mcp
[hackage-mcp-server]: https://hackage.haskell.org/package/mcp-server
[rust-sdk]: https://github.com/modelcontextprotocol/rust-sdk
[AgdaDojang]: ../agda-dojang/
[MANIFESTO]: ../MANIFESTO.md
[PLAN]: ../docs/PLAN.md
[M1-2]: https://github.com/formalverification/agda-native-air/issues/10
