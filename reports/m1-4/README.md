<!-- File: reports/m1-4/README.md -->

# M1-4 Demo Results: Claude Code + agda-mcp End-to-End

## Overview

The reports in the `reports/m1-4/` directory document the first end-to-end
demonstrations of a frontier AI agent (Claude Code, Sonnet 4.6) using the agda-mcp
MCP server to inspect and solve proof obligations in Agda.

**Date**: 2026-04-03
**Agent**: Claude Code v2.1.63 (Sonnet 4.6)
**Server**: agda-mcp v0.2.0
**Agda**: 2.8.0
**Transport**: stdio via `scripts/run-server.sh` (Nix-wrapped)


## Results Summary

| Fixture | Holes | Solved | Attempts | Wall-clock | Notes |
|---------|-------|--------|----------|------------|-------|
| `Fixture01.agda` | 3 | 3/3 | 7 | 1m 42s | All solved on first attempt. |
| `FixtureStdlibBooleanAlgebra.agda` | 3 | 3/3 | 3 | ~1m 40s | All solved on first attempt; agent studied oracle proofs. |


## Session Transcripts

+  `2026-04-04-222457-ClaudeCode-Fixture01.txt` — identity, unit, reflexivity (simple).  
+  `2026-04-03-213713-ClaudeCode-StdlibBooleanAlgebra.txt` — Boolean algebra
   complements, de Morgan laws (moderate).


## Observations

### What worked

+  MCP connection stayed stable through entire sessions (crash-proof server loop held up).
+  Agent correctly used `get_goal`, `fill_hole`, `check_file`, and `get_diagnostics`
   with proper parameter names.
+  Agent extracted concrete goal types from `fill_hole` error messages when `get_goal`
   returned unresolved metavariables.
+  For the Boolean algebra fixture, the agent studied oracle solutions in the file and
   adapted them — notably using `goal-deMorgan₁` instead of `oracle-deMorgan₁` in the
   chain proof for deMorgan₂.

### Known limitations

+  **Unresolved metas in goals**.  `get_goal` returns goals with metavariables
   (`_3`, `_5`, ...) when other holes exist in the  file; the agent worked around
   this by reading error messages, but better goal normalization would help.
   (Targeted for M2.)
+  **fill_hole is typecheck-only**.  Validates candidates in a temp file without
   modifying the source.  The agent must use its own Edit tool to persist changes;
   this is by design (separation of concerns)  but was initially confusing to the agent.
+  **Cold start latency**.  First MCP connection takes ~30s due to Nix shell setup;
   subsequent tool calls are faster (~3–5s per Agda invocation).
+  **No search tools used**.  The agent relied on file reading for context rather
   than `search_by_name` or `search_by_type`; testing search-driven proof discovery
   is a goal for the agda-algebras slice.

### Failure modes observed

+  **Wrong parameter names on first session**.  Claude Code initially sent
   `file`/`hole_number` instead of `filePath`/`holeIndex`; resolved by crash-proofing
   the server (the error response now includes the correct schema).
+  **Agent hallucinated results after server crash**.  When the server disconnected
   (pre-hardening), Claude Code fabricated a plausible goal table from file reading;
   the crash-proof loop eliminated this.


## Reproducing These Results

### Prerequisites

+  Nix (with flakes enabled)
+  Node.js 18+ (for Claude Code)
+  Claude Code: `npm install -g @anthropic-ai/claude-code`
+  Anthropic API key or Claude Pro subscription

### Steps

1. Clone the repo and enter the worktree:
   ```sh
   cd agda-native-air
   ```

2. Ensure the Nix backend shell generates the `libraries` file:
   ```sh
   nix develop .#backend
   # Ctrl-D to exit — the file persists
   ```

3. Build agda-mcp (inside the backend shell):
   ```sh
   nix develop .#backend
   cd agda-mcp && cabal build && cd ..
   ```

4. Verify the server works (outside any Nix shell):

   ```sh
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test","version":"0.1"}}}' \
     | ./scripts/run-server.sh \
         --agda-flags "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library" \
         2>/dev/null
   ```
   After a few seconds, you should see a JSON-RPC response tht includes `serverInfo.name: "agda-mcp"`.

5. Launch Claude Code:
   ```sh
   MCP_TIMEOUT=120000 claude
   ```

6. Verify connection: type `/mcp` and confirm `agda · ✔ connected`.

7. Test:
   ```
   Use the agda MCP tool "get_goal" with filePath
   "agda-dojang/data/fixtures/Fixture01.agda" and holeIndex 0.
   Show me the raw result.
   ```

---

## Next Steps

- [ ] Run agent on 5–10 agda-algebras proof obligations (without oracles).
- [ ] Test search tool usage for premise discovery.
- [ ] Measure performance without oracle hints in prompt.
```
