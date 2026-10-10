<!-- File: agda-mcp/examples/README.md -->

# agda-mcp client-config examples

Ready-to-adapt MCP client configurations for using `agda-mcp` from **another Agda
project** (one whose code lives outside this repository).  JSON does not allow
comments, so the templates use `/ABS/PATH/TO/...` placeholders; copy one into the
project you are editing as `.mcp.json`, replace the placeholders with absolute
paths, and keep it out of that project's git history.

See
[`docs/HowToRun.md` §13.5](../../docs/HowToRun.md#135--using-agda-mcp-on-another-agda-project)
for the full walkthrough, the caveats (`get_goal` needs `AgdaDojang.Debug`;
absolute paths; toolchain match), and the alternative `claude mcp add` command.

Both templates check the client project with **its own pinned Agda**, never this
repository's, so the client's version pins stay authoritative (issue #103), and
both anchor the server in the client's checkout with `--cwd`.  The server
splits `--agda-flags` and `--check-command` on whitespace, with no quoting, so
no path inside either may contain a space; keep the gc-roots under a
space-free directory such as `~/.cache`.

## `agda-algebras.mcp.json`

Connects a Claude Code session working on
[`agda-algebras`](https://github.com/ualib/agda-algebras) to this repository's
`agda-mcp`.  One copy of the file serves every agda-algebras worktree: it names
no worktree, and the server anchors itself in whichever one Claude Code was
started from.

Realize the three machine-specific inputs once, from any directory:

```sh
# agda-algebras's own Agda, wrapped with its standard library, gc-rooted:
nix build /ABS/PATH/TO/agda-algebras -o /ABS/PATH/TO/agda-algebras-agda-root
# the libraries file that wrapper reads, gc-rooted under a path of its own:
nix build "$(grep -oE -- '--library-file=[^ ]+' /ABS/PATH/TO/agda-algebras-agda-root/bin/agda | cut -d= -f2)" \
  -o /ABS/PATH/TO/agda-algebras-libraries
# the search corpus (docs/corpora/agda-algebras-v0.1.md):
gh release download agda-algebras-corpus-v0.1 -R formalverification/agda-native-air \
  -p corpus.jsonl.gz -D /ABS/PATH/TO/agda-algebras-corpus-v0.1
gunzip -k /ABS/PATH/TO/agda-algebras-corpus-v0.1/corpus.jsonl.gz
```

Re-run the two `nix build` lines after agda-algebras's `flake.lock` moves; they
re-point the same symlinks.  Then install the file in each checkout you work in:

```sh
cd /ABS/PATH/TO/agda-algebras/<a-worktree>
cp /ABS/PATH/TO/agda-native-air/agda-mcp/examples/agda-algebras.mcp.json ./.mcp.json
# edit ./.mcp.json: replace every /ABS/PATH/TO/... placeholder with a real path
echo '.mcp.json' >> "$(git rev-parse --git-common-dir)/info/exclude"   # once per clone
claude   # approve the "agda" server when prompted; then /mcp
```

Every copy is identical, so a single edited copy symlinked into each worktree
serves as well.  `git rev-parse --git-common-dir` names the clone's shared `.git`
directory, whose `info/exclude` covers every worktree; in a worktree, `.git` is a
file, so the literal path `.git/info/exclude` does not exist there.

Each binding does one job; they are the following:

+  `--cwd ${PWD}`: Claude Code expands `${PWD}` to the directory it was started
   from when it spawns the server, so each session is anchored in its own
   worktree.  Agda finds that worktree's `agda-algebras.agda-lib` from there,
   resolves the modules in that tree, and writes their `.agdai` interfaces to its
   `_build/`, which the worktree's own `nix develop` runs share.  A client
   that does not expand variables passes `${PWD}` through literally, and the
   server stops with `cannot enter --cwd`; give such a client the worktree's
   absolute path instead.
+  `--agda-bin`: agda-algebras's wrapped Agda, the one its `nix develop` and CI
   use, through the gc-rooted symlink built above.
+  `--agda-flags`: two flags.  `--library-file` names the same registry the
   wrapper bakes in, for the server's sake: `agda-mcp` cannot see inside the
   wrapper, and without the flag it reads this repository's `agda/libraries`
   (the `$AGDA_DIR` of the shell `run-server.sh` enters), which registers
   agda-algebras at the flake-pinned store copy and so refuses every worktree
   file with a `rootMismatch`.  The wrapper's registry names only the standard
   library; the worktree's own library comes from the `.agda-lib` in the working
   directory.  `-i .../agda-dojang/agda` makes the `AgdaDojang.Debug` module
   that `get_goal` splices in visible to agda-algebras's Agda.
+  `--corpus`: turns on the search tools (`search_by_name`, `search_by_type`,
   `get_dependencies`, and `search_in_scope`, which `--expose` must name).
   Without it the server presents 10 tools, not 13.
+  `--check-command`: agda-algebras's own gate, `make check`, which regenerates
   the `Everything` aggregators and checks them.  `AGDA=` points it at the same
   Agda; left alone, `make` would run the first `agda` on the server's `PATH`,
   which is this repository's.

Start Claude Code inside an agda-algebras checkout.  Wherever Agda finds no
`.agda-lib`, it falls back to `$AGDA_DIR/defaults`, and the shell
`run-server.sh` enters sets that to this repository's, which asks for
`agda-dojang`.  So a session started anywhere else (the directory holding the
worktrees, say) gets `Library 'agda-dojang' not found` from `check_file`, and
the lane tools cannot load a scratch module that sits outside every checkout
(`get_goal` still answers, through its batch fallback); keep scratch modules
inside the worktree.  The template does not select `-l standard-library` to
cover those cases: an `-l` flag makes Agda ignore the worktree's own
`agda-algebras.agda-lib`, so its modules would resolve only through the
server's fallback include path and lose the `flags:` line the library sets.

Nothing this registration reads is written by another session, so any number of
sessions in different worktrees run side by side.  (The template this one
replaced set `AGDA_ALGEBRAS_ROOT` instead, and every launch rewrote this
repository's `agda/libraries` to name its own worktree.  A second session in
another worktree re-pointed the registry, and the first session's server then
refused its own files.)

## `fls.mcp.json`

Connects a Claude Code session working on
[formal-ledger-specifications](https://github.com/IntersectMBO/formal-ledger-specifications)
to this repository's `agda-mcp`, with the checking done by **fls's own pinned
Agda**, never this repository's, so IOG's version pins stay authoritative
(issue #103).  This is the template for any client project that pins its own
toolchain, and the agda-algebras template above follows it.  Three bindings carry
the arrangement:

+  `--cwd`: the absolute path to the fls checkout.  Agda anchors its project
   discovery (the nearest `*.agda-lib`) to the directory it runs in, so this is
   what makes fls modules resolve, and write their `.agdai` interfaces, exactly
   as fls's own `nix develop --command agda` does.  The template carries an
   absolute placeholder; under Claude Code, `${PWD}` in its place, as in the
   agda-algebras template, lets one copy serve every fls worktree.
+  `--agda-bin`: fls's wrapped Agda, through a gc-rooted symlink realized once:

   ```sh
   nix build /ABS/PATH/TO/formal-ledger-specifications#fls-agdaWithPackages \
     -o /ABS/PATH/TO/fls-agda-root
   ```

   The wrapper bakes in fls's `--library-file` (standard-library 2.3 and the four
   IOG libraries), so it is self-contained from any directory.  Re-run the same
   command after fls's `flake.lock` moves; it re-points the same symlink.  Until
   you re-run it, the server keeps checking with the previously pinned toolchain.
+  `--agda-flags`: only `-i .../agda-dojang/agda`, so the `AgdaDojang.Debug`
   module that `get_goal` splices in is visible to fls's Agda (it compiles under
   Agda 2.8.0 and 2.9.0).  Everything else rides in the wrapper.

The `--check-command` gate checks `src/Ledger.lagda.md`, the module that
aggregates the whole specification.  To make `check_project` double as a
staleness canary for the gc-root, run the gate through the flake instead,
always the *current* pin, at the cost of a Nix evaluation per run:

```json
"--check-command", "env -u LD_LIBRARY_PATH nix develop /ABS/PATH/TO/formal-ledger-specifications --command agda src/Ledger.lagda.md"
```

(`env -u LD_LIBRARY_PATH` because the backend shell hosting the server exports
an `LD_LIBRARY_PATH` that breaks a nested `nix`.)

## One worktree per branch

A registration that names a worktree binds the server to that worktree, and one
that rewrites a registry other sessions read binds every session to whichever
launched last.  The agda-algebras template does neither: `--cwd ${PWD}` anchors
each session in the directory it was started from, and the registry it names is
a read-only store file.  Start Claude Code in the worktree you are editing and
the server checks that worktree, however many other sessions are running.

The server still guards against the case a registration cannot rule out: if the
file you ask about sits under a different checkout of a library its registry
places elsewhere, it refuses, naming both roots and the libraries file that
disagrees with the file, instead of resolving your imports against the other
tree and reporting success.  Every response also carries a `project` block naming
the tree it checked, so you can confirm this without triggering the failure.  See
[`docs/agda-mcp/agda-mcp-environment.md`](../../docs/agda-mcp/agda-mcp-environment.md)
for the resolution rules and for what the server writes where.

## `check_project` on an external project

`scripts/run-server.sh` starts the server from *this* repository's root.  Both
templates pass `--cwd`, which moves the server into the client project, and
`--check-command`, which names that project's gate, so `check_project` with no
arguments runs the right gate in the right tree.  A registration without `--cwd`
leaves `check_project` anchored at agda-native-air, where it would run
**agda-native-air's** gate; pass the project you mean:

```json
{"name": "check_project", "arguments": {"projectPath": "/ABS/PATH/TO/agda-algebras/<your-worktree>"}}
```

The response's `gate.searchedFrom` and `command.cwd` always name the directory
that was searched and the one the gate ran in, so a call anchored at the wrong
project is visible in its own answer rather than something to discover later.
If the external project's gate is not a `make check`, nor an `Everything`
module, name it once in the config with
`"--check-command", "<the command your gate is>"`; it is split on whitespace and
run without a shell.
