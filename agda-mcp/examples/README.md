<!-- File: agda-mcp/examples/README.md -->

# agda-mcp client-config examples

Ready-to-adapt MCP client configurations for using `agda-mcp` from **another Agda
project** (one whose code lives outside this repository).  JSON does not allow
comments, so the templates use `/ABS/PATH/TO/...` placeholders; copy one into the
worktree you are editing, replace the placeholders with absolute paths, and keep it
out of that project's git history.

See [`docs/HowToRun.md` §13.5](../../docs/HowToRun.md) for the full walkthrough,
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
