# agda-mcp improvements — executive summary

This document (`docs/agda-mcp-improvements-summary.md`) condenses the state of the `agda-mcp` hardening effort tracked by issue #68 — what the server is, what the field test found, what has landed, and what remains — for anyone returning to the project after time away.  It is a navigation aid, not a source of truth; the authoritative material is listed at the end.  Status is as of 2026-08-16.

## What agda-mcp is and where it sits

+  `agda-mcp` is a small Haskell server speaking the Model Context Protocol over stdio, giving AI coding agents structured tools for working with Agda: `check_file`, `get_diagnostics`, `get_goal`, and `fill_hole`, plus corpus-backed search tools (`search_by_name`, `search_by_type`, `get_dependencies`) when started with `--corpus`.  It calls the pinned `agda` binary as a batch subprocess per request; Agda-as-a-library is the long-term plan.
+  Within `agda-native-air`, it is one of the three core components of the interaction layer between frontier models and Agda: `agda-dojang` (the Agda-side reflection harness whose `reportGoalCtx` macro `get_goal` uses), `agda-mcp` (the bridge agents actually call), and `agda-strux` (structured corpus extraction feeding the search tools and the Milestone 2 retrieval layer).
+  On the roadmap it is the centerpiece of Milestone 1 (frontier agent solves real proofs through the MCP interface) and the delivery vehicle for Milestone 2 retrieval and Milestone 3 counterexample tools.

## The field test that drives the current wave

+  In July 2026 a Claude Code session formalized FLRP RP-2 in `ualib/agda-algebras` — roughly 1200 lines of literate Agda over about fifteen type-check iterations — with `agda-mcp` configured and its tools listed.  The headline datum: the agent never called the server once, preferring bare `agda <file>` from the shell every time.
+  The agent's own post-mortem became `docs/feedback/flrp-agda-mcp-improvements.md`, and every claim in it was then re-verified against the live server before issues were filed (its § 7 addendum records that verification).  Verification confirmed the worst of it, refuted one claim, and found two new bugs.
+  The resulting plan is issue #68, organized in three lanes: P0 is trust (the tools must never say "ok" when batch Agda would say no), P1 is reach (things the shell cannot do), P2 is economics and ergonomics.  The acceptance metric for the whole wave is blunt: the next real literate-repo session reaches for the MCP instead of the shell.

## The improvements

### P0. Trust (all landed)

