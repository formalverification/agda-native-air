<!-- File: agda-native-air/agda-mcp/README.md -->

# agda-mcp

> **Status: v0.2.0 (M1-3)**.  Fourteen tools over stdio transport: four core
> proof-state tools, the whole-project gate, five live-query tools answered by
> a persistent interaction lane (issue #75), plus four corpus-backed tools:
> three search lookups and the scope-aware `search_in_scope` (issue #17).

`agda-mcp` is a [Model Context Protocol][MCP] (MCP) server that exposes
Agda's proof engine — batch typechecking verdicts, goal introspection, and
live scope, type, and definition queries — to any MCP-compatible coding agent
(Claude Code, Codex CLI, Cursor), or any other tool that speaks MCP.  It
drives the pinned `agda` binary in two lanes (a batch subprocess for
verdicts, Agda's own interaction protocol for knowledge), and uses
[AgdaDojang]'s `reportGoalCtx` reflection macro for `get_goal`'s
goal-and-context introspection.

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
responses.  It does not contain proof-search logic, heuristics, or strategy; those
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

Fourteen tools are implemented: four core proof-state tools (Milestone [M1-2]),
the whole-project gate (issue #78), five live-query tools over the interaction
lane (issue #75), three corpus-backed search tools (Milestone [M1-3]), and the
scope-aware retrieval tool `search_in_scope` (issue #17, phase 1).
Navigation tools and neural premise selection are planned for later
milestones; see [GITHUB_PROJECT.md](../docs/GITHUB_PROJECT.md).

### Where the contract lives (issue #191)

A client reads three things this server sends, and puts all of them in its
model's context on every turn: each tool's description and input schema
(`tools/list`), and the `instructions` of the `initialize` answer, which
Claude Code places in the system prompt.  So the client-visible contract is
split by who shares it, and each part is stated once.

+  **The instructions** carry what every tool shares: that the file tools'
   verdicts come from a batch process's exit code (`fill_hole`'s status also
   tolerates open holes, and `check_project`'s gate can be turned red by its
   output) and the live lane informs and never decides, each
   lane's cost, `reload`, the path refusal, the tree every answer names and the
   wrong-tree refusal, `verbose`, how failures arrive, `checkedFromSource`, and
   the hole model's coordinates.  They name only the tools the server exposes
   (see `--expose` below).
+  **Each description** carries its own tool's contract and nothing else (what
   it answers, what its verdict or its answer's fields mean, and its own
   failure modes), and each input property says what to send.  A description
   names another tool only when that tool is exposed: a subset that hides
   `check_file` gets `get_diagnostics`' whole contract, and `check_project`'s
   diagnostic shape inline, since a hidden tool's description never reaches
   the client.
+  **This README** carries the mechanism a model does not need in order to use
   a tool correctly: `search_in_scope`'s rendering ladder and rank formula, the
   lane's re-load vocabulary and lifecycle, the response echo field by field.

**Both are cut at 2,048 characters**.  Claude Code 2.1.282 truncates every MCP
tool description, and a server's instructions, at 2,048 characters and appends
`… [truncated]` (measured on issue #191 with a probe server whose texts are
numbered sequences, and on this server: before #191 eleven of the fourteen
descriptions ran to 3,193 to 7,648 characters, so 27,808 characters of their
contract, `fill_hole`'s `status` rule among them, never reached a model).  The
suite asserts that every description and the instructions fit.  Before #191
the surface was 77,603 characters of `tools/list`, about 16,300 tokens a turn
as delivered to Sonnet 5; after it, 24,094 characters of `tools/list` and 1,981
of instructions (the #191 arms ran the same `tools/list` and a 1,989-character
version of the instructions, before review fixes scoped their exit-code rule
to `success` and named `fill_hole`'s tolerance).

**Fewer tools**.  `--expose NAME,...` presents a subset: `tools/list` lists
those tools alone, the instructions name those alone, and a call to any other
registered tool is refused by name before it runs.  The agent benchmark uses it
to measure what a smaller surface changes (issue #191's `arm-verdict-mcp-1`).

### Core proof-state tools (Milestone 1 — [M1-2])

This is the minimum tooling required for an agent to do interactive proof development.

| Tool | Description |
|------|-------------|
| `get_goal`         | Inspect the goal type and local context at a hole — answered by the interaction lane when it can (no file mutation, millisecond-warm), by the reporting-macro injection otherwise; the response's `source` field says which. |
| `fill_hole`        | Substitute a candidate term into a hole and typecheck. |
| `check_file`       | Load/reload an Agda file and return all diagnostics. |
| `get_diagnostics`  | Lightweight summary: error/warning counts, open holes with positions. |

### The whole-project gate (issue #78)

| Tool | Description |
|------|-------------|
| `check_project`    | Run the project's own acceptance gate (a `make` target, a configured command, or `agda` on the project's `Everything` module) and report its verdict without misreporting its exit code. |

### Live scope, type, and definition queries (issue #75)

These answer read-only questions from a persistent `agda --interaction-json` child kept per project root (the second lane of the server, designed in [`docs/agda-mcp/agda-mcp-interaction-lane.md`](../docs/agda-mcp/agda-mcp-interaction-lane.md)).  The child holds one current file at a time, re-loaded only when it changes (or when the client passes `reload: true`); the first question about a file costs one load, every further consecutive question about it is milliseconds, and switching files under a root re-loads the switched-to file (for a file with open holes a full re-typecheck, since such a file writes no interface).  An edit to a *dependency* is picked up when the queried file is next re-loaded, or at once with `reload: true`, since no stamp on the queried file can see it.  They inform and never decide a build verdict: interaction-mode Agda is tolerant (it loads files with open holes), so `success`/`verdict` remain exclusively the batch tools' fields, and an Agda-level negative (the file does not load, the expression does not typecheck, the module is not in scope) arrives *in band* as an `error: {stage, code?, message}` object, because for a check-a-term-without-committing tool the negative answer is a product.

| Tool | Description |
|------|-------------|
| `type_of`       | Infer the type of an expression in a file's scope — the expression need not appear in the file (Agda's `C-c C-d`). |
| `normalize`     | Evaluate an expression to normal form in a file's scope (Agda's `C-c C-n`). |
| `resolve_name`  | Every candidate a name resolves to, with provenance chains — the `AmbiguousName` answer, through re-exports and module applications grep cannot see. |
| `definition_of` | The defining file and position of every candidate, chased through barrels to the origin. |
| `exports_of`    | A module's public surface, one page at a time: the first `limit` members (default 20) with their types, the names of the rest, and the total; `pattern` narrows it by name, and `""` names the file's own top-level module. |

An optional `line` argument scopes the question to the goal whose range contains it, which makes local variables visible and, on a hole-free file, recovers opened names the completed top-level scope loses.  `scope_at` — the sixth query the issue proposed — has no interaction-protocol backing (no command enumerates the names in scope) and is deliberately not approximated with grep; the finding is recorded on issue #75.

### Which file gets checked: the path rule (issue #101)

Every path-taking tool (`get_goal`, `fill_hole`, `check_file`, `get_diagnostics`, and `check_project`'s `projectPath`) resolves the path you send the same way, and the rule matters because the server is a **separate process** from your client.

+  **Pass an absolute path**.  A relative path is resolved against the *server's* working directory, which is the only directory the server knows: it is never told where its client stands.  Launched through `scripts/run-server.sh`, that directory is this repository's root, because the script deliberately `cd`s there (issue #76's stray-directory fix).  So `src/Foo.lagda.md` sent from your project names a file in *this* checkout, not in yours.
+  **A relative path that does resolve still works**.  A client whose own working directory *is* the server's (this repository's committed `.mcp.json`, `make agda-mcp-serve`, or the binary driven by hand from the repo root) keeps sending repo-root-relative paths exactly as before.
+  **`--cwd` moves that directory, deliberately**.  A registration made *for* one client project (issue #103) starts the server with `--cwd` naming that project's checkout root; the server enters it before doing anything else, so the project's own relative paths resolve there — and, just as important, the checking `agda` runs there, which is where Agda's own project discovery (the nearest `*.agda-lib`) anchors.  See [Checking a client project with its own toolchain](#checking-a-client-project-with-its-own-toolchain-issue-103).
+  **A path that resolves to no readable file is refused by name**.  The failure is a structured `pathError` object next to the prose, naming what you sent, what it resolved to, whether it was relative, and the server's working directory.  The prose states how the path was resolved on every failure; it goes on to explain the cwd rule only when the path resolved to *nothing*, which is the one case where resolving against the wrong directory is what went wrong; a relative path that resolved to a directory gets the remedy for that instead:

```json
{
  "error": "agda-mcp: filePath does not exist: /home/w/git/…/agda-native-air/src/Foo.lagda.md\n  you sent a RELATIVE path (src/Foo.lagda.md), which this server resolved against its own\n  working directory.\n  This server is a separate process, normally started in its own checkout\n  rather than in your project, so a path relative to your project does not\n  name your file here.\n  this server's working directory: /home/w/git/…/agda-native-air\n  Fix: pass an ABSOLUTE path: YOUR project's directory, followed by src/Foo.lagda.md.",
  "pathError": {
    "parameter": "filePath",
    "requestedPath": "src/Foo.lagda.md",
    "resolvedPath": "/home/w/git/…/agda-native-air/src/Foo.lagda.md",
    "relative": true,
    "serverCwd": "/home/w/git/…/agda-native-air",
    "problem": "missing"
  }
}
```

`problem` is one of four: `missing`; `notAFile` (you passed a directory); `notRegularFile` (you passed a FIFO, socket, or device, named under `detail`; this server opens regular files only, because reading anything else can block forever or never reach EOF, and it would do so *before* `--timeout` has anything to bound); or `unreadable` (the operating system refused the path — a permission wall, a symbolic-link loop, a device error — with its own words, naming the call that failed, under `detail`).  All four arrive as `isError` tool results — content your client hands its model — never as a JSON-RPC error.

This replaces the failure issue #101 was filed over: the read was unguarded, so a missing file threw an `IOException` that escaped the handler as a bare `MCP error -32603: Internal error`, naming neither the path nor the rule.  The #83 field test measured what that costs: the one agent that reached for the server on its own initiative sent a relative path, got `-32603`, concluded the server had crashed, and never called it again.  The resolution is deliberately not *guessed*: trying the relative path under each registered library root and taking a unique hit would have made that call succeed, at the price of occasionally answering green about a tree the caller never named, which is the one outcome [the field report](../docs/feedback/flrp-agda-mcp-improvements.md) § 3.6 calls worse than an error.  MCP's `roots/list` is the protocol-correct way to learn where a client stands and is left as follow-up work; it needs a bidirectional transport this server does not yet have.

### The response echo: verdict, command, project (issues #72 and #76)

Every proof-state tool can say, in three keys, what ran, what its answer
means, and which tree it ran against.  They exist because a verdict an agent
cannot check costs more than no verdict: § 2 of [the field
report](../docs/feedback/flrp-agda-mcp-improvements.md) records a session in
which the server was configured, listed, and never called, because nothing
said whether green here meant the build passed.

Since issue #184 a successful answer carries only the part of the echo it
cannot do without, and a call that passes `verbose: true` gets all of it.

| Key | With `verbose: true` | In the default (lean) answer |
|-----|----------------------|------------------------------|
| `verdict` | `equivalentTo`: the exact `agda` command this call is equivalent to, prefixed `equivalent-to:`; `meaning`: one sentence saying what the tool's verdict field means; `exitCode`: Agda's own exit status, which the verdict is derived from. | `exitCode` alone. |
| `command` | `binary` (resolved against `PATH`, so you can see *which* `agda` ran), `args` (the full argument vector, ending in the file path), and `cwd`. | Absent. |
| `project` | `rootSource` (`nearest-agda-lib` or `server-config`), `root`, the file's own `library`, the `librariesFile` consulted (echoed whether or not it exists, with `librariesFileMissing` when it does not), and what that registry declares (`registeredLibraries`) next to the libraries and include paths `agda` finally received (`selectedLibraries`, `includePaths`): the *effective* set, including whatever resolution added, so `project` and `command.args` never disagree. | `root` and `rootSource`, and `librariesFileMissing` when it is true. |

**Why lean is the default**.  The echo was written into every answer,
identically on every call, and it was most of a small one: a `type_of` whose
type is one line was 3.3 KB, of which the type was 35 characters.  Over the
server-only arm of the #162 agent benchmark the tools returned 3.6 times the
bytes the shell-only arm's commands did, and the model wrote about as much in
both.  What the verdict means is stated in the tool descriptions and the
server's instructions (issue #191), which a client already carries; the
command line and the registry are what a client re-reads only when it doubts
a call, and can then ask for.

+  **A lean answer is a restriction of the verbose one**.  Fields are left
   out, never renamed or moved: a client reading `verdict.exitCode` or
   `project.root` reads the same path in either answer, and `verbose: true`
   returns every field exactly as it was before #184.
+  **Every answer still names its tree**.  `project.root` and
   `project.rootSource` are in every answer, which is what [ADR
   0002](../docs/adr/0002-agda-mcp.md) § 5 promises.
+  **A failure keeps its whole echo**.  An error response (a timeout, a
   wrong-tree refusal, a path refusal, a lane failure) carries its full echo
   whatever was asked, since there the echo is the diagnosis.
+  **A `verbose` that is neither a boolean nor null is refused by name**,
   rather than quietly answered lean.  Null means absent, as it does for
   every optional argument this server takes (`reload`, `limit`,
   `maxDiagnostics`).

Two properties are contractual, not incidental.

+  **`success` is a function of the exit code alone**.  Never of the diagnostics text.  A change in Agda's message format can empty the `diagnostics` list (e.g., the position-parsing drift that #74 fixed) but it cannot turn a failing build green.  The test suite pins this with a stand-in binary that exits non-zero while printing nothing an error parser could latch onto.
+  **A wrong tree is an error, not a wrong answer**.  If the requested file belongs to a different checkout of a library this server has registered elsewhere, the call fails with a `rootMismatch` object naming both roots, *before* `agda` is spawned and before any in-place patching.  The one limit: that comparison is against the registry, so a configured `--library-file` that does not exist leaves nothing to compare against, which the response reports as `project.librariesFileMissing` rather than leaving you to infer it.  See [`docs/agda-mcp/agda-mcp-environment.md`](../docs/agda-mcp/agda-mcp-environment.md) for the resolution rules and the operator checklist.

There is no `strict` option to opt into: this server shells out to batch `agda` per call, so unsolved metavariables, unsolved constraints, and open holes have always made it red.  What was missing was saying so.

### The hole model, and the code-only view (issues #71, #73, #100)

All four tools share one definition of "hole", implemented in `AgdaMCP.Holes` and kept in sync with what Agda itself reports:

+  Every Agda hole syntax is recognized: `{!!}`, `{! ... !}` (with nesting), and standalone `?`, where `?` counts only as a lexically separate token, so names like `op?` or `_≟_` never match.
+  Tokens inside comments (`--` lines, nested `{- ... -}` blocks), pragmas, string/character literals, and literate prose are never holes.
+  Literate files are recognized by extension (`.lagda` / `.lagda.tex`, `.lagda.md` / `.lagda.typ`, `.lagda.rst`, `.lagda.org`, `.lagda.tree`) and only their code regions are scanned, following the code-block rules of Agda 2.8.0's own literate preprocessor.
+  `holeIndex` addresses holes in source order under this model, and all reported positions are 1-based (line, col) coordinates in the file as written — literate-file coordinates for literate sources, matching what an editor or Agda's error messages show.

One lexical scan serves the scans that are not about holes, too.  The `AgdaDojang.Debug` import `get_goal` injects must be placed *before* Agda runs, so its header search reads the *code-only view* of the file — literate prose, comment text, and pragma text blanked, every character position preserved — and a prose paragraph opening with `module`, a commented-out `module M where`, the embedded Haskell of a `{-# FOREIGN GHC ... #-}` pragma, or such a line sitting inside a `{! ... !}` hole is never mistaken for a declaration.  Holes are blanked in that view along with their contents, since Agda lexes `{! ... !}` as one token and never parses what is inside; `findHoles` is where holes are seen, and it reads the same scan.  Before issue #100 the injection read that view and the reported module name did not, so `get_goal` on a literate file could answer with a name that appears only in its prose.  The reported name is now Agda's own (see [`get_goal`](#get_goal) below); the code-only scan supplies the fallback.

### Stable hole handles (issue #79)

`get_goal` and `fill_hole` accept two spellings of "which hole", and they are not equal alternatives.

| Spelling | What a fill does to it |
|----------|------------------------|
| `line` + `column` (or `col`) | Describes where the hole's text sits.  A fill later in the file never moves it; a fill earlier in the file moves it only when the candidate differs in length or line count from the hole token it replaced. |
| `holeIndex` | A 0-based index into the source-order hole list.  Filling any earlier hole renumbers it, whether or not a character moved. |

**Prefer the position, and re-anchor it from each response**.  An index cached across calls silently addresses a different hole once an earlier hole is filled; the bookkeeping § 3.8 of [the field report](../docs/feedback/flrp-agda-mcp-improvements.md) records an agent losing track of between calls.  `holeIndex` is kept for backward compatibility.  Neither handle survives an arbitrary edit, though, which is why every answer carries the re-anchored list below: after a fill you keep, take the next address from that response rather than from coordinates cached before it.

+  A position addresses the hole whose span contains it; a position at the hole's first character counts, one past its last does not.  So both `(22, 5)` and `(22, 7)` name the `{!!}` at line 22 column 5.
+  A position inside no hole is an **error listing the file's nearest holes** — never a guess at the closest one.  An out-of-range `holeIndex` fails the same way, listing the holes the file does have.
+  A request carries exactly one address.  Both spellings at once is rejected — they can disagree, and choosing one silently is how a call fills the wrong hole — as are half a position (a `line` with no column) and both `column` and `col` together.  The input schema's `oneOf` names the three shapes a legal request has, so a client that validates its arguments and one that just sends them agree about what is legal.
+  Positions are read in the file as written, so a literate file's holes are addressed in literate-file coordinates and its prose decoys are addressable by nothing.

**Every answer re-anchors**.  `check_file` and `fill_hole` return the full hole list (the same `[{index, line, col, goal}]` shape `get_diagnostics` already returned) so a client never recomputes a position.  `fill_hole`'s list describes the file *as that candidate leaves it*, which is what the client will have once it keeps the candidate; the bytes on disk are restored either way, so until the candidate is written back the file still has the holes it started with.

### Structured diagnostics (issue #74)

`check_file` and `get_diagnostics` return diagnostics as *data*, so a client branches on a code and jumps to a range instead of regexing prose:

```json
{
  "severity": "warning",
  "code": "ModuleDoesntExport",
  "file": "/abs/path/Consumer.agda",
  "range": {"startLine": 20, "startCol": 24, "endLine": 20, "endCol": 50},
  "line": 20,
  "col": 24,
  "message": "The module DiagBarrel doesn't export the following:\n  absentName\nwhen scope checking the declaration\n  open import DiagBarrel using (usable; absentName)",
  "involved": {"candidates": ["absentName"]}
}
```

+  `code` is Agda's own name for the diagnostic (`NotInScope`, `AmbiguousName`, `ClashingDefinition`, `UnequalTerms`, `UnsolvedMetaVariables`, and so on) read from the `[Code]` of an error header or the `-W[no]Code` of a warning header.  It is absent only when Agda printed no name.
+  `range` is 1-based (line, column) in the file as written, with `endCol` one past the last character, exactly as Agda spells a span.  Both of Agda's position formats parse: the current `file:9.12-13` and `file:9.12-11.5`, and the older `file:10,5-15` and `file:10,5-11,3`.  `line` and `col` are retained as aliases of the range start, so a pre-#74 client keeps working.  Some diagnostics genuinely have no position (e.g., `error: [UnsolvedConstraints]` is printed without one) and those omit `file` and `range` rather than inventing them.
+  `message` is the *full* message body, not just the header line, bounded at 24 lines and 2000 characters (elision marker included, so a client budgeting 2000 characters is never handed one more) with the elision stated rather than silent.
+  `involved` lifts out what the message is about, per code: `expected` and `actual` for a mismatch (`Bool !=< Nat`), `candidates` for a "did you mean" list, the ambiguity candidates, the missing exports, or the origin of a clashing definition, and `metaTypes` for one entry per unsolved meta or constraint.  It is omitted when nothing was extracted; the full message is always there to fall back on.
+  `involved.metas` is the one payload that does not come from the prose (issue #115).  Agda names its unsolved metas by location and never prints their types, so the § 5 corpus's last ask — each meta with its type — is unanswerable from a batch run; a load on the interaction lane lists every meta with its name, type, and range instead.  `check_file` and `get_diagnostics` therefore hand the unsolved-meta diagnostics (`[UnsolvedMetaVariables]` and its `[UnsolvedConstraints]` sibling, whose constraint text names those very metas) a `metas: [{name, type, range}]` list from a warm lane's stored load — the same free peek that fills the hole listings' `goal` fields, never a lane call — and omit it when the lane is cold or its recorded load no longer describes the file's current bytes.  `metaTypes` is unaffected either way: it is what Agda's own prose said, and a client reading it keeps working.
+  Diagnostics are ordered **most likely root cause first**: unresolvable-file errors, then the scope warnings that precede a hard error (`ModuleDoesntExport` before the `NotInScope` it causes), then scope errors, then type errors, then unsolved metas and constraints, then remaining warnings.  The sort is stable, so Agda's own order survives within a rank.
+  The list is capped by the optional `maxDiagnostics` argument (default 10; `0` means no limit), and `diagnosticsTotal` always reports how many were found before the cap, so a broken import list cannot return a hundred cascading errors, and a truncated list is never mistaken for a short one.  `get_diagnostics`' `errors` and `warnings` counts are over *every* diagnostic found, not over the capped list.
+  Identical diagnostics collapse to one.  A run that ends in warnings prints each of them twice (once where it was raised, once under Agda's `———— All done; warnings encountered ————` banner) and counting both would double every count.

The regression suite under `test/resources/diagnostics/` has one fixture per error class of the field report's [§ 5 corpus](../docs/feedback/flrp-agda-mcp-improvements.md) (`ModuleDoesntExport`, `NotInScope`, `AmbiguousName`, `ClashingDefinition`, `UnequalTerms`, `UnsolvedConstraints` + `UnsolvedMetaVariables`) each asserting the code, the range, and the payload § 5 asks for, against the pinned Agda.

### Live queries over the interaction lane (issue #75)

The five query tools of the Tool Surface section share one implementation spine (`AgdaMCP.Tools.LiveQueries` over `AgdaMCP.Interaction`): resolve and read the requested path exactly as the batch tools do (issue #101), resolve the library context and refuse a wrong-checkout call (issue #76), then ask the root's persistent `agda --interaction-json` child, loading the file with the same effective flag list a batch check would run with — so both lanes resolve one file against one tree by construction.  The wire protocol, its probed gotchas, the process lifecycle (per-root children, evidence-gated re-loads, the #77 kill ladder on a hung command, idle reaping, crash restart), and the measured economics all live in [`docs/agda-mcp/agda-mcp-interaction-lane.md`](../docs/agda-mcp/agda-mcp-interaction-lane.md).

Every answer carries the lane's own echo in brief, `lane {load,
loadElapsedMs?}`, where `load` says why this call did or did not re-load
(`reused`/`first`/`switch`/`changed`/`forced`/`retry`) and `loadElapsedMs`
what that load cost, beside `project {root, rootSource}`.  With `verbose:
true` it carries the whole of it alongside the usual `command`/`project` pair
(issue #184): `lane {root, pid, spawned, load, loadElapsedMs?, agdaVersion,
iotcm}`, where `iotcm` is the exact wire lines sent, so a call can be replayed
by hand.  `checkedFromSource` means on this lane what it means in the batch
tools, read from the load's own progress lines: `false` for a reused load (no
load ran, so nothing was checked), and absent when its evidence could not
arrive: a per-load argv carrying `--trace-imports=0`, which silences those
lines (issue #114), or a load that failed before Agda announced the file,
which establishes no interface reuse either.  Process-level failures (spawn,
timeout, crash) are structured `isError` payloads naming the event, root, wire
lines, and the child's last stderr lines, never a bare `-32603` (issue #101's
rule), and they carry their whole echo whether or not the call asked for it.

### Corpus-backed search tools (Milestone 1 [M1-3])

These let the agent discover relevant definitions from an agda-strux JSONL corpus
without calling Agda.  They are registered **only** when the server is started
with `--corpus PATH`; without a corpus, the ten tools above are the whole
surface.

| Tool | Description |
|------|-------------|
| `search_by_name`    | Find definitions whose name matches a substring (case-insensitive). |
| `search_by_type`    | Find definitions whose type signature contains a substring. |
| `get_dependencies`  | Return a definition's dependencies, optionally expanded one hop. |

### Scope-aware retrieval (issue #17)

The fourth corpus tool is registered with the three lookups and is the one corpus
tool that also takes the interaction lane.  It answers the question the three
lookups cannot: of the corpus rows that could help *here*, which ones can this
file actually name, and what does Agda say each one's type is?

| Tool | Description |
|------|-------------|
| `search_in_scope`   | Corpus rows the queried file can name, ranked, each rendering typed by the interaction lane in that file's scope, with an honesty ledger on every response. |

It rides the corpus index for the pool and the lane for validation, so it is a
knowledge tool under the two-lane policy: it informs and never decides, no
response carries `success` or `verdict`, and a returned rendering typechecks
*as an expression* in the file's scope, which says nothing about whether it
fills any hole (`fill_hole` judges that).  The file's import surface (`import`
and `open import`, with `using`, `hiding`, `renaming`, `as`, and `public`) is
read off the code-only view, because no interaction command enumerates a
scope; that derived answer is subordinated completely, since every rendering
it proposes is typed by lane `type_of` before it is returned.  See
[`search_in_scope`](#search_in_scope) below for the contract.

One limitation is measured and stated rather than hidden: reachability is a
name-prefix rule over the queried file's own import lines, so a row that
another file re-exports into an imported module from outside that prefix is
reported out of scope even though the file can name it.  On this repository's
own fixtures, `ReexportUse.agda` imports only `ReexportBarrel`, which carries
`open import ReexportOrigin public`; the lane types both `originalName` and
`ReexportBarrel.originalName` there, while a corpus row for
`ReexportOrigin.originalName` comes back in `outOfScope`.  It costs recall
and never correctness, and closing it needs one module-contents probe per
import, which is [issue #165](https://github.com/formalverification/agda-native-air/issues/165).



---

## Command-line options

```
agda-mcp [--cwd DIR]      [--agda-bin PATH] [--agda-flags "FLAG1 FLAG2 ..."]
         [--corpus PATH]  [--timeout N] [--verbose]
         [--check-command "CMD ARGS ..."] [--check-timeout N]
         [--expose NAME,NAME,...]
```

| Flag | Description |
|------|-------------|
| `--cwd DIR`          | Working directory to enter before anything else.  Every later relative path (`--corpus`, client file paths, gate discovery) resolves inside it, and the checking `agda` runs there, so Agda's own project discovery (the nearest `*.agda-lib`) anchors to it.  Set it to the client project's checkout root when this server checks a project it is not started in (issue #103).  A directory the server cannot enter is a fatal startup error, reported by name. |
| `--agda-bin PATH`    | Path to the `agda` binary (default: `agda` on `PATH`). |
| `--agda-flags "..."` | Space-separated flags passed through to Agda (include paths, `--library-file`, `-l` library names). |
| `--corpus PATH`      | Load an agda-strux JSONL corpus; registers the four corpus tools (`search_by_name`, `search_by_type`, `get_dependencies`, `search_in_scope`). |
| `--timeout N`        | Per-typecheck timeout in seconds (default: 300; `0` means no limit).  Enforced: on expiry the `agda` process group is killed and the tool reports a timeout.  Size it for a *cold* first check; see below. |
| `--check-command "..."` | The project's acceptance gate, for `check_project`.  Split on whitespace and run **directly, with no shell**, so it can contain neither a pipeline nor a redirect, and nothing this server puts around your gate can mask its exit code.  (A wrapper *script* you name here can still lie about its own; that is what `maskedFailure` catches.)  Without it, `check_project` discovers the gate (see below). |
| `--check-timeout N`  | Timeout for one `check_project` run, in seconds (default: 1800; `0` means no limit).  Separate from `--timeout`, because a whole-project gate legitimately runs for tens of minutes. |
| `--expose NAMES`     | Present only these tools (comma-separated, issue #191): `tools/list` lists them alone, the `initialize` instructions name them alone, and a call to any other registered tool is refused by name.  A name this configuration does not register (a typo, or a corpus tool without `--corpus`) is a fatal startup error, never a silently smaller surface. |
| `--verbose`          | Emit debug output to stderr. |
| `--help`             | Print usage and exit. |

### Timeouts, cold calls, and latency

Every tool call spawns a **cold `agda` subprocess**; this server keeps no warm
Agda session and caches nothing itself.  The only warmth available is Agda's own
`.agdai` interface files, which Agda writes on a first check and reuses on later
ones.  So the first call against a large library is expected to be slow; it is
building interfaces for the whole import graph, which for something the size of
agda-algebras is *minutes*, not seconds.  Later calls that reuse those interfaces
are far faster.

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
| `checkedFromSource` | `true` if Agda re-typechecked the module from source (a `Checking` line was observed, including runs that then failed or were killed mid-check), `false` if it reused `.agdai` interfaces (the run completed successfully in silence, which is Agda's warm signature, or printed `Loading` lines at raised verbosity) — the coarse signal that explains why the same call took three minutes once and 200 ms the next time.  **Omitted** when the run died before producing evidence either way (a startup failure, or a timeout before any output), and when the flags in force carry `--trace-imports=0`, which silences the progress lines the signal reads: a cold check is then indistinguishable from a warm one, so the field is withheld rather than reported as warm (issue #114).  Muting is about that flag family at Agda's default verbosity — a raised `-v` prints the same lines again even at level 0, and the field is then answered from what was printed, since observed evidence always outranks an inference from silence.  An absent field means *unknown*, never a guess. |

On expiry the subprocess and its whole process group are killed and reaped —
escalating SIGINT → SIGTERM → SIGKILL group-wide, so no runaway `agda` and no
descendant it spawned is left behind — and the tool reports the timeout in its
own vocabulary: `fill_hole` returns `"status": "timeout"` (*not* `type_error`:
the candidate was never judged) with a message naming the bound, `check_file`
and `get_diagnostics` return `"success": false` with `"timedOut": true` and an
`agda timed out after Ns` error diagnostic, and `get_goal` returns an error
whose text is a JSON object (`{"error": …, "timedOut": true, "elapsedMs": …,
"checkedFromSource": …?}`) naming the bound while preserving the measurements
the killed call still produced.  Files patched in place by `get_goal` and
`fill_hole` are restored byte-for-byte on the timeout path exactly as on every
other path.

### Checking a client project with its own toolchain (issue #103)

A project that pins its own Agda (e.g., formal-ledger-specifications) must be checked with *that* toolchain, never this repository's; for a specification repo, version skew is a correctness hazard.  Two flags carry the whole arrangement:

+  **`--agda-bin`** names the client's own `agda`.  For a Nix-pinned project, realise a garbage-collector-rooted wrapper once (`nix build <checkout>#<agdaWithPackages-attr> -o ~/.cache/<proj>/agda-root`) and point at `<root>/bin/agda`: the wrapper bakes in the project's `--library-file`, so it is self-contained from any directory, and the gc-root pins it against `nix store gc`.  Re-run the same command after the project's flake pin moves; it re-points the same symlink.
+  **`--cwd`** names the client's checkout root.  Agda decides a file's project by walking up from the *directory it runs in* to the nearest `*.agda-lib` — not from the checked file's location — so without `--cwd` the client's modules resolve against no project at all, and with it they resolve, and write their `.agdai` interfaces, exactly as the project's own `nix develop --command agda` does.

`--agda-flags` then needs only what the wrapped binary does not already carry.  One addition is load-bearing: `-i <this-repo>/agda-dojang/agda`, because `get_goal` splices `open import AgdaDojang.Debug` into the file it inspects, and the client's Agda must be able to see that module's source (it imports only builtins, so it compiles under any Agda 2.8).  [`examples/fls.mcp.json`](examples/fls.mcp.json) is the registration this section describes, tested against real formal-ledger modules.

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
│       ├── Diagnostics.hs       ← Agda output → structured diagnostics: codes, ranges, involved
│       ├── Holes.hs             ← The hole model: literate masking, lexical scan, code-only view
│       ├── Project.hs           ← Root resolution: nearest *.agda-lib, registry, mismatch
│       ├── Gate.hs              ← Which command is the project's gate: make target, configured, Everything
│       ├── Interaction.hs       ← The interaction lane: persistent agda --interaction-json child per root
│       ├── Corpus.hs            ← In-memory corpus index + search/lookup
│       ├── Scope.hs             ← The import surface off the code-only view; the rendering ladder
│       ├── Retrieval.hs         ← Tokens, statement normalization, the scorer, the pool pipeline
│       └── Tools/
│           ├── ProofState.hs    ← get_goal, fill_hole, check_file, get_diagnostics
│           ├── CheckProject.hs  ← check_project: run the gate, never misreport its exit code
│           ├── LiveQueries.hs   ← type_of, normalize, resolve_name, definition_of, exports_of
│           ├── Search.hs        ← search_by_name, search_by_type, get_dependencies
│           └── SearchInScope.hs ← search_in_scope: the pool, the ladder on the lane, the ledger
└── test/
    └── Main.hs                  ← Pure + corpus + integration tests
```

### Core proof-state tools (Milestone 1)

#### `get_goal`

Given a file path and hole address, return the hole's expected type and its local context (bound variables with types); this is the primary "what am I trying to prove?" query.

**Input**.  The hole is addressed by position (preferred) or by index; see [Stable hole handles](#stable-hole-handles-issue-79).

```json
{
  "filePath": "/path/to/Fixture01.agda",
  "line": 7,
  "column": 8
}
```

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
  "checkedFromSource": true,
  "source": "injected-macro",
  "verdict": {"exitCode": 42},
  "project": {"root": "/path/to", "rootSource": "server-config"}
}
```

That is the default (lean) answer; `verbose: true` adds the rest of the
[response echo](#the-response-echo-verdict-command-project-issues-72-and-76).
A lane-sourced answer (`source: "interaction-lane"`) carries `lane {load,
loadElapsedMs?}` in place of `verdict`.

`module` is the name **Agda** resolved for this file, read from the `Checking M (path).` line of the very run this call made.  That is the name an `import` of the file must use and the name Agda's own messages print: `Proofs.Use` for a module embedded at `src/Proofs/Use.agda`, and `AnonModule` for a file whose header reads `module _ where`, which no reading of the source could supply.  When the goal comes back and Agda named no module — a client whose `--agda-flags` include `--trace-imports=0` silences the progress line — the field falls back to the name the source *declares*, scanned off the code-only view so that neither prose nor a comment can supply it.  The other ways Agda can decline to say do not reach this field: a parse error, a header that disagrees with its file name, or a timeout ends the call as a failure response, which carries no `module` at all — for a mismatched header the failure's text is Agda's own message, which names both the module it found and the file it expected (issue #100).

`verdict.exitCode` here is normally **non-zero even when the goal is right**: the injected macro leaves an interaction point behind, so this run is evidence about the introspection, not a judgement on the file.  Use `check_file` for that.

**How it works**.  Ensures `AgdaDojang.Debug` is imported (injecting the import transiently if the file does not already import it), replaces the hole with the `reportGoalCtx` macro, typechecks the file **in place**, and parses the `AGDADOJANG_REQ_BEGIN/END` marker block.  Checking at the file's real path (rather than a scratch copy) lets hierarchically-named modules embedded in a library resolve normally; the original source is restored after the call.

**A fallback-path timeout** is an `isError` result whose text is a JSON object, `{error, timedOut: true, elapsedMs, checkedFromSource?, verdict, command, project}`, naming the bound, since no goal was reported.  A lane timeout is reported as the lane's own structured failure and is never re-run on the fallback path, which would double the bound.

#### `fill_hole`

Submit a candidate term for a hole and receive typecheck feedback: success (hole filled, possibly generating new sub-holes) or failure (error message with location).

**Input**.  Addressed like `get_goal`, by position or by index.

```json
{
  "filePath": "/path/to/Fixture01.agda",
  "line": 7,
  "column": 8,
  "candidate": "x"
}
```

**Output (success)**.  
```json
{
  "status": "ok",
  "candidate": "x",
  "holes": [{"index": 0, "line": 10, "col": 11, "goal": "?"}],
  "remainingHoles": 1,
  "elapsedMs": 1840,
  "checkedFromSource": true,
  "verdict": {"exitCode": 0},
  "project": {"root": "/path/to", "rootSource": "server-config"}
}
```

**Output (failure)**.  
```json
{
  "status": "type_error",
  "candidate": "tt",
  "message": "A !=< ⊤ when checking that the expression tt has type A",
  "holes": [{"index": 0, "line": 10, "col": 11, "goal": "?"}],
  "remainingHoles": 1,
  "elapsedMs": 1795,
  "checkedFromSource": true,
  "verdict": {"exitCode": 42},
  "project": {"…": "…"}
}
```

**Output (timeout)**.  
```json
{
  "status": "timeout",
  "candidate": "foldr-fusion refl",
  "message": "agda timed out after 300s (raise --timeout if this is a cold first check that must build .agdai interfaces for a large library)",
  "holes": [{"index": 0, "line": 10, "col": 11, "goal": "?"}],
  "remainingHoles": 1,
  "elapsedMs": 300262,
  "checkedFromSource": true,
  "verdict": {"exitCode": -1},
  "project": {"…": "…"}
}
```

**Output (no hole at that position)**.  An error response, returned before `agda` is spawned.

```
No hole at line 23, column 1 in /abs/TwoHoles.agda (a position addresses the hole
whose span contains it; starting at it counts).
  nearest holes (2 in the file):
    index 0 at line 22, column 5
    index 1 at line 25, column 5
  Address a hole by the (line, column) its own listing reports (get_diagnostics.holes,
  check_file.holes, or the holes list every fill_hole response carries).
  Take that listing from the latest response: a fill above a hole moves it when the
  candidate is a different length, and renumbers it always.
```

**How it works**.  Substitutes the candidate over the hole's actual span (four characters for `{!!}`, one for `?`, arbitrary for `{! e !}`), typechecks the file **in place** (restoring the original afterwards), and reports success — tolerating only the `[UnsolvedInteractionMetas]` of the file's other open holes, or of new sub-holes inside the candidate — or the type error.  A candidate that leaves `[UnsolvedMetaVariables]` or `[UnsolvedConstraints]` behind is reported as a type error (issue #69).  Hole *tracking* matches hole *tolerance* (issue #71): the hole address, `holes`, and `remainingHoles` cover every hole syntax, so a `?` or `{! ... !}` sub-hole introduced by the candidate is counted and addressable like any other hole.  Every response (ok, type error, or timeout) carries `holes`, the re-anchored list described under [Stable hole handles](#stable-hole-handles-issue-79), so a multi-hole edit needs no index bookkeeping between calls (issue #79).  As with `get_goal`, checking at the real path lets library-embedded modules resolve.

#### `check_file`

Load or reload an Agda file and return all diagnostics (errors, warnings, unsolved metas, and remaining holes).

**Input**.  
```json
{
  "filePath": "/path/to/Fixture01.agda",
  "maxDiagnostics": 10
}
```

**Output**.  The default (lean) answer; its `verdict` and `project` blocks are
what every answer keeps of the [response
echo](#the-response-echo-verdict-command-project-issues-72-and-76).

```json
{
  "success": false,
  "diagnostics": [
    {
      "severity": "error",
      "code": "UnequalTerms",
      "file": "/path/to/Fixture01.agda",
      "range": {"startLine": 17, "startCol": 5, "endLine": 17, "endCol": 9},
      "line": 17,
      "col": 5,
      "message": "Bool !=< Nat\nwhen checking that the expression true has type Nat",
      "involved": {"expected": "Nat", "actual": "Bool"}
    }
  ],
  "diagnosticsTotal": 1,
  "holesCount": 3,
  "holes": [
    {"index": 0, "line": 7,  "col": 8,  "goal": "?"},
    {"index": 1, "line": 10, "col": 11, "goal": "?"},
    {"index": 2, "line": 14, "col": 9,  "goal": "?"}
  ],
  "timedOut": false,
  "elapsedMs": 2140,
  "checkedFromSource": true,
  "verdict": {"exitCode": 42},
  "project": {"root": "/abs/agda-native-air/agda-dojang", "rootSource": "nearest-agda-lib"}
}
```

**Output with `verbose: true`**.  The same answer with the whole echo, which
every proof-state tool adds on request; it is shown in full only here.

```json
{
  "success": false,
  "…": "…",
  "verdict": {
    "equivalentTo": "equivalent-to: /nix/store/…/bin/agda -i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library /abs/Fixture01.agda",
    "meaning": "success is true if and only if that command exited 0, so it means exactly what green means in a batch build. …",
    "exitCode": 42
  },
  "command": {
    "binary": "/nix/store/…-agdaWithPackages-2.8.0/bin/agda",
    "args": ["-i", "agda-dojang/agda", "--library-file=agda/libraries", "-l", "agda-dojang", "-l", "standard-library", "-i", "/abs/dir", "/abs/Fixture01.agda"],
    "cwd": "/abs/agda-native-air"
  },
  "project": {
    "rootSource": "nearest-agda-lib",
    "root": "/abs/agda-native-air/agda-dojang",
    "library": {"name": "agda-dojang", "root": "/abs/agda-native-air/agda-dojang", "libFile": "…/agda-dojang.agda-lib", "includes": ["agda"]},
    "librariesFile": "/abs/agda-native-air/agda/libraries",
    "registeredLibraries": [{"name": "agda-dojang", "…": "…"}],
    "selectedLibraries": ["agda-dojang", "standard-library"],
    "includePaths": ["agda-dojang/agda"]
  }
}
```

**Output (timeout)**.  
```json
{
  "success": false,
  "diagnostics": [
    {"severity": "error", "message": "agda timed out after 300s (raise --timeout if this is a cold first check that must build .agdai interfaces for a large library)"}
  ],
  "diagnosticsTotal": 1,
  "holesCount": 3,
  "holes": [{"index": 0, "line": 7, "col": 8, "goal": "?"}, {"…": "…"}],
  "timedOut": true,
  "elapsedMs": 300251,
  "checkedFromSource": true,
  "verdict": {"exitCode": -1},
  "project": {"…": "…"}
}
```

**Output (the file belongs to another checkout)**.  An error response, returned before `agda` is spawned.

```json
{
  "error": "agda-mcp: refusing to check /abs/branch-B/src/M.agda — it belongs to a different checkout than the one this server has registered. …",
  "rootMismatch": {
    "filePath": "/abs/branch-B/src/M.agda",
    "libraryName": "agda-algebras",
    "fileRoot": "/abs/branch-B",
    "registeredRoot": "/abs/branch-A",
    "librariesFile": "/abs/agda-native-air/agda/libraries"
  }
}
```

The timeout notice is a diagnostic like any other, and stays first: it explains why the rest of the list is short.  See [Structured diagnostics](#structured-diagnostics-issue-74) for `code`, `range`, `involved`, the ordering, and the cap.

#### `get_diagnostics`

Retrieve the current diagnostic state without reloading: error count, warning count, list of open holes with their types.

**Input**.  
```json
{
  "filePath": "/path/to/Fixture01.agda",
  "maxDiagnostics": 10
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
  "diagnostics": [
    {
      "severity": "warning",
      "code": "UnreachableClauses",
      "file": "/path/to/Fixture01.agda",
      "range": {"startLine": 6, "startCol": 1, "endLine": 6, "endCol": 8},
      "line": 6,
      "col": 1,
      "message": "Unreachable clause\nwhen checking the definition of f"
    }
  ],
  "diagnosticsTotal": 1,
  "timedOut": false,
  "elapsedMs": 1980,
  "checkedFromSource": false,
  "verdict": {"exitCode": 0},
  "project": {"…": "…"}
}
 ```

`success` and `verdict` are the same fields `check_file` returns, with the same derivation from Agda's exit code: the two tools differ in what they summarize, never in what green means.  The `errors` / `warnings` counts come from parsing Agda's prose and can drift with its message format, which is exactly why `success` is not read from them.

Each hole carries its 0-based `index` (the `holeIndex` accepted by `get_goal` and `fill_hole`) and its 1-based `line`/`col` position — literate-file coordinates for literate sources.  The `line`/`col` pair is the one to pass back: a fill moves it only when the edit moves the hole's text, while `index` is renumbered by any fill at all (see [Stable hole handles](#stable-hole-handles-issue-79)).  `errors` and `warnings` count every diagnostic found, not just the ones `maxDiagnostics` kept.

### The whole-project gate (issue #78)

#### `check_project`

Run the project's own acceptance gate — the whole-project check a human runs before calling the work done — and report its verdict.  This is the call that replaces running the gate from a shell, and with it the defence the shell forces on you: in [§ 3.5 of the field report](../docs/feedback/flrp-agda-mcp-improvements.md), the session's gate was a 10–20 minute `make check` over a generated `Everything.agda`, run four times as a backgrounded Bash job, and its wrapper script ended in an `echo`, so the shell reported exit 0 whatever `make` had done, and the log had to be grepped for `error:` every time.

**Input**.  Every field is optional, because the honest default is discoverable.

```json
{
  "target": "check",
  "projectPath": "/path/to/project",
  "maxDiagnostics": 10
}
```

**Which command runs**, in this order:

+  the `make` target named by `target`, the nearest Makefile *above the anchor* that declares it, run in that Makefile's own directory;
+  else the server's `--check-command`, if the operator configured one (run directly, never through a shell);
+  else the nearest Makefile's `check` target;
+  else `agda` on the project's `Everything` module (`Everything.agda` or any literate flavour), with the same flags `check_file` would use;
+  else the call **fails**, naming every directory it searched and what to configure.  A check that did not happen is never reported as a pass.

The upward search stops at a repository boundary (a `.git` file or directory), so a Makefile above your checkout is never mistaken for your gate.  Discovery reads each Makefile's own rule lines: a target defined only in an `include`d file is not found, and `--check-command` is the escape hatch.  `projectPath` anchors the search, a file anchors its own directory, and a path that does not exist is an error rather than a reason to check something else.  The response's `gate` block says which of the five branches was taken, and `command` echoes the argument vector and working directory that ran.

**`success` is a conjunction, and that is the whole point**.

```
success  ⟺  exit 0  ∧  finished inside the bound  ∧  no failure evidence in the output
```

+  `verdict.exitCode` is the gate's own status whenever the gate produced one, echoed verbatim and never reinterpreted, so a failing gate can never be reported green.  Two runs have no status of their own and report `-1`: a gate that could not be started, and one killed at the bound.  `timedOut` tells those apart, and a gate that could not be started also says so in `outputTail`.  A killed process's real status is the signal that took it down, which is indistinguishable from an ordinary failure, so #77 reports the fact as a flag rather than as a magic exit code, and this tool follows it.
+  The reverse is deliberate.  A gate that exits 0 while its output carries failure evidence is reported as `"success": false` with `"maskedFailure": true` — the wrapper-ending-in-`echo` trap, named in the response instead of left for the client to grep for.
+  *Failure evidence* is two recognizers: an Agda error diagnostic, and the gate's own failure line — GNU make's `make: *** [Makefile:12: check] Error 2` and its `make[1]:` / `gmake:` variants, which is what a missing tool or a failed non-Agda step looks like.  When the second one is what caught the mask, it becomes the diagnostic explaining the verdict, since Agda printed nothing that would.
+  So the evidence can turn a green gate red, never a red gate green.  This is the one place the server departs from "the verdict is the exit code and nothing else" (issue #72), and it departs only in the safe direction: there, the risk was Agda's prose drifting and silently passing a broken build; here, the risk is a wrapper the server did not write.
+  Those recognizers are a list, not a theory of failure.  A wrapper that hides a failure printing neither is reported as a pass, and no honest reading from outside the wrapper can do better, which is exactly why `outputTail` comes back whatever the verdict.  The response never claims a pass while withholding the output that could contradict it.
+  The cost is a false alarm for a gate that prints an Agda `error:` block in the course of passing (e.g., a deliberately-failing negative test).  The diagnostics and the exit code are both right there in the response, so the alarm is legible rather than mysterious.

**Output (a gate whose exit code was masked)**.  An ordinary failure looks the same but with a non-zero `exitCode` and no `maskedFailure`.

```json
{
  "success": false,
  "timedOut": false,
  "maskedFailure": true,
  "elapsedMs": 812431,
  "timeoutSeconds": 1800,
  "gate": {
    "source": "makefile-target",
    "target": "check",
    "makefile": "/abs/agda-algebras/Makefile",
    "searchedFrom": "/abs/agda-algebras"
  },
  "diagnostics": [
    {
      "severity": "error",
      "code": "NotInScope",
      "file": "/abs/agda-algebras/src/Base/Structures/Basic.lagda.md",
      "range": {"startLine": 116, "startCol": 9, "endLine": 116, "endCol": 14},
      "line": 116,
      "col": 9,
      "message": "Not in scope:\n  zeroo\n  at …:116.9-14\n    (did you mean 'zero'?)",
      "involved": {"candidates": ["zero"]}
    }
  ],
  "diagnosticsTotal": 3,
  "firstError": {"severity": "error", "code": "NotInScope", "…": "…"},
  "failingModule": "Base.Structures.Basic",
  "failingFile": "/abs/agda-algebras/src/Base/Structures/Basic.lagda.md",
  "modulesChecked": 143,
  "outputTail": "… 218 earlier lines elided …\nmake: *** [Makefile:31: check] Error 42\ngate finished",
  "verdict": {"exitCode": 0},
  "project": {"root": "/abs/agda-algebras", "rootSource": "nearest-agda-lib"}
}
```

With `verbose: true` the same answer adds the rest of the echo:

```json
{
  "…": "…",
  "verdict": {
    "equivalentTo": "equivalent-to: (cd /abs/agda-algebras && make check)",
    "meaning": "success is true if and only if that command exited 0, finished inside the --check-timeout bound, and printed no failure evidence. …",
    "exitCode": 0
  },
  "command": {"binary": "/nix/store/…/bin/make", "args": ["check"], "cwd": "/abs/agda-algebras"},
  "project": {"…": "…"}
}
```

| Field | Meaning |
|-------|---------|
| `firstError`     | The first error-severity diagnostic, lifted out of the (capped) `diagnostics` list so a client need not scan it.  The list itself is the [structured-diagnostics](#structured-diagnostics-issue-74) shape, root-cause ordered and capped by `maxDiagnostics`. |
| `failingModule` / `failingFile` | The module the gate stopped in, present **only when the check did not pass**: the one carrying `firstError`, or, when the gate failed without a located error (a timeout included), the last module `agda` started.  The module name comes from Agda's own `Checking M (path).` progress line.  A green gate has no failing module, so on a pass both are absent. |
| `modulesChecked` | How many distinct modules `agda` re-typechecked from source, so how much of the project was actually rebuilt: 0 on a fully warm gate, the whole import graph on a cold one, and on a timeout, how far it got.  Absent when the gate is the `Everything` module and the `agda` command this server assembled for it carries `--trace-imports=0`, since the flag silences the very lines this counts and what could still be counted is then a floor rather than a total (issue #114).  Every other gate is opaque and treated so: a `make` recipe or a `--check-command` script chooses its own `agda` invocation, which this server neither writes nor reads, so there the count stays a best-effort read of whatever the gate printed. |
| `outputTail`     | The bounded tail of the gate's stdout and stderr (40 lines / 4000 characters, elision counted), returned **whatever the verdict** and absent only when the gate printed nothing.  A gate can fail for reasons Agda never printed (no such target, a missing tool, a killed build) and a mask the two recognizers above miss is reported as a pass, so the evidence has to be in the response to be read. |
| `timeoutSeconds` | The `--check-timeout` bound in effect; absent when unbounded. |

**Cost, and no streaming**.  This call *blocks* for the whole gate and reports its timings at the end.  10–20 minutes is an ordinary figure for a large library.  The MCP transport here is a synchronous line loop with no progress-notification plumbing, so streaming progress is honest follow-on scope rather than something the framing already supports; `modulesChecked` and `failingModule` are the progress report a blocking call *can* give, including on the timeout path.  Narrowing a check to the files changed `since` a revision is likewise follow-on scope.

**Output (timeout)**.  The gate's whole process group is killed (`make` and every `agda` under it) and the response still carries what the run established on the way down.

```json
{
  "success": false,
  "timedOut": true,
  "elapsedMs": 1800213,
  "timeoutSeconds": 1800,
  "gate": {"source": "makefile-target", "target": "check", "…": "…"},
  "diagnostics": [
    {"severity": "error", "message": "the project gate timed out after 1800s (raise --check-timeout if this gate legitimately runs longer; a cold whole-project check that must build .agdai interfaces for a large library can take tens of minutes)"}
  ],
  "diagnosticsTotal": 1,
  "failingModule": "Base.Structures.Basic",
  "modulesChecked": 143,
  "outputTail": "…",
  "verdict": {"exitCode": -1},
  "project": {"…": "…"}
}
```

**The `project` block, for a gate**.  It is resolved from the anchor exactly as `check_file` resolves it from a file, including the [wrong-checkout refusal](#the-response-echo-verdict-command-project-issues-72-and-76): pointing `check_project` at a worktree whose libraries registry names a *different* worktree fails with a `rootMismatch` rather than running a gate whose imports resolve against the other tree.  One difference is worth knowing: for a `make` or `--check-command` gate, `selectedLibraries` and `includePaths` are this server's own configuration and **not** a claim about the flags the gate passed `agda`; the gate chooses those itself.  For the `Everything` gate they are what `agda` finally received, as everywhere else.

### Corpus-backed search tools (Milestone 1 [M1-3])

Registered only when `--corpus PATH` points at an agda-strux JSONL corpus.  All
three are pure lookups on the in-memory index; they never invoke Agda.  The
fourth corpus tool, `search_in_scope`, is documented after them; it reads the
same index and asks the interaction lane about every row it returns.

**At library scale**.  The published agda-algebras corpus (issue #84, dataset card at [`docs/corpora/agda-algebras-v0.md`](../docs/corpora/agda-algebras-v0.md)) is 11,666 rows and 185 MB of JSONL; it loads in about 1.4 s to a 308 MB resident footprint.  The index keeps only the fields these tools serve — the `typeAst` and the proof bodies are read and dropped, which is the difference between that and 2.7 GB — so `hasBody` tells an agent a proof term exists to go and read, and the corpus file is where to read it.  Two consequences of a real corpus worth knowing before you write a query: its dependency tokens are *fully qualified* (`Overture.Signatures.Signature`, not `Signature`), and 655 of its `prettyQname` keys are shared by more than one row, so the index holds 10,520 of the 11,666.  `make corpus-mcp-smoke` drives the three pure lookups against it over this transport; `search_in_scope` needs a loaded file as well as the corpus, and the live tier of `make agda-mcp-test` is where it is exercised.

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
definition's type signature; useful for "what returns an `Algebra`?" queries.

#### `get_dependencies`

Given a fully-qualified `name`, return its `dependencies`; with `expand: true`,
also return the one-hop neighbourhood (each dependency's own record).

**Input**.  
```json
{ "name": "Homomorphisms.Basic.∘-hom", "expand": true }
```

### Scope-aware retrieval (issue #17, phase 1)

#### `search_in_scope`

Of the corpus rows that match a query, which ones can this file actually name,
and what does Agda say each one's type is?  The pool is the corpus index; the
scope is the file's import surface; and the validation is the interaction lane,
which types every candidate rendering in the file's scope (goal-scoped when the
anchor addresses a hole) before it is returned.  The contract was agreed on
issue #17 before the tool was built.  Since issue #191 the description a
client receives carries what a caller needs (the question, that every
rendering was typed here, the query, the bounds, the exclusion, the ledger);
the ladder and the rank below are documented here, for people.

**Input**.  Only `filePath` is required.  `query` may be omitted when
`line`/`column` addresses a hole: the tokens are then derived from that goal's
own displayed type, through the same normalized display `get_goal`'s lane path
reads, and the response says `query.source: "goal"`.

```json
{
  "filePath": "/abs/agda-mcp/test/resources/ScopeSearch.agda",
  "line": 23, "column": 11,
  "query": { "tokens": ["Nat"] },
  "limit": 10,
  "exclude": { "names": ["probe"], "statement": "(n : Nat) → twice n ≡ n + n" }
}
```

| Property | Meaning |
|----------|---------|
| `query` | `{name?, tokens?}`: a case-insensitive substring over the qualified and unqualified names, and/or type tokens as a goal display spells them (`+`, `≡`, `Commutative`, `hom`), matched after the corpus's qualified tokens are reduced to bare ones (`Agda.Builtin.Nat._+_` meets `+`).  Both given means both must hold. |
| `limit` | Accepted rows to return (default 8).  The cut is taken **after** lane validation, so a rejected rendering never consumes a slot. |
| `maxProbes` | Ranked rows sent to the lane before the walk gives up on filling `limit` (default 4 × `limit`), so a pool of stale rows cannot hold the call. |
| `exclude` | `{names?, statement?}`: your policy, never the server's.  Rows whose bare name is listed, or whose type normalizes to the statement (on the corpus text, and again on Agda's printing of the accepted rendering), are set aside and **named** in the ledger with a reason. |

**Output**.  Captured over the stdio transport against the fixture corpus and
`test/resources/ScopeSearch.agda`, whose imports are deliberately narrow
(`open import ScopeSearchLib using (twice)`; `import ScopeSearchBarrel`, not
opened).  The lane echo (`lane`, `command`, `project`, `elapsedMs`,
`checkedFromSource`) is the live-query echo and is elided here.

```json
{
  "query": { "tokens": ["Nat"], "source": "given" },
  "scope": "goal 0 (line 23, column 11)",
  "imports": [
    { "module": "Agda.Builtin.Nat", "opened": true },
    { "module": "Agda.Builtin.Equality", "opened": true },
    { "module": "ScopeSearchLib", "opened": true, "using": ["twice"] },
    { "module": "ScopeSearchBarrel", "opened": false }
  ],
  "results": [
    { "prettyQname": "ScopeSearchBarrel.Core.quad", "rendering": "ScopeSearchBarrel.quad",
      "type": "Nat → Nat", "via": { "module": "ScopeSearchBarrel", "rung": "importing-module" },
      "module": "ScopeSearchBarrel.Core", "defKind": "function", "hasBody": true,
      "corpusType": "Nat → Nat", "score": 2 },
    { "prettyQname": "ScopeSearchLib.Box.unbox", "rendering": "ScopeSearchLib.Box.unbox",
      "type": "ScopeSearchLib.Box → Nat", "via": { "module": "ScopeSearchLib", "rung": "qualified" }, "…": "…" },
    { "prettyQname": "ScopeSearchLib.Inner.thrice", "rendering": "ScopeSearchLib.Inner.thrice",
      "type": "Nat → Nat", "via": { "module": "ScopeSearchLib", "rung": "qualified" }, "…": "…" },
    { "prettyQname": "ScopeSearchLib.twice", "rendering": "twice",
      "type": "Nat → Nat", "via": { "module": "ScopeSearchLib", "rung": "bare" }, "…": "…" },
    { "prettyQname": "ScopeSearchLib.twice-def", "rendering": "ScopeSearchLib.twice-def",
      "type": "(n₁ : Nat) → n₁ + n₁ ≡ n₁ + n₁", "via": { "module": "ScopeSearchLib", "rung": "qualified" }, "score": 0, "…": "…" }
  ],
  "ledger": {
    "hits": 7, "inScope": 6, "outOfScope": 1,
    "excluded": [], "nonFunction": 0, "ranked": 6, "probed": 6, "laneCalls": 9,
    "laneRejected": [ { "prettyQname": "ScopeSearchLib.ghost", "tried": ["ScopeSearchLib.ghost"] } ],
    "accepted": 5, "truncated": false, "stoppedBy": "exhausted"
  },
  "timing": { "poolMs": 0, "laneMs": 8 },
  "elapsedMs": 68, "lane": {"…": "…"}, "project": {"…": "…"}
}
```

Three things are contractual.

+  **Every `rendering` was typed by Agda in this file's scope, and `type` is Agda's printing**.  Typing alone is not identity, though: a pattern variable named like a `using`-listed import shadows it inside a hole, and a re-exported spelling resolves to whatever the importing module exports under that name, so every accepted spelling other than the row's own qualified name is also asked Agda's `WhyInScope` and kept only if a candidate's defined name is the row's (the `shadow` hole of the fixture pins the local case: `twice` types there as `Nat`, is refused, and the row renders as `ScopeSearchLib.twice`).  Three of the ladder's four rungs are visible above: `twice` is `using`-listed and renders bare; the nested rows render by their own qualified name; and `quad`, defined in `ScopeSearchBarrel.Core` and re-exported by the barrel this file imports, renders as `ScopeSearchBarrel.quad` because the lane refused `ScopeSearchBarrel.Core.quad` (that module is not in the file's scope).  The fourth, `re-export`, is the importing module qualifying the tail of the row's module path, which is how a record field defined in a file that an imported module re-exports is named (`Setoid.Homomorphisms.IsHom.compatible` for the agda-algebras row `Setoid.Homomorphisms.Basic.IsHom.compatible`); the first measurement on that corpus found those rows refused under every other spelling, and the ladder grew the rung.  `ScopeSearchLib.ghost`, a row the corpus carries and the library no longer defines, is not returned; it is named in `laneRejected` with the spelling that was tried.
+  **An empty result states its bounds**.  `hits` counts the query's matches over the whole corpus, before scope, so `hits: 12, inScope: 0` reads as "the lemma exists and this file does not import its module"; `excluded` names every row your own `exclude` set aside and why (`name`, `statement`, or `lane-statement`); `laneRejected` names every row the loaded library disagreed with; `laneCalls` counts the lane calls spent validating (a `type_of` per rung tried, plus one identity check per accepted spelling other than the row's own qualified name; the goal read of a derived query is timed, not counted); and `stoppedBy` says whether the walk ended because `limit` was filled, `maxProbes` was spent, or the ranked list ran out.
+  **No verdict**.  A file that does not load answers `error.stage: "load"` with Agda's message and runs no query; no `query` with no goal at the anchor, or with a goal whose display yields no tokens (a goal that is only a context variable), answers `error.stage: "query"` rather than searching the whole corpus.  Process-level lane failures and path refusals are the same structured `isError` payloads the live-query tools raise.

**The rank**.  Only rows of `defKind` `function` are ranked (constructors,
records, and data types are counted in `ledger.nonFunction`).  A row scores
twice the overlap between the query's tokens and its own bare type tokens,
plus a name bonus capped at one, minus one per pure-symbol operator in its
type that the query never mentions; ties break cheap before expensive on
approximate arity, then by name.  Both sides are reduced the same way (a
name's outer underscores stripped, so `_+_` meets `+`), and a query whose
tokens all reduce to nothing, with no `name` beside them, selects nothing
rather than everything: it answers `error.stage: "query"`.

`timing.poolMs` is the corpus half (query, scope, exclusion, rank over the whole
index) and `timing.laneMs` the lane half (every `type_of`, plus the goal read
when the query was derived).  Measured on the agda-algebras v0.1 corpus (11,865
indexed rows) from a benchmark obligation whose seven `using` imports reach 98
to 247 rows per query: the pool half answers in 7 to 35 ms whatever the query
(one token, four goal-derived tokens, or a name), because bare type tokens are
indexed at corpus load (about half a second of the 2.3 s load); a warm lane
answers a `type_of` or an identity check in 3 to 5 ms, so a default call of
eight results, all reached through re-exports on that obligation, costs 20 to
23 lane calls and 55 to 70 ms; and the one cold cost is the file's first lane
load, 5.6 to 6.4 s for that obligation, paid once per file and shared with
every live-query tool.  The full table is on issue #17.  Phase 2 of the issue,
`search_term` (bounded synthesis at a hole, committed-checkable terms only), is
not part of this tool.

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
| **agda-dojang**  | Interaction layer: provides the proof actions that `agda-mcp` wraps | [`agda-dojang/`](../agda-dojang/)   |
| **agda-strux**   | Extraction layer: produces the corpus data that backs search tools  | [`agda-strux/`](../agda-strux/)     |
| **strux-driver** | ETL layer: processes extracted data into retrieval-friendly formats | [`strux-driver/`](../strux-driver/) |


See [GITHUB_PROJECT.md](../docs/GITHUB_PROJECT.md) for milestones and issue tracking.

---

## Example Tests

``` sh
cd agda-mcp
cabal run agda-mcp -- \
  --agda-flags "-i ../agda-dojang/agda --library-file=../agda/libraries -l agda-dojang -l standard-library" \
  < test/resources/mcp-test-input.jsonl
```

> **Note**: The test input uses paths relative to `agda-mcp/` (e.g. `../agda-dojang/...`).
> Run from the `agda-mcp/` directory, or adjust paths if running from elsewhere.

---

## Configuring MCP Clients

### Claude Code / Claude Desktop

**Recommended (zero-setup)**.  This repository already ships a project `.mcp.json`
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
at a real agda-strux corpus to search a whole library — `make extract-lib` then
`make corpus` builds one, and [`docs/corpora/agda-algebras-v0.md`](../docs/corpora/agda-algebras-v0.md)
describes the published agda-algebras corpus and how to reproduce it.
The `--timeout 600` is deliberate rather than decorative: a first check of a large
library builds its `.agdai` interfaces and can run for minutes, so the bound has to
cover that cold call (see [Timeouts, cold calls, and latency](#timeouts-cold-calls-and-latency)).

**Direct (already inside a Nix shell)**.  If you launch your client from within
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

Similar configuration: point the MCP client at `scripts/run-server.sh` (or the
`agda-mcp` binary if you are already in a Nix shell) with the appropriate
`--agda-flags` and optional `--corpus`.

---

## Architecture Notes

### The batch lane: a subprocess per verdict

The verdict-producing tools call the `agda` binary as a subprocess for each
invocation; since issue #108, `get_goal` prefers the persistent interaction
lane (next section) and reaches a subprocess only on its fallback path.  The
approach was inherited from `agda-dojang`'s Python bridge
(`agent_bridge.py`), which this server superseded and which retired in
issue #109.  The marker protocol that bridge established
(`AGDADOJANG_REQ_BEGIN/END`) is not legacy: `AgdaDojang.Debug` still emits
it on the fallback path and this server still reads it.

**Advantages**: simple, decoupled from Agda's GHC version, reuses all
existing AgdaDojang macros without modification.

**In-place typechecking**.  The batch tools typecheck the file at its real
path on disk.  `fill_hole` — and `get_goal` on its fallback path (since issue
#108 the lane answers it without touching the file when it can) — must alter
the source (inject the reporting macro, or substitute a candidate), so they
patch the file transiently and restore it afterwards under `bracket_`.  The original is
captured and rewritten as raw bytes (`Data.ByteString`), so the file is
returned byte-for-byte — no encoding or newline round-trip — even if Agda
errors or the call is interrupted.  Checking in place, rather than against a
scratch copy, is what lets a hierarchically-named module embedded in a
library resolve its own name and cross-directory imports the same way it does
for the developer; an earlier scratch-copy approach failed on such modules
with `ModuleDefinedInOtherFile` (issue #66).

**Limitations**: each *verdict-producing* tool call spawns a new Agda process
(cold typechecking, no persistent state) — deliberate, so a verdict is always
batch Agda's own exit code.  The read-only query tools do not pay this cost:
they are served by the persistent interaction lane (issue #75), whose child
holds the loaded file's typechecking state between questions.

**Bounded subprocesses**.  Each call is bounded by `--timeout` and the bound is
enforced by killing the process, not by abandoning it.  `agda` is spawned into its
own process group; its stdout and stderr are drained concurrently on dedicated
threads (so neither stream can fill its pipe buffer and deadlock the other), and
the process is raced against a timer.  On expiry the group gets `SIGINT`, then
`SIGTERM`, and is then reaped with `waitForProcess`, leaving no zombie and no
orphaned `agda` still burning CPU.  This is why `readProcessWithExitCode` could
not simply be wrapped in `System.Timeout.timeout`: that kills the *waiting
Haskell thread*, not the subprocess, and leaks a running `agda` every time it
fires (issue #77).  A timeout is returned as a value, never thrown, which is what
lets the in-place tools' `bracket_` restore run on the timeout path exactly as it
does after a clean typecheck.


### The interaction lane (issue #75)

The second process model, beside the batch subprocess: one persistent
`agda --interaction-json` child per resolved project root, speaking IOTCM
commands, serving the five read-only query tools.  It delivers the persistent
state and millisecond warm latency the library plan promises, for queries only
— verdicts stay with batch `agda`, whose tolerance rules are the ones a build
enforces.  Protocol, lifecycle, and measurements:
[`docs/agda-mcp/agda-mcp-interaction-lane.md`](../docs/agda-mcp/agda-mcp-interaction-lane.md).

### Ask Agda rather than re-derive (issue #106)

Before a new tool — or a new field on an existing one — computes an answer
by scanning source text, ask the question this server holds itself to: can
Agda answer this?  If it can, in output a call already captures or through
an interaction-lane query, then Agda's answer is the authority and the
local derivation is at most a pre-flight approximation and a fallback:

```
answer = whatAgdaSaid <|> whatWeDerived
```

so that a change in Agda's output degrades the field to the derived value,
never to a wrong value.  This is issue #72's rule for verdicts ("the
diagnostics text never gets a vote") applied to informational fields.

The worked example is issue #100.  `get_goal` reported its `module` field
from a file scan, so a literate file whose *prose* opened a line with
`module` was reported under the prose's name — while Agda had already
printed the true answer (`Checking LiterateMd (…).`) in output the same
call had captured.  Agda's answer is also better than a correct scan's:
it is the name Agda *resolved* from the include path (`AnonModule` for a
`module _ where` header, `Proofs.Use` for a hierarchical module), where a
scan can only repeat what the header claims, and the difference between
the two is a diagnosis.  The field is now sourced from Agda on both paths
(the lane's stored `liModule`, the batch run's `agdaModuleNameOf`), with
the declared-name scan as the `<|>` fallback (PRs 105 and 110).

The audit that applied this rule to every derived answer in the server —
verdicts, the issues that delegated each one, and the measurements for
diagnostics and `checkedFromSource` — is
[`docs/agda-mcp/agda-mcp-ask-agda-audit.md`](../docs/agda-mcp/agda-mcp-ask-agda-audit.md).
Two of its conclusions matter when writing new code: project resolution
(`AgdaMCP.Project`) stays local because no Agda query exists for it, by
measurement rather than oversight; and Agda's *silence* is weaker evidence
than Agda's *answer* — a client flag (`--trace-imports=0`) can mute the
progress channel that `checkedFromSource` infers from, which issue #114
answered by reading the argv the server itself assembled
(`AgdaMCP.Agda.progressChannelMuted`) and withholding every answer that
would have rested on a silence the server caused: `checkedFromSource` in
both lanes, and `check_project`'s `modulesChecked`.  The rule that
generalizes: before inferring anything from what Agda did *not* say, check
that the channel it would have said it on was open.


### Future: Agda-as-a-library

The long-term plan is to use Agda as a Haskell library (persistent
interaction state, warm caches, sub-second latency).  This requires
AgdaDojang to expose a Haskell API, which is tracked in the roadmap.


### Interaction model

A typical agent session follows a propose-check-refine loop:

> `check_file` → `get_goal` → reason about the goal → `fill_hole` → read feedback → revise or advance.

This is the same loop that AgdaDojang's scripted policy backend demo implements, but
driven by a frontier LLM instead of a fixed script.

The loop ends where the project's own gate does: `check_project` once the file is
green, which is the check a human runs before calling the work done, and the one
an agent otherwise runs from a shell, with the exit-code trap that entails.


### MCP Transport

We implement a minimal MCP stdio transport (~200 lines in `AgdaMCP.Server`) rather
than using the `mcp-server` Hackage library.  The original reason was a version
floor — that library needs `base >= 4.20`, i.e. GHC 9.10+, and the backend then
pinned an older GHC — and that reason has since expired: the pinned toolchain is
GHC 9.10.3.  What keeps the hand-rolled transport is that it is small and does
exactly what is needed: `initialize`, `tools/list`, `tools/call`, and nothing else
to keep in step with an upstream API.

---

## Related Documents

- [`agda-dojang/README.md`](../agda-dojang/README.md): Action space reference (the macros this server wraps).
- [`docs/adr/0002-agda-mcp.md`](../docs/adr/0002-agda-mcp.md): The server's design record (every decision, the evidence that earned it, and its open follow-ups); read it before the two notes below.
- [`docs/agda-mcp/agda-mcp-interaction-lane.md`](../docs/agda-mcp/agda-mcp-interaction-lane.md): The interaction lane's design record — the two-lane policy, the wire protocol as observed, lifecycle, and economics (issue #75).
- [`docs/agda-mcp/agda-mcp-ask-agda-audit.md`](../docs/agda-mcp/agda-mcp-ask-agda-audit.md): The issue-#106 audit — every answer computed from source text, its verdict, and the diagnostics and `checkedFromSource` measurements.
- [`docs/policy_contract.md`](../docs/policy_contract.md): Policy backend JSON contract (compatible with our tool schemas).
- [`docs/architecture.md`](../docs/architecture.md): System architecture overview.


## References

- [Model Context Protocol specification (2025-11-25)][MCP-spec]
- [MCP documentation and guides][MCP]
- [Haskell `mcp-server` library on Hackage][hackage-mcp-server]
- [Haskell `mcp` library on Hackage][hackage-mcp]
- [Rust MCP SDK (`rmcp`)][rust-sdk]: considered but not chosen; see above
- [MANIFESTO.md §2.2: Bridge Layer][MANIFESTO]
- [PLAN.md: project roadmap][PLAN]


[MCP]: https://modelcontextprotocol.io/
[MCP-spec]: https://modelcontextprotocol.io/specification/2025-11-25
[hackage-mcp]: https://hackage.haskell.org/package/mcp
[hackage-mcp-server]: https://hackage.haskell.org/package/mcp-server
[rust-sdk]: https://github.com/modelcontextprotocol/rust-sdk
[AgdaDojang]: ../agda-dojang/
[MANIFESTO]: ../docs/MANIFESTO.md
[PLAN]: ../docs/PLAN.md
[M1-2]: https://github.com/formalverification/agda-native-air/issues/10
[M1-3]: https://github.com/formalverification/agda-native-air/issues/11
