<!-- File: agda-mcp/examples/README.md -->

# agda-mcp client-config examples

Ready-to-adapt MCP client configurations for using `agda-mcp` from **another Agda
project** (one whose code lives outside this repository).  The templates use
`/ABS/PATH/TO/...` placeholders; copy one into the project you are editing (a
`.mcp.json` template as `.mcp.json`, the Codex template as `.codex/config.toml`),
replace the placeholders with absolute paths, and keep it out of that project's
git history.

See
[Connecting an agent](../../docs/agda-mcp/connecting-an-agent.md)
for the walkthrough in each agent harness, including the `claude mcp add` command,
and
[`docs/HowToRun.md` § 13.4](../../docs/HowToRun.md#134--using-agda-mcp-on-another-agda-project)
for the caveats (`get_goal` needs `AgdaDojang.Debug`; absolute paths; toolchain
match).

Every template checks the client project with **its own Agda**, never this
repository's, so the client's version pins stay authoritative (issue #103), and
each anchors the server in the client's checkout with `--cwd`.  None names a
hand-built pin, which matches one lock and goes stale in silence when the
project's lock moves (issue #342); [Registering a
project](../../docs/agda-mcp/registering-a-project.md) has the setup each
template is an instance of, and how to verify it.  The server splits
`--agda-flags` and `--check-command` on whitespace, with no quoting, so no path
inside either may contain a space.

## `agda-algebras.mcp.json`

Connects a Claude Code session working on
[`agda-algebras`](https://github.com/ualib/agda-algebras) to this repository's
`agda-mcp`.  One copy of the file serves every agda-algebras worktree: it names
no worktree, and the server anchors itself in whichever one Claude Code was
started from.

agda-algebras's dev shell writes its Agda into the checkout: every `nix
develop` there writes `.agda/bin/agda` (the flake's Agda, wrapped with the
standard library) and `.agda/libraries` (gitignored), from that checkout's own
`flake.lock`.  The template names both through `${PWD}`, so each worktree is
checked with the Agda its own lock names.  Download the search corpus once,
from any directory:

```sh
# the search corpus (docs/corpora/agda-algebras-v0.1.md):
gh release download agda-algebras-corpus-v0.1 -R formalverification/agda-native-air \
  -p corpus.jsonl.gz -D /ABS/PATH/TO/agda-algebras-corpus-v0.1
gunzip -k /ABS/PATH/TO/agda-algebras-corpus-v0.1/corpus.jsonl.gz
```

Then install the file in each checkout you work in, after entering its dev
shell once:

```sh
cd /ABS/PATH/TO/agda-algebras/<a-worktree>
nix develop --command true   # writes .agda/; again after the lock moves
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
   that does not expand variables passes `${PWD}` through literally, and
   `scripts/run-server.sh` substitutes the directory it was started in
   (issue #242), so the same file serves such a client, provided it starts
   the server in the worktree.  The bare binary, run without the launcher,
   refuses the literal string by name.
+  `--agda-bin`: the worktree's own `.agda/bin/agda`, the Agda its `nix
   develop` uses, written by its last entry.  It is no gc root: after a `nix
   store gc`, or a pull that moves the lock, enter the dev shell again.
+  `--agda-flags`: two flags.  `--library-file` names the registry the wrapper
   reads, `.agda/libraries`, for the server's sake: `agda-mcp` cannot see
   inside the wrapper, and without the flag it reads this repository's
   `agda/libraries` (the `$AGDA_DIR` of the shell `run-server.sh` enters),
   which registers agda-algebras at the flake-pinned store copy and so refuses
   every worktree file with a `rootMismatch`.  The worktree's registry names
   the standard library and the worktree's own `agda-algebras.agda-lib`.
   `-i .../agda-dojang/agda` makes the `AgdaDojang.Debug` module that
   `get_goal` splices in visible to agda-algebras's Agda.
+  `--corpus`: turns on the search tools (`search_by_name`, `search_by_type`,
   `get_dependencies`, and `search_in_scope`, which `--expose` must name).
   Without it the server presents 10 tools, not 13.
+  `--check-command`: agda-algebras's own gate, `make check`, which regenerates
   the `Everything` aggregators and checks them.  `AGDA=` points it at the same
   Agda; left alone, `make` would run the first `agda` on the server's `PATH`,
   which is this repository's.

Verified on 2026-11-06 with the agda-algebras `master` checkout and a sibling
worktree: each server answered from its own root.

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

One binding is optional, and the template leaves it out.  An `env` block naming
a built server, `"env": {"AGDA_MCP_BIN": "/ABS/PATH/TO/agda-mcp"}` (the path
`cabal list-bin exe:agda-mcp` prints in a checkout that has built it), lets the
launcher skip the shell, since the template already names its Agda with
`--agda-bin` (issue #249).  The server then answers `initialize` once it has
loaded the corpus (3 to 4 s), where the shell path adds about 4 s before that.
It runs in the client's environment, so the `make` and `env` its gate runs and
the `$AGDA_DIR/defaults` of the previous paragraph are the client's, not this
repository's.  The template's `--library-file` and `AGDA=` keep the rest the
same on both paths.  [`agda-mcp/README.md`](../README.md), § *Without the
shell*, has the whole list.

Nothing this registration reads is written by a session in another worktree,
so any number of sessions in different worktrees run side by side.  (An earlier
template set `AGDA_ALGEBRAS_ROOT` instead, and every launch rewrote this
repository's `agda/libraries` to name its own worktree.  A second session in
another worktree re-pointed the registry, and the first session's server then
refused its own files.  The template after it named one hand-built pin for
every worktree, which could match only one lock.)

## `agda-algebras.codex.toml`

The same agda-algebras registration as a `[mcp_servers.agda]` table, for an
OpenAI Codex CLI session, which does not read `.mcp.json`.  It needs the same
inputs (the corpus, and a dev shell entered once), and is installed per
checkout as `.codex/config.toml` (Codex reads a project's file only once the
project is trusted) or appended to `~/.codex/config.toml`.  It differs from
the `.mcp.json` template in four ways, each explained in a comment in the file,
as follows:

+  It passes no `--cwd`: Codex expands no variables and starts the server in the
   directory the session started in, which the launcher then passes as `--cwd`
   (issue #242), and substitutes for each `${PWD}` in the other arguments.
+  It sets `startup_timeout_sec` and `tool_timeout_sec` above Codex's defaults
   (10 and 60 seconds), which the launcher's shell entry and a cold check
   overrun.
+  It sets `required = true`, so that `codex exec` holds its first request until
   the server is up.
+  It approves every tool but `check_project` without a prompt, since the
   server's tools carry no read-only annotation and `codex exec`, which cannot
   ask, would refuse them all.

Tested on 2026-10-11 with Codex CLI 0.162.1 in an agda-algebras checkout, when
the table named a pinned Agda: the server presented thirteen tools, and
`check_file` answered from that checkout.  Its current form answered the same
way on 2026-11-06, started as Codex starts it, but not in Codex itself.

## `fls.mcp.json`

Connects a Claude Code session working on
[formal-ledger-specifications](https://github.com/IntersectMBO/formal-ledger-specifications)
to this repository's `agda-mcp`, with the checking done by **fls's own Agda**,
the one its flake exports as `fls-agdaWithPackages` (Agda 2.8.0 with fls's
custom backend, wrapped with standard-library 2.3 and the four IOG libraries),
never this repository's, so IOG's version pins stay authoritative (issue #103).
This is the template for any project whose flake exports an Agda environment.
Three bindings carry the arrangement:

+  `--cwd ${PWD}`: the checkout the session starts in.  Agda anchors its
   project discovery (the nearest `*.agda-lib`) to the directory it runs in,
   so this is what makes fls modules resolve, and write their `.agdai`
   interfaces, exactly as fls's own `nix develop --command agda` does, in
   whichever worktree the session started.
+  `--agda-bin`: [`scripts/agda-for-flake.sh`](../../scripts/agda-for-flake.sh),
   with `AGDA_FLAKE_ATTR` in `env` naming the attribute.  It builds
   `fls-agdaWithPackages` from the checkout it runs in, once per key (the
   checkout's tracked files other than Agda sources, `flake.lock` among them),
   keeps the build as a gc root under `~/.cache/agda-mcp/`, and runs it.  So a
   worktree on another lock gets that lock's Agda, and a lock that moves costs
   one build, with nothing to refresh by hand.  It replaces the hand-built pin
   (`nix build <checkout>#fls-agdaWithPackages -o <link>`) this template used
   to name, which went stale for two weeks when fls's lock moved on 2026-10-22
   (issue #342).  The `--check-command` gate runs the same launcher, on
   `src/Ledger.lagda.md`, the module that aggregates the whole specification.
+  `--agda-flags`: only `-i .../agda-dojang/agda`, so the `AgdaDojang.Debug`
   module that `get_goal` splices in is visible to fls's Agda (it compiles
   under Agda 2.8.0 and 2.9.0).  The wrapper carries its own libraries file.

Before the first session in a checkout, build and run its Agda once, outside
any tool call's timeout:

```sh
cd /ABS/PATH/TO/formal-ledger-specifications
AGDA_FLAKE_ATTR=fls-agdaWithPackages /ABS/PATH/TO/agda-native-air/scripts/agda-for-flake.sh --version
```

Verified on 2026-11-06 with fls `master` and a worktree on the lock of
2026-02-17: each got its own lock's environment, and `type_of` loaded
`Ledger.Prelude` in each in 14 s.

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

`scripts/run-server.sh` starts the server in the directory the client started
the launcher in, unless `--cwd` names another (issue #242).  Both templates pass
`--cwd`, which names the client project explicitly, and `--check-command`,
which names that project's gate, so `check_project` with no arguments runs the
right gate in the right tree.  A registration without `--cwd` anchors
`check_project` wherever the client started, which is the right tree only when
the client starts at the project's root; a session started in agda-native-air
would run **agda-native-air's** gate.  When in doubt, pass the project you mean:

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
