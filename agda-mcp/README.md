<!-- File: agda-native-air/agda-mcp/README.md -->

# agda-mcp

> **Status: v0.2.0 (M1-3).** Seven tools over stdio transport — four core
> proof-state tools plus three corpus-backed search tools.

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
  --agda-flags "-i ../agda-dojang/agda --library-file=../agda/libraries -l agda-dojang -l standard-library"
```

The server reads JSON-RPC from stdin and writes to stdout.  It will wait for an MCP client to connect.

### Test

```sh
cabal test
```
Pure tests (marker parsing, hole finding) run without Agda.  Integration tests that
call Agda require `nix develop .#backend`.

### Via `make` (from the repo root)

The top-level Makefile wraps the build/test above in the backend Nix shell, so you
do not have to enter it or `cd` first:

```sh
make agda-mcp-smoke   # build + a fast JSON-RPC round-trip sanity check
make agda-mcp-test    # full cabal test (unit + corpus + Agda integration)
make agda-mcp-serve   # launch the server (the same invocation as .mcp.json)
```

Already inside `nix develop .#backend`?  Add `BACKEND_USE_NIX=0` to skip the nested shell (this is what CI does).

For Claude Code setup and MCP client configuration, see [Configuring MCP Clients](#configuring-mcp-clients) below.

---

## Tool Surface

Seven tools are implemented: four core proof-state tools (Milestone [M1-2]) and
three corpus-backed search tools (Milestone [M1-3]).  Navigation tools and neural
premise selection are planned for later milestones; see
[GITHUB_PROJECT.md](../docs/GITHUB_PROJECT.md).

### Core proof-state tools (Milestone 1 — [M1-2])

This is the minimum tooling required for an agent to do interactive proof development.

| Tool | Description |
|------|-------------|
| `get_goal`         | Inspect the goal type and local context at a hole. |
| `fill_hole`        | Substitute a candidate term into a hole and typecheck. |
| `check_file`       | Load/reload an Agda file and return all diagnostics. |
| `get_diagnostics`  | Lightweight summary: error/warning counts, open holes with positions. |

### The hole model (issues #71 and #73)

All four tools share one definition of "hole", implemented in `AgdaMCP.Holes` and kept in sync with what Agda itself reports:

+  Every Agda hole syntax is recognized: `{!!}`, `{! ... !}` (with nesting), and standalone `?` — where `?` counts only as a lexically separate token, so names like `op?` or `_≟_` never match.
+  Tokens inside comments (`--` lines, nested `{- ... -}` blocks), pragmas, string/character literals, and literate prose are never holes.
+  Literate files are recognized by extension — `.lagda` / `.lagda.tex`, `.lagda.md` / `.lagda.typ`, `.lagda.rst`, `.lagda.org`, and `.lagda.tree` — and only their code regions are scanned, following the code-block rules of Agda 2.8.0's own literate preprocessor.
+  `holeIndex` addresses holes in source order under this model, and all reported positions are 1-based (line, col) coordinates in the file as written — literate-file coordinates for literate sources, matching what an editor or Agda's error messages show.

### Corpus-backed search tools (Milestone 1 — [M1-3])

These let the agent discover relevant definitions from an agda-strux JSONL corpus
without calling Agda.  They are registered **only** when the server is started
with `--corpus PATH`; without a corpus, the four core tools above are the whole
surface.

| Tool | Description |
|------|-------------|
| `search_by_name`    | Find definitions whose name matches a substring (case-insensitive). |
| `search_by_type`    | Find definitions whose type signature contains a substring. |
| `get_dependencies`  | Return a definition's dependencies, optionally expanded one hop. |



---

## Command-line options

```
agda-mcp [--agda-bin PATH] [--agda-flags "FLAG1 FLAG2 ..."]
         [--corpus PATH]   [--timeout N] [--verbose]
```

| Flag | Description |
|------|-------------|
| `--agda-bin PATH`    | Path to the `agda` binary (default: `agda` on `PATH`). |
| `--agda-flags "..."` | Space-separated flags passed through to Agda (include paths, `--library-file`, `-l` library names). |
| `--corpus PATH`      | Load an agda-strux JSONL corpus; registers the three search tools. |
| `--timeout N`        | Per-typecheck timeout in seconds (default: 300; `0` means no limit).  Enforced: on expiry the `agda` process group is killed and the tool reports a timeout.  Size it for a *cold* first check — see below. |
| `--verbose`          | Emit debug output to stderr. |
| `--help`             | Print usage and exit. |

### Timeouts, cold calls, and latency

Every tool call spawns a **cold `agda` subprocess**; this server keeps no warm
Agda session and caches nothing itself.  The only warmth available is Agda's own
`.agdai` interface files, which Agda writes on a first check and reuses on later
ones.  So the first call against a large library is expected to be slow — it is
building interfaces for the whole import graph, which for something the size of
agda-algebras is *minutes*, not seconds — while later calls that reuse those
interfaces are far faster.

Size `--timeout` for that cold interface build, not for the warm steady state.
The default is 300 s; the field-test configuration below uses 600 s, which is the
safer choice the first time you point the server at a large library you have
never checked in that worktree.  A bound that is too small does not degrade
gracefully: it aborts the very call that would have built the interfaces, so the
next call starts cold again.

Every proof-state response reports what actually happened:

| Field | Meaning |
|-------|---------|
| `elapsedMs`         | Wall-clock time in the `agda` subprocess, from a monotonic clock. |
| `checkedFromSource` | `true` if Agda re-typechecked the module from source (a `Checking` line was observed — including runs that then failed or were killed mid-check), `false` if it reused `.agdai` interfaces (the run completed successfully in silence, which is Agda's warm signature, or printed `Loading` lines at raised verbosity) — the coarse signal that explains why the same call took three minutes once and 200 ms the next time.  **Omitted** when the run died before producing evidence either way (a startup failure, or a timeout before any output): an absent field means *unknown*, never a guess. |

On expiry the subprocess and its whole process group are killed and reaped —
escalating SIGINT → SIGTERM → SIGKILL group-wide, so no runaway `agda` and no
descendant it spawned is left behind — and the tool reports the timeout in its
own vocabulary: `fill_hole` returns `"status": "timeout"` (*not* `type_error`:
the candidate was never judged) with a message naming the bound, `check_file`
and `get_diagnostics` return `"success": false` with `"timedOut": true` and an
`agda timed out after Ns` error diagnostic, and `get_goal` returns an error
whose text is a JSON object — `{"error": …, "timedOut": true, "elapsedMs": …,
"checkedFromSource": …?}` — naming the bound while preserving the measurements
the killed call still produced.  Files patched in place by `get_goal` and
`fill_hole` are restored byte-for-byte on the timeout path exactly as on every
other path.


---

## What we've implemented so far

### Module Structure

```
agda-mcp/
├── agda-mcp.cabal
├── README.md
├── app/
│   └── Main.hs                  ← CLI entry point + option parsing
├── src/
│   └── AgdaMCP/
│       ├── Server.hs            ← MCP stdio transport (JSON-RPC)
│       ├── Types.hs             ← Stable JSON schema types
│       ├── Agda.hs              ← Agda subprocess interaction + marker parsing
│       ├── Holes.hs             ← The hole model: literate masking + lexical hole scan
│       ├── Corpus.hs            ← In-memory corpus index + search/lookup
│       └── Tools/
│           ├── ProofState.hs    ← get_goal, fill_hole, check_file, get_diagnostics
│           └── Search.hs        ← search_by_name, search_by_type, get_dependencies
└── test/
    └── Main.hs                  ← Pure + corpus + integration tests
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
  "module": "Fixture01",
  "elapsedMs": 1720,
  "checkedFromSource": true
}
```

**How it works**.  Ensures `AgdaDojang.Debug` is imported (injecting the import transiently if the file does not already import it), replaces the hole with the `reportGoalCtx` macro, typechecks the file **in place**, and parses the `AGDADOJANG_REQ_BEGIN/END` marker block.  Checking at the file's real path (rather than a scratch copy) lets hierarchically-named modules embedded in a library resolve normally; the original source is restored after the call.


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
  "remainingHoles": 1,
  "elapsedMs": 1840,
  "checkedFromSource": true
}
```

**Output (failure)**.  
```json
{
  "status": "type_error",
  "candidate": "tt",
  "message": "A !=< ⊤ when checking that the expression tt has type A",
  "elapsedMs": 1795,
  "checkedFromSource": true
}
```

**Output (timeout)**.  
```json
{
  "status": "timeout",
  "candidate": "foldr-fusion refl",
  "message": "agda timed out after 300s (raise --timeout if this is a cold first check that must build .agdai interfaces for a large library)",
  "elapsedMs": 300262,
  "checkedFromSource": true
}
```

**How it works**.  Substitutes the candidate over the hole's actual span (four characters for `{!!}`, one for `?`, arbitrary for `{! e !}`), typechecks the file **in place** (restoring the original afterwards), and reports success — tolerating only the `[UnsolvedInteractionMetas]` of the file's other open holes, or of new sub-holes inside the candidate — or the type error.  A candidate that leaves `[UnsolvedMetaVariables]` or `[UnsolvedConstraints]` behind is reported as a type error (issue #69).  Hole *tracking* matches hole *tolerance* (issue #71): `holeIndex` and `remainingHoles` cover every hole syntax, so a `?` or `{! ... !}` sub-hole introduced by the candidate is counted and addressable like any other hole.  As with `get_goal`, checking at the real path lets library-embedded modules resolve.

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
  "holesCount": 3,
  "timedOut": false,
  "elapsedMs": 2140,
  "checkedFromSource": true
}
```

**Output (timeout)**.  
```json
{
  "success": false,
  "diagnostics": [
    {"severity": "error", "message": "agda timed out after 300s (raise --timeout if this is a cold first check that must build .agdai interfaces for a large library)"}
  ],
  "holesCount": 3,
  "timedOut": true,
  "elapsedMs": 300251,
  "checkedFromSource": true
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
  "holes": [{"index": 0, "line": 7, "col": 8, "goal": "?"}],
  "success": true,
  "diagnostics": [],
  "timedOut": false,
  "elapsedMs": 1980,
  "checkedFromSource": false
}
 ```

Each hole carries its 0-based `index` (the `holeIndex` accepted by `get_goal` and `fill_hole`) and its 1-based `line`/`col` position — literate-file coordinates for literate sources.

### Corpus-backed search tools (Milestone 1 — [M1-3])

Registered only when `--corpus PATH` points at an agda-strux JSONL corpus.  All
three are pure lookups on the in-memory index — they never invoke Agda.

#### `search_by_name`

Find definitions whose name matches a substring (case-insensitive), capped by an
optional `limit`.

**Input**.  
```json
{ "pattern": "hom", "limit": 5 }
```

**Output** (array of matches).  
```json
[
  {"prettyQname": "Homomorphisms.Basic.hom", "type": "...", "module": "Homomorphisms.Basic", "defKind": "function", "hasBody": true}
]
```

#### `search_by_type`

Same shape as `search_by_name`, but matches the substring against each
definition's type signature — useful for "what returns an `Algebra`?" queries.

#### `get_dependencies`

Given a fully-qualified `name`, return its `dependencies`; with `expand: true`,
also return the one-hop neighbourhood (each dependency's own record).

**Input**.  
```json
{ "name": "Homomorphisms.Basic.∘-hom", "expand": true }
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


See [GITHUB_PROJECT.md](../docs/GITHUB_PROJECT.md) for milestones and issue tracking.

---

## Example Tests

``` sh
cd agda-mcp
cabal run agda-mcp -- \
  --agda-flags "-i ../agda-dojang/agda --library-file=../agda/libraries -l agda-dojang -l standard-library" \
  < test/resources/mcp-test-input.jsonl
```

> **Note:** The test input uses paths relative to `agda-mcp/` (e.g. `../agda-dojang/...`).
> Run from the `agda-mcp/` directory, or adjust paths if running from elsewhere.

---

## Configuring MCP Clients

### Claude Code / Claude Desktop

**Recommended (zero-setup).**  This repository already ships a project `.mcp.json`
at the root that launches the server through `scripts/run-server.sh`.  That wrapper
enters `nix develop .#backend` for you (so `agda`, `cabal`, and GHC need not be on
your `PATH`) and routes the Nix banner to stderr so it does not corrupt the MCP
JSON-RPC framing.  It looks like this:

```json
{
  "mcpServers": {
    "agda": {
      "command": "./scripts/run-server.sh",
      "args": [
        "--agda-flags", "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library",
        "--corpus", "agda-mcp/test/resources/corpus-fixture.jsonl",
        "--timeout", "600",
        "--verbose"
      ]
    }
  }
}
```

Drop the `--corpus` line to run with only the four core proof-state tools; point it
at a real agda-strux corpus (see `make extract-lib`) to search a whole library.
The `--timeout 600` is deliberate rather than decorative: a first check of a large
library builds its `.agdai` interfaces and can run for minutes, so the bound has to
cover that cold call (see [Timeouts, cold calls, and latency](#timeouts-cold-calls-and-latency)).

**Direct (already inside a Nix shell).**  If you launch your client from within
`nix develop .#backend`, you can skip the wrapper and invoke `cabal` directly:

```json
{
  "mcpServers": {
    "agda": {
      "command": "cabal",
      "args": [
        "run", "-v0", "agda-mcp", "--",
        "--agda-flags", "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library",
        "--timeout", "600"
      ],
      "cwd": "/path/to/agda-native-air/agda-mcp"
    }
  }
}
```

### Cursor / Codex CLI

Similar configuration — point the MCP client at `scripts/run-server.sh` (or the
`agda-mcp` binary if you are already in a Nix shell) with the appropriate
`--agda-flags` and optional `--corpus`.

---

## Architecture Notes

### v0: Subprocess-based

The v0 implementation calls the `agda` binary as a subprocess for each
tool invocation.  This mirrors how `agda-dojang`'s Python tooling
(`agent_bridge.py`) works and reuses the established marker protocol
(`AGDADOJANG_REQ_BEGIN/END`).

**Advantages:** simple, decoupled from Agda's GHC version, reuses all
existing AgdaDojang macros without modification.

**In-place typechecking.**  All four tools typecheck the file at its real
path on disk.  `get_goal` and `fill_hole` must alter the source (inject the
reporting macro, or substitute a candidate), so they patch the file
transiently and restore it afterwards under `bracket_`.  The original is
captured and rewritten as raw bytes (`Data.ByteString`), so the file is
returned byte-for-byte — no encoding or newline round-trip — even if Agda
errors or the call is interrupted.  Checking in place, rather than against a
scratch copy, is what lets a hierarchically-named module embedded in a
library resolve its own name and cross-directory imports the same way it does
for the developer; an earlier scratch-copy approach failed on such modules
with `ModuleDefinedInOtherFile` (issue #66).

**Limitations:** each tool call spawns a new Agda process (cold
typechecking, no persistent state).  This is acceptable for the v0 demo
and benchmark fixtures, but will need optimization for larger files.

**Bounded subprocesses.**  Each call is bounded by `--timeout` and the bound is
enforced by killing the process, not by abandoning it.  `agda` is spawned into its
own process group; its stdout and stderr are drained concurrently on dedicated
threads (so neither stream can fill its pipe buffer and deadlock the other), and
the process is raced against a timer.  On expiry the group gets `SIGINT`, then
`SIGTERM`, and is then reaped with `waitForProcess` — leaving no zombie and no
orphaned `agda` still burning CPU.  This is why `readProcessWithExitCode` could
not simply be wrapped in `System.Timeout.timeout`: that kills the *waiting
Haskell thread*, not the subprocess, and leaks a running `agda` every time it
fires (issue #77).  A timeout is returned as a value, never thrown, which is what
lets the in-place tools' `bracket_` restore run on the timeout path exactly as it
does after a clean typecheck.


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
[M1-3]: https://github.com/formalverification/agda-native-air/issues/11
