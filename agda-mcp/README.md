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
nix develop .#backend   # or .#all for the full environment
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
Pure tests (marker parsing, hole finding) run without Agda.  Integration tests that call Agda require `nix develop`.


---
## Tool Surface (v0)

The tools are organized in three groups, corresponding to implementation phases.

### Core proof-state tools (Milestone 1 — [M1-2])

This is the minimum tooling required for an agent to do interactive proof development.

| Tool | Description |
|------|-------------|
| `get_goal`         | Inspect the goal type and local context at a hole. |
| `fill_hole`        | Substitute a candidate term into a hole and typecheck. |
| `check_file`       | Load/reload an Agda file and return all diagnostics. |
| `get_diagnostics`  | Lightweight summary: error/warning counts, open holes. |


### Search and retrieval tools (Milestone 1 — [M1-3])

Basic corpus search, enabling the agent to find relevant definitions.  These are
backed by `agda-strux` output initially; neural premise selection is added in
Milestone 2.

| Tool | Description |
|------|-------------|
| `search-by-name`   | Fuzzy search for definitions by qualified or unqualified name; returns matching definitions with their types, module paths, and source locations. |
| `search-by-type`   | Search for definitions whose type unifies with (or is similar to) a given type expression — essential for finding lemmas that might help discharge a goal. |
| `get-dependencies` | Given a definition name, return its dependency neighborhood: what it depends on (imports, referenced lemmas) and what depends on it (reverse dependencies). |


### Context and navigation tools (future milestones)

These are lower priority and may be added as the system matures.

| Tool | Description |
|------|-------------|
| `get-file-contents`    | Return the source text of an Agda file, optionally with hole markers annotated. |
| `get-module-structure` | List the definitions in a module with their types and kinds (data, record, function, postulate). |
| `get-corpus-stats`     | Summary statistics about the loaded corpus: module count, definition count, hole count. Useful for agent orientation. |


---

## What we've implemented so far

### Core proof-state tools (Milestone 1 — [M1-2])

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
  "newHoles": 1
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

## Language Choice: Haskell

`agda-mcp` will be implemented in **Haskell**.   Our rationale for this choice was
based on a number of factors, including the following considerations.

1.  **Zero-cost Agda integration**.  Agda is implemented in Haskell and can be used
    as a library.  A Haskell MCP server can call AgdaDojang's Haskell API directly —
    no subprocess spawning, no serialization boundaries, no process management.

2.  **Ecosystem coherence**.  The extraction backend (`agda-strux`) is already
    Haskell.  Adding the MCP server in the same language means shared types, shared
    build infrastructure (Cabal/Nix), and a single GHC version to maintain.

3.  **Collaborator alignment**.  Key collaborators on this project work primarily in
    Haskell and Agda.  A Haskell MCP server maximizes collaboration opportunities for
    the people who understand Agda's internals best.

4.  **MCP SDK availability**.  There are now Haskell MCP libraries on Hackage
    ([`mcp`][hackage-mcp], [`mcp-server`][hackage-mcp-server]) supporting the
    MCP 2025-11-25 specification with stdio and HTTP transports.  We are not
    starting from scratch.

5.  **Type safety.**  Haskell's type system provides compile-time guarantees that
    tool schemas, request parsing, and response construction are consistent — a
    meaningful advantage for a protocol server.

### Alternatives considered

We evaluated Rust (official MCP SDK, excellent performance, but no Agda-as-library
access and would introduce a fourth compiled language), Python (fastest prototyping,
but conflicts with our preference for statically typed functional code), and
TypeScript (canonical MCP language, but alien to the team and toolchain).  See
[PLAN.md §2][PLAN] for broader architectural context.

At this point, the existing Haskell MCP libraries are very young; if they prove
inadequate, the fallback is a minimal hand-written JSON-RPC-over-stdio
implementation — the protocol is simple enough that this is feasible.


---

## Transport

The initial implementation will use **stdio** transport (JSON-RPC over stdin/stdout).
This is the standard for local MCP servers invoked by coding agents and requires no
network configuration.

HTTP/SSE transport may be added later for remote or multi-session scenarios, but is
not planned for Milestone 1.


---

## Interaction Model

A typical agent session looks like this:

