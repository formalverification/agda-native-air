<!-- File: docs/agda-mcp/registering-a-project.md -->

# Registering agda-mcp for your Agda project

A registration serves a project only while the Agda it names, and the
libraries that Agda reads, are the project's own.  [Connecting an
agent][connecting] says how each harness registers a server, and its section
*Your own Agda project* says what `--agda-bin` and `--library-file` do.  This
page says which Agda to name for each kind of project setup, how it stays
current, and how to tell from inside a session that it has not.

Terms used below, as follows:

+  A *flake* is a Nix project definition (`flake.nix`); its *lock*
   (`flake.lock`) pins the revision of everything it builds from; an
   *attribute* is one thing the flake exports, such as
   `fls-agdaWithPackages`.
+  An *Agda environment* is an Agda wrapped with the libraries a project
   depends on (nixpkgs' `agda.withPackages`), so that it reads its own
   libraries file wherever it runs.
+  A *pin* is a symlink to one build of such an environment, made by hand
   with `nix build <checkout>#<attribute> -o <link>`; the link also keeps
   that build from garbage collection (it is a *gc root*).

Every template below is a `.mcp.json` for Claude Code or Copilot CLI, placed
at the checkout's root and kept out of its history (`echo .mcp.json >> "$(git
rev-parse --git-common-dir)/info/exclude"`, once per clone); the Codex and
Kimi Code sections of [Connecting an agent][connecting] give the same command
and arguments in their formats.  `/ABS/AIR` stands for the absolute path of
an agda-native-air checkout in which the server is built (*Before any
harness: the server*, on the same page).  A session serves the checkout it
starts in: start it in the worktree you are editing.

## Which setup is yours

