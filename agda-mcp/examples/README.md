<!-- File: agda-mcp/examples/README.md -->

# agda-mcp client-config examples

Ready-to-adapt MCP client configurations for using `agda-mcp` from **another Agda
project** (one whose code lives outside this repository).  JSON does not allow
comments, so the templates use `/ABS/PATH/TO/...` placeholders; copy one into the
worktree you are editing, replace the placeholders with absolute paths, and keep it
out of that project's git history.

See [`docs/HowToRun.md` §13.5](../../docs/HowToRun.md#135--using-agda-mcp-on-another-agda-project) for the full walkthrough,
the caveats (`get_goal` needs `AgdaDojang.Debug`; absolute paths; toolchain match),
and the alternative `claude mcp add` command.

## `agda-algebras.mcp.json`

Connects a Claude Code session working on [`agda-algebras`](https://github.com/ualib/agda-algebras)
to this repository's `agda-mcp`.  Usage, from the agda-algebras worktree root:

```sh
cp /ABS/PATH/TO/agda-native-air/agda-mcp/examples/agda-algebras.mcp.json ./.mcp.json
# edit ./.mcp.json — replace both /ABS/PATH/TO/... placeholders with real paths
echo '.mcp.json' >> .git/info/exclude   # ignore it locally without touching tracked .gitignore
claude                                    # approve the "agda" server when prompted; then /mcp
```

Two fields carry the machine-specific paths:

+  `command` — the absolute path to this repo's `scripts/run-server.sh`.
+  `env.AGDA_ALGEBRAS_ROOT` — the absolute path to your agda-algebras checkout/worktree
   (the directory containing its `.agda-lib`), so the backend shell registers the
   library and `-l agda-algebras` resolves.

For a different library, change the `-l <name>` flag and the matching `*_ROOT`
variable (e.g. `AGDA_CATEGORIES_ROOT`, `AGDA_TYPETOPOLOGY_ROOT`); add `--corpus
/ABS/PATH/TO/...jsonl` to enable the search tools.

## `fls.mcp.json`

Connects a Claude Code session working on
[formal-ledger-specifications](https://github.com/IntersectMBO/formal-ledger-specifications)
to this repository's `agda-mcp` — with the checking done by **fls's own pinned
Agda**, never this repository's, so IOG's version pins stay authoritative
(issue #103).  This is the template for any client project that pins its own
toolchain; the agda-algebras template above is instead for a library checked
*with* this repository's Agda.  Three bindings carry the arrangement:

+  `--cwd` — the absolute path to the fls checkout.  Agda anchors its project
   discovery (the nearest `*.agda-lib`) to the directory it runs in, so this is
   what makes fls modules resolve — and write their `.agdai` interfaces — exactly
   as fls's own `nix develop --command agda` does.
+  `--agda-bin` — fls's wrapped Agda, through a gc-rooted symlink realised once:

   ```sh
   nix build /ABS/PATH/TO/formal-ledger-specifications#fls-agdaWithPackages \
     -o /ABS/PATH/TO/fls-agda-root
   ```

   The wrapper bakes in fls's `--library-file` (standard-library 2.3 and the four
   IOG libraries), so it is self-contained from any directory.  Re-run the same
   command after fls's `flake.lock` moves; it re-points the same symlink.  Until
   you re-run it, the server keeps checking with the previously pinned toolchain.
+  `--agda-flags` — only `-i .../agda-dojang/agda`, so the `AgdaDojang.Debug`
   module that `get_goal` splices in is visible to fls's Agda (it imports only
   builtins, so it compiles under any Agda 2.8).  Everything else rides in the
   wrapper.

The `--check-command` gate checks `src/Ledger.lagda.md`, the module that
aggregates the whole specification.  To make `check_project` double as a
staleness canary for the gc-root, run the gate through the flake instead —
always the *current* pin, at the cost of a Nix evaluation per run:

```json
"--check-command", "env -u LD_LIBRARY_PATH nix develop /ABS/PATH/TO/formal-ledger-specifications --command agda src/Ledger.lagda.md"
```

(`env -u LD_LIBRARY_PATH` because the backend shell hosting the server exports
an `LD_LIBRARY_PATH` that breaks a nested `nix`.)

## One worktree per branch

`AGDA_ALGEBRAS_ROOT` binds the server to one checkout, so a `.mcp.json` copied
between worktrees — or a server left running while you move to another branch's
worktree — points at the wrong tree.  The server no longer answers such a call:
if the file you ask about sits under a different checkout of a library it has
registered elsewhere, it refuses, naming both roots and the libraries file that
disagrees with the file, instead of resolving your imports against the other
tree and reporting success.  Every response also carries a `project` block naming
the tree it checked, so you can confirm this without triggering the failure.

Copy the template into each worktree separately and set `AGDA_ALGEBRAS_ROOT` to
that worktree.  See [`docs/agda-mcp-environment.md`](../../docs/agda-mcp-environment.md)
for the resolution rules and for what the server writes where.

## `check_project` on an external project

`scripts/run-server.sh` starts the server from *this* repository's root, so that
is the working directory `check_project` anchors at when you give it none — and
it would run **agda-native-air's** gate, not the one you are working on.  (A
registration that passes `--cwd`, like `fls.mcp.json`, has already moved that
anchor to the client project, so this concern is the agda-algebras template's.)
Pass the project you mean:

```json
{"name": "check_project", "arguments": {"projectPath": "/ABS/PATH/TO/agda-algebras/<your-worktree>"}}
```

The response's `gate.searchedFrom` and `command.cwd` always name the directory
that was searched and the one the gate ran in, so a call anchored at the wrong
project is visible in its own answer rather than something to discover later.
If the external project's gate is not a `make check` — nor an `Everything`
module — name it once in the config with
`"--check-command", "<the command your gate is>"`; it is split on whitespace and
run without a shell.