1. Agent starts `agda-mcp` as a subprocess (configured in the agent's MCP settings).
2. Agent calls `check-file` to load an Agda file with holes.
3. Agent calls `get-goal` for a specific hole to inspect the goal type and context.
4. Agent reasons about the goal (using its own knowledge + optionally
   `search-by-name` / `search-by-type` to find relevant lemmas).
5. Agent calls `fill-hole` with a candidate term.
6. If the term typechecks: the hole is filled (possibly creating sub-holes; go to 3).
7. If the term fails: agent reads the error, revises, and retries (go to 4).
8. Repeat until all holes are filled or the agent gives up.

This is the same propose-check-refine loop that AgdaDojang's scripted policy backend
implements, but driven by a frontier LLM instead of a fixed script.


---


## Directory Structure (planned)

```
agda-mcp/
├── README.md              ← you are here
├── agda-mcp.cabal         ← Cabal package definition
├── src/
│   └── AgdaMCP/
│       ├── Main.hs        ← entry point; stdio transport setup
│       ├── Server.hs      ← MCP server definition; tool registration
│       ├── Tools/
│       │   ├── ProofState.hs   ← get-goal, fill-hole, check-file, get-diagnostics
│       │   └── Search.hs       ← search-by-name, search-by-type, get-dependencies
│       └── Types.hs       ← shared request/response types
└── test/
    └── AgdaMCP/
        └── ...            ← integration tests
```


---


## Related Components

| Component | Role | Link |
|-----------|------|------|
| **agda-dojang**  | Interaction layer — provides the proof actions that `agda-mcp` wraps | [`agda-dojang/`](../agda-dojang/)   |
| **agda-strux**   | Extraction layer — produces the corpus data that backs search tools  | [`agda-strux/`](../agda-strux/)     |
| **strux-driver** | ETL layer — processes extracted data into retrieval-friendly formats | [`strux-driver/`](../strux-driver/) |


---


## Roadmap

| Milestone | What happens for `agda-mcp`                                                                   |
|-----------|-----------------------------------------------------------------------------------------------|
| **M0-7**  | Stub directory, README, planned design                                                        |
| **M1-1**  | AgdaDojang stabilized — prerequisite for wrapping                                             |
| **M1-2**  | Core proof-state tools implemented (`get-goal`, `fill-hole`, `check-file`, `get-diagnostics`) |
| **M1-3**  | Search tools added (`search-by-name`, `search-by-type`, `get-dependencies`)                   |
| **M1-4**  | End-to-end demo: Claude Code solves proof obligations via `agda-mcp`                          |
| **M2-3**  | Corpus-backed retrieval integrated (backed by `agda-strux` output)                            |
| **M2-5**  | Neural premise selection (QUILL-like) available as a retrieval backend                        |


---

## Installing Claude Code

Claude Code is a CLI tool, which is set it up as follows:

1.  Install Claude Code (requires Node.js 18+)

    ```sh
    npm install -g @anthropic-ai/claude-code
    ```

2.  Navigate to the repo root; e.g., `cd agda-native-air`, or wherever you cloned it.
    (That's where the `.mcp.json` file lives.)

3.  Start Claude Code by entering `claude`.

    Claude Code will detect .mcp.json and attempt to start the agda MCP server.

    You may need to approve the MCP server connection when prompted.

4.  Once connected, you can ask Claude Code things like:
    "Use the get_goal tool on agda-dojang/data/fixtures/Fixture01.agda hole 0"
```

---


## Example Tests

``` sh
cabal run agda-mcp -- \
  --agda-flags "-i ../agda-dojang/agda --library-file=../agda-dojang/agda/libraries -l agda-dojang -l standard-library" \
  < test/resources/mcp-test-input.jsonl
```




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
 
### MCP Transport

We implement a minimal MCP stdio transport (~200 lines in `AgdaMCP.Server`)
rather than using the `mcp-server` Hackage library, because that library
requires `base >= 4.20` (GHC 9.10+) and the project pins GHC 9.8.2 for
Agda compatibility.  The transport handles the three methods we need:
`initialize`, `tools/list`, `tools/call`.

## Module Structure

```
agda-mcp/
├── agda-mcp.cabal
├── README.md
├── src/
│   └── AgdaMCP/
│       ├── Main.hs              ← CLI entry point
│       ├── Server.hs            ← MCP stdio transport (JSON-RPC)
│       ├── Types.hs             ← Stable JSON schema types
│       ├── Agda.hs              ← Agda subprocess interaction + marker parsing
│       └── Tools/
│           └── ProofState.hs    ← get_goal, fill_hole, check_file, get_diagnostics
└── test/
    └── Main.hs                  ← Pure + integration tests
```

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