+  **Truthful `fill_hole` verdict** (#69, PR 81, merged).  `fill_hole` reported `ok` for candidates that left unsolved metas or constraints behind, while `agda` exited 42 on identical content.  A candidate is now `ok` only if the file passes batch Agda, tolerating nothing but open holes' `[UnsolvedInteractionMetas]`.
+  **`get_goal` returns the actual goal** (#70, PR 82, merged).  The tool reported the reporting macro's own unsolved type (e.g. `(x₁ : _3 x) → _5 x x₁`) instead of the hole's documented goal.
+  **A real hole model** (#71, PR 88, merged).  Hole detection matched only the literal token `{!!}`, missing `{! !}` / `{! e !}` / `?` while counting — and even filling — tokens in comments and prose.  The new `AgdaMCP.Holes` module ports Agda 2.8.0's literate masking and a model of its lexer, so hole enumeration agrees with Agda's interaction points; parity tests against batch Agda pin this.
+  **First-class literate Agda** (#73, PR 88, merged).  All literate flavours (`.lagda`, `.lagda.md`, `.lagda.tex`, `.lagda.rst`, `.lagda.org`, `.lagda.tree`) are masked to their code regions with positions reported in literate-file coordinates, so prose can never be a hole and a `.lagda.md` behaves exactly like the same code in a `.agda`.  This matters because `agda-algebras` is entirely literate and its prose discusses holes constantly.
+  **Explicit batch verdict and contract** (#72, PR 95, open).  Verification refuted the "check_file green on unsolved metas" claim — the server was already batch-strict — but nothing said so, and an agent chooses tools by reading two-line descriptions.  Every response now carries a `verdict` naming the equivalent `agda` command, what green means, and Agda's exit code, plus a `command` echo of binary, argument vector, and cwd; `success` is derived from the exit code and never from parsing Agda's prose.  The four tool descriptions carry the client-visible contract, so a `tools/list` dump alone answers whether green means the build passes.

### P1. Reach beyond the shell

+  **Enforced timeout with timing visibility** (#77, PR 89, merged).  `--timeout` was parsed and then ignored, so a hung Agda blocked a tool call forever.  The subprocess group is now killed on a SIGINT → SIGTERM → SIGKILL ladder at the bound, every response carries `elapsedMs` and a tri-state `checkedFromSource` cache signal, and the default bound was raised from 30 s to 300 s so cold interface builds are not aborted.
+  **Structured diagnostics** (#74, PR 94, merged).  Diagnostics shipped as severity plus prose with no source positions at all — the parser split on the comma of Agda's old `file:10,5-15` format while 2.8.0 emits `file:9.12-13` — it dropped any error printed without a location, and only the header line survived.  Each one now carries a machine-readable `code`, the `file` and `range`, the bounded full message body, and an `involved` payload (expected/actual, candidates, missing exports, the origin of a clashing definition, one entry per unsolved meta), capped by `maxDiagnostics` with the pre-cap total reported and ordered most likely root cause first.  One fixture per error class of the field report's § 5 corpus asserts the code, the range, and the payload § 5 names.
+  **Root resolution and environment transparency** (#76, PR 95, open — landed with #72, whose response echo it shares).  No response said which tree was checked, and a stale `AGDA_ALGEBRAS_ROOT` could silently typecheck a different worktree while reporting success.  The new `AgdaMCP.Project` resolves the library context per call from the requested file's nearest `*.agda-lib`, falls back to the server-start configuration and says which was used, and refuses outright — before `agda` is spawned — when the file belongs to a different checkout of a library the server has registered elsewhere.  The stray untracked `agda/` directory the field report saw is reproduced, explained, and fixed: the shellHook derived its root from the client's working directory.  See `docs/agda-mcp-environment.md`.
+  **Live scope, type, and definition queries** (#75, open — after the current batch).  `scope_at`, `resolve_name`, `type_of`, `normalize`, `exports_of`, `definition_of`: answers the shell cannot give without reading source, and the strongest reason for an agent to prefer the server.  The #71 hole-model groundwork (Agda's interaction points as source of truth) feeds directly into this.

### P2. Economics and ergonomics

+  **Whole-project check tool** (#78, open — next batch).  The field session's real gate was a 10–20 minute `make check` run four times as backgrounded Bash, grepping logs because a wrapper masked the exit code.  `check_project` runs the project's own gate, never misreports its exit status, and returns the first error structured; this is the call that would replace that session's shell usage entirely.
+  **Stable hole handles** (#79, open — unblocked now that #71 has landed).  Indices shift whenever an earlier hole is filled, turning multi-hole edits into bookkeeping.  Accept `(line, column)` or a stable id alongside `holeIndex`, and return the updated hole list from every `fill_hole` so the client re-anchors without a second call.

## Measurement and publication

+  **Measured re-run** (#83, open — unblocked once the trust wave is contractual).  Replay a comparable real `agda-algebras` task against the hardened server with a fresh agent that knows nothing of the server's internals, and record per-tool call counts, iterations to green, and the moments the agent chose server versus shell.  This is the experiment that checks whether the wave achieved its one metric; #72's contract descriptions are the prerequisite, since descriptions are all a fresh agent reads, and they are in PR 95.
+  **Tech report** (#86, draft PR 87 in progress).  A write-up of the field test and hardening cycle: baseline session, verification methodology, fixes, and the re-run results.
+  **Demo page** (#85, open).  An animated session replay and corpus-search demo on GitHub Pages; independent of the server work.

## Near-term sequencing

+  Merged so far, in order: PR 88 (#71 + #73), PR 89 (#77), and PR 94 (#74), each rebased over the last.
+  In review: PR 95 (#72 + #76 together, sharing the response-echo plumbing), which completes the P0 trust lane.
+  Next, as parallel work: #78 (`check_project`); then #79 and #75 on top of the new hole model; then the #83 re-run as the wave's acceptance measurement.
+  Related later work that builds on this surface: corpus-backed retrieval tools in the server (#17, M2-3), counterexample-search tools (#24, M3-2), a local completion backend (#29, M4-3), and `makeOverlay` performance (#43).

## Where the details live

+  Issue #68 (tracking): verification results, the full plan, and sequencing rationale.
+  `docs/feedback/flrp-agda-mcp-improvements.md`: the field report with the § 7 verification addendum; § 5 is the error corpus the diagnostics fixtures are built from.
+  `agda-mcp/README.md`: tool-by-tool reference, architecture notes, and the response-field tables.
+  `docs/agda-mcp-environment.md`: what the server and its shellHook write where, how the library context is resolved per call, and the operator checklist for pointing a client at one worktree among several.
+  `docs/roadmap.md`: the milestone structure (M0–M4) that places agda-mcp within the project.
+  `docs/HowToRun.md`: § 13 — configuring the server against an external Agda project such as `agda-algebras`.