| Your project's setup | `--agda-bin` | Kept current by | Section |
| --- | --- | --- | --- |
| A flake exports an Agda environment (formal-ledger-specifications) | `/ABS/AIR/scripts/agda-for-flake.sh`, with the attribute in `env` | the launcher: one build per change of the checkout's lock or other non-Agda files | [Flake](#a-flake-that-exports-an-agda-environment) |
| A dev shell writes a per-checkout binary and libraries file (ualib/agda-algebras) | `${PWD}/.agda/bin/agda` | entering the dev shell in that checkout | [Dev shell](#a-dev-shell-that-writes-a-per-checkout-binary) |
| No Nix: an `agda` you installed | its absolute path | you | [No Nix](#no-nix) |
| Your library builds with this repository's Agda 2.9.0 and standard library 2.3 | none | this repository's flake | [This repository's](#this-repositorys-agda) |

Do not register a pin.  It matches one lock: when the project's lock moves,
the pin keeps serving the old environment, and every load fails inside a
dependency (`NotInScope`), which reads as broken code.
formal-ledger-specifications ran that way for two weeks ([field
report][field-report]).  If you keep one anyway, the launcher says at startup
when the project's flake has moved past it (see *Failure signatures*).

## A flake that exports an Agda environment

*Run*, 2026-11-06, on formal-ledger-specifications, Agda 2.8.0.

[`scripts/agda-for-flake.sh`][agda-for-flake] stands in for Agda.  It finds
the nearest `flake.nix` at or above the directory it runs in, computes a key
from the checkout's tracked files other than Agda sources, builds the
attribute once per key (`nix build <checkout>#<attribute>`, kept as a gc root
under `~/.cache/agda-mcp/<attribute>/`), and runs that build's `bin/agda`
with every argument it was given.  Each checkout so gets the Agda its own
lock names, with nothing to refresh by hand.  The header of the script says
why the key covers what it covers (in short: Nix reads every tracked file,
and formal-ledger-specifications builds its Agda from Haskell sources, not
only from its lock).

```json
{
  "mcpServers": {
    "agda": {
      "command": "/ABS/AIR/scripts/run-server.sh",
      "args": [
        "--cwd", "${PWD}",
        "--agda-bin", "/ABS/AIR/scripts/agda-for-flake.sh",
        "--agda-flags", "-i /ABS/AIR/agda-dojang/agda",
        "--timeout", "900",
        "--check-command", "/ABS/AIR/scripts/agda-for-flake.sh src/Ledger.lagda.md",
        "--check-timeout", "3600"
      ],
      "env": { "AGDA_FLAKE_ATTR": "fls-agdaWithPackages" }
    }
  }
}
```

+  `AGDA_FLAKE_ATTR` names the attribute: an Agda environment of the
   project's dependencies, never a package built from the project's own
   sources (Agda would then find the project twice, and the key leaves Agda
   sources out).
+  `--check-command` runs the same launcher, so the gate checks with the
   same Agda; name your project's top module.
+  There is no `--library-file`.  The environment's wrapper carries its own,
   which registers the dependencies, and Agda finds the project from the
   checkout's `.agda-lib`.
+  A first call on a new key costs about a second when the environment is
   already in the store (a `nix develop` in that checkout has built it), and
   a full build when it is not, which can outlast a tool call's timeout.  The
   build is then killed with the call, keeps what it finished, and resumes on
   the next call; the verification step below builds it outside any timeout.
+  An edit to a tracked file that is not an Agda source (a changelog, a
   script) makes a new key, so the first call after it evaluates the flake
   again, about a second, and links the same build.  On 2026-11-06, two
   branches that differ from `master` in such files did exactly that; a
   worktree on the 2026-02-17 lock got that lock's environment, and `master`
   kept its own.

**Verify**.  From the checkout, before the first session, build and run the
Agda once, as follows:

```sh
cd /path/to/your/checkout
AGDA_FLAKE_ATTR=fls-agdaWithPackages /ABS/AIR/scripts/agda-for-flake.sh --version
```

The first run prints `agda-for-flake: building ...` and the version; later
runs print the version alone, 30 ms after they start.  Then run the probe in
*Verifying any registration*: on `src/Ledger/Prelude.lagda.md` it answered
`Agda.Primitive.Set₁` after a 14 s load.

## A dev shell that writes a per-checkout binary

*Run*, 2026-11-06, on ualib/agda-algebras, Agda 2.9.0.

Some projects' dev shells write a wrapped Agda and a libraries file into the
checkout on every entry; agda-algebras's `nix develop` writes `.agda/bin/agda`
and `.agda/libraries` (gitignored).  Register those through `${PWD}`, which
Claude Code expands to the directory the session starts in:

```json
{
  "mcpServers": {
    "agda": {
      "command": "/ABS/AIR/scripts/run-server.sh",
      "args": [
        "--cwd", "${PWD}",
        "--agda-bin", "${PWD}/.agda/bin/agda",
        "--agda-flags", "--library-file=${PWD}/.agda/libraries -i /ABS/AIR/agda-dojang/agda",
        "--timeout", "600",
        "--check-command", "make check AGDA=${PWD}/.agda/bin/agda",
        "--check-timeout", "3600"
      ]
    }
  }
}
```

+  `--library-file` names the file the wrapper reads, for the server's sake:
   the server reads it to decide which checkout a file belongs to, and cannot
   see inside the wrapper.  Without it the server reads your user libraries
   file, which may register the project at another checkout.
+  The binary follows the checkout's lock only once the dev shell has been
   entered again: after a pull that moves the lock, run `nix develop` once in
   that checkout before the next session.  The binary is no gc root either,
   so a `nix store gc` can remove the Agda it names until the next entry.

**Verify**.  `nix develop --command true` once in the checkout, then
`.agda/bin/agda --version`, then the probe below: on
`src/Overture/Operations.lagda.md` it answered `Type₁` (agda-algebras's name
for `Set₁`).

## No Nix

Name the `agda` you installed, and a libraries file that registers every
library the project depends on (Agda finds the project itself from its
`.agda-lib`), as follows:

```json
"args": [
  "--cwd", "${PWD}",
  "--agda-bin", "/usr/local/bin/agda",
  "--agda-flags", "--library-file=/home/you/.config/agda/libraries -i /ABS/AIR/agda-dojang/agda",
  "--timeout", "600"
]
```

Nothing keeps it current but you: a new Agda or library version is an edit
to your system and to that file.  (The server itself still needs Nix to
build, once.)

**Verify**.  `agda --version`, then the probe below.

## This repository's Agda

If your library builds with Agda 2.9.0 and the standard library 2.3, you need
no Agda flags: the launcher's shell supplies both, and its libraries file
registers `standard-library`, `agda-dojang` and `agda-algebras`.  The
template is the first one in *Your own Agda project* of [Connecting an
agent][connecting].  It follows this repository's flake, so a pull here can
change the Agda your project is checked with.

**Verify**.  The probe below.

## Verifying any registration

From the checkout a session will start in, send the server the requests a
session would, through the registration's own command, as follows:

```sh
cd /path/to/your/checkout
FILE="$PWD/src/Some/Module.agda"   # any module of the project
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"type_of","arguments":{"filePath":"'"$FILE"'","expr":"Set","verbose":true}}}' \
  | env AGDA_FLAKE_ATTR=fls-agdaWithPackages /ABS/AIR/scripts/run-server.sh \
      --cwd "$PWD" --agda-bin /ABS/AIR/scripts/agda-for-flake.sh --agda-flags "-i /ABS/AIR/agda-dojang/agda" \
      2>verify.err | tail -1
```

Pass the registration's arguments, with `"$PWD"` for `${PWD}`, and its `env`
(only the flake setup has one).  A working registration answers the type of
`Set` in the module's scope once the module has loaded (seconds, or minutes
for a first load of a large library), and with `verbose` the answer says who
answered: `lane.agdaVersion`, `command.binary`, and `project.root`, which
must be the checkout.  An `error` object instead is Agda's own; read it with
the next section, and `verify.err` for the server's log.

## Failure signatures

What each misconfiguration looks like from inside a session, each seen on
2026-11-06 unless marked, as follows:

| Symptom | Cause | Fix |
| --- | --- | --- |
| `NotInScope`, or another scope error, in a file of a dependency library, at the first load of any module | a pin built from an older lock | register [the launcher](#a-flake-that-exports-an-agda-environment), or rebuild the pin |
| `agda-mcp: --agda-bin ... is /nix/store/..., but the flake at ... now builds ...` in the server's log | the same, said at startup by the launcher, about a second in | as above |
| `ClashingDefinition` or `NotInScope` in a dependency, for a file of a sibling worktree | a lane tool loaded a worktree on another lock with the session's Agda | ask that worktree's own session |
| `AmbiguousTopLevelModuleName`, naming the file in two checkouts | a batch tool (`check_file`) was asked about a file of a sibling worktree | ask that worktree's own session |
| `rootMismatch`, naming a libraries file | that file registers the project at another checkout | pass `--library-file` naming the checkout's own file |
| `LibraryError`: `Library 'X' not found` | the libraries file Agda read lacks `X`: a file missing a dependency, or a session started outside every checkout (Agda then falls back to its defaults; measured 2026-09-29) | add `X`; start the session in the checkout |
| `stderrTail` holding `agda-for-flake: ...` (lane tools), or `success: false`, `exitCode` 69 and no diagnostics (`check_file`) | the launcher ran no Agda: no flake or no lock at or above the checkout, no attribute, no `nix`, or a failed build (offline, say) | the line says which; `check_file` leaves it in the server's log |
| The harness shows `CONNECTION_CLOSED` | the server never started | [Known issues][known-issues] |

Claude Code keeps each server's log, the launcher's lines among them, under
`~/.cache/claude-cli-nodejs/<project-dir>/mcp-logs-agda/`.

[agda-for-flake]: ../../scripts/agda-for-flake.sh
[connecting]: connecting-an-agent.md
[field-report]: ../field-reports/2026-11-06-fls-stale-pin-and-proof-repairs.md
[known-issues]: connecting-an-agent.md#known-issues
