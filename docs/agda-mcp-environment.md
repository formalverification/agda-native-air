<!-- File: agda-native-air/docs/agda-mcp-environment.md -->

# agda-mcp: what the server writes, and which tree it checks

Environment forensics for the `agda-mcp` server, written to close the open question in [issue #76](https://github.com/formalverification/agda-native-air/issues/76): an untracked `agda/` directory containing `defaults` and `libraries` appeared in the root of an `ualib/agda-algebras` worktree during a field session, and the reporter could not tell whether the MCP setup, the Nix `agda` wrapper, or a direct `agda` invocation had created it.

Short answer: the MCP setup created it, by way of the flake's shellHook, and it created a second stray directory (`target/`) at the same time.  Both are fixed on this branch.  The rest of this document is the reproduction, the full inventory of what gets written where, and the resolution rules the server now follows so that a response always names the tree it checked.

## 1.  Reproduction

The MCP client launches the server through [`scripts/run-server.sh`](../scripts/run-server.sh), which enters `nix develop .#backend`.  `nix develop` runs the shellHook in the **caller's working directory**, and an MCP client spawns its servers with its own project as the working directory.  The hook then did this:

```sh
ROOT="$PWD"
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT="$(git rev-parse --show-toplevel)"
fi
export AGDA_DIR="$ROOT/agda"
mkdir -p "$AGDA_DIR"
```

so `git rev-parse` answered about the *client's* checkout, not about this one.  Reproduced directly, with an empty git repository standing in for the client's worktree:

```sh
mkdir /tmp/faketree && cd /tmp/faketree && git init -q
nix develop /path/to/agda-native-air#backend --command bash -c 'echo "$AGDA_DIR"'
```

Before the fix, that printed `/tmp/faketree/agda` and left behind:

```
/tmp/faketree/agda/libraries    # 2 lines, see below
/tmp/faketree/agda/defaults     # agda-dojang, standard-library
/tmp/faketree/target/           # global-logging/, task-temp-directory/
```

Two things are worth naming precisely.

+  The `agda/libraries` written into the foreign tree is not merely misplaced, it is **broken**: its first line reads `/tmp/faketree/agda-dojang/agda-dojang.agda-lib`, a path that does not exist, because the hook composed it from the wrong `ROOT`.  Anything that later read that registry would resolve `agda-dojang` to nothing.
+  The `target/` directory comes from the banner's `sbt --version` probe, which sbt answers by creating `target/` in whatever directory it is invoked from.  It is the same class of defect — generated state written into somebody else's project — and it was not in the original report only because nobody looked for it.

The field report's worry was that an untracked directory in a project root is "one careless `git add -A` away from being committed".  In `ualib/agda-algebras` that is exactly right: its `.gitignore` covers `/.agda/`, with a dot, not `agda/`.

## 2.  Fixes on this branch

+  **`scripts/run-server.sh`** exports `AGDA_NATIVE_AIR_ROOT` and `cd`s to this repository before entering the shell, so the hook's answer no longer depends on the client's working directory, and so sbt's probe runs here rather than there.
+  **`flake.nix`** resolves `ROOT` from three candidates in order — the explicit `AGDA_NATIVE_AIR_ROOT` anchor, the enclosing git checkout, then `$PWD` — and **validates** each against a marker only this repository carries, `agda-dojang/agda-dojang.agda-lib`.  A candidate without the marker is not silently accepted: the shell still starts (so an unusual layout is not fatal), but it prints a warning naming what it is writing where and how to fix it.
+  The `sbt --version` probe in the backend shell now runs from `$ROOT`, whose `target/` is already gitignored here.

Verified after the fix, from the same foreign working directory:

| Case | `AGDA_DIR` | Stray files in the client tree |
| --- | --- | --- |
| No anchor, foreign cwd | `<client>/agda` + loud warning | `agda/`, `target/` |
| With `AGDA_NATIVE_AIR_ROOT` (what `run-server.sh` now sets) | `<agda-native-air>/agda` | none |
| Full `run-server.sh` launch, foreign cwd | `<agda-native-air>/agda` | none |

## 3.  Inventory: what writes what, where

| Writer | Path | When | Tracked? |
| --- | --- | --- | --- |
| flake shellHook | `$AGDA_DIR/libraries` — one `*.agda-lib` path per line | every shell entry, overwritten from the `*_ROOT` variables then in effect | gitignored (`agda/`) |
| flake shellHook | `$AGDA_DIR/defaults` | every shell entry | gitignored |
| sbt version probe | `$ROOT/target/` | every shell entry of a shell whose banner probes sbt | gitignored |
| `agda` (the typechecker) | `*.agdai` beside each checked source | every check that re-typechecks from source | gitignored |
| `agda-mcp` itself | nothing | — | — |

The server writes no state of its own.  `get_goal` and `fill_hole` do rewrite the requested source file transiently, but restore it byte for byte under `bracket_` — including on the timeout path, which the test suite pins.

Two further environment facts an operator needs.

+  **`AGDA_DIR` is exported unconditionally by the hook**, so setting it before entering the shell has no effect.  It is also where Agda looks for a `libraries` file when none is passed explicitly, which is why `AgdaMCP.Project` consults `$AGDA_DIR/libraries` (then `~/.agda/libraries`) as its fallback registry.
+  **The Nix `agda` on `PATH` is a wrapper that already supplies `--library-file`**, pointing into the Nix store:

   ```sh
   exec /nix/store/…-Agda-2.8.0-bin/bin/agda --with-compiler=… --library-file=/nix/store/…/libraries "$@"
   ```

   The caller's `--library-file` arrives after it and wins, since Agda's option parser takes the last occurrence.  The shell *function* `agda()` that the hook defines — the one that adds `--no-default-libraries` and the `--library` flags — is not visible to a subprocess, so `agda-mcp` never gets it; that is why the client configuration must pass `--library-file` and `-l` explicitly.  Every response now echoes the resolved binary under `command.binary`, so which `agda` ran is no longer a guess.

## 4.  Which tree gets checked

Before any of that, a prior question the server used to answer silently: **which file did you name?**  A relative `filePath` is resolved against the *server's* working directory, because that is the only directory the server knows — it is a separate process and is never told where its client stands — and `scripts/run-server.sh` pins that directory to this repository.  A relative path that really does name a file there is checked, which is what keeps the in-repo client working; one that does not is refused with a `pathError` object naming the path as resolved, the working directory it was resolved against, and the rule (issue #101).  Guessing instead — trying the path under each registered library root — was rejected for the reason this whole section exists: it would sometimes answer green about a tree nobody named.

`agda/libraries` is shared, mutable, process-global state: the hook rewrites it on **every** shell entry from whatever `AGDA_ALGEBRAS_ROOT` (or `AGDA_CATEGORIES_ROOT`, …) is in effect at that moment.  With one worktree per branch — the `ualib/agda-algebras` workflow — a second shell entry elsewhere silently repoints the registry a long-running server is still reading.  That is the hazard § 3.6 of [the field report](feedback/flrp-agda-mcp-improvements.md) describes: not a crash, but a green answer about a tree nobody asked about.

The server now resolves the library context per call, in [`agda-mcp/src/AgdaMCP/Project.hs`](../agda-mcp/src/AgdaMCP/Project.hs):

1.  Walk up from the requested file to the nearest `*.agda-lib`, stopping at a repository boundary (a directory holding `.git`) so the search cannot wander into an unrelated checkout above the project.
2.  Read the registry `agda` will actually use — the `--library-file` from the server's flags, else `$AGDA_DIR/libraries`, else `~/.agda/libraries` — **fresh on every call**, because a registry snapshotted at startup is not necessarily the one the next call will read.
3.  Compare, and act:
    +  the registry gives the file's library name a **different** root — refuse the call, naming both roots (see below);
    +  the registry gives that name the **same** root — proceed unchanged; the server's `-l` flags already reach it;
    +  the registry has **never heard of** the library — proceed, adding the library's own `include:` directories with `-i` so the file resolves in its own tree;
    +  there is **no `*.agda-lib`** above the file — proceed on the server-start configuration, and report `rootSource: "server-config"` so the caller knows that is what happened.

Every response carries the outcome under `project`, and the refusal in case 3 looks like this — a structured `rootMismatch` object alongside the prose:

```
agda-mcp: refusing to check /home/w/git/ualib/agda-algebras/branch-B/src/FLRP/Bridge.lagda.md
  — it belongs to a different checkout than the one this server has registered.
  the file's nearest *.agda-lib declares library 'agda-algebras' rooted at
    /home/w/git/ualib/agda-algebras/branch-B
  but the libraries file /home/w/git/…/agda-native-air/agda/libraries
    registers 'agda-algebras' at /home/w/git/ualib/agda-algebras/branch-A
  Checking here would resolve this file's imports against
    /home/w/git/ualib/agda-algebras/branch-A
    and report success about a tree you did not ask about.
  Fix: restart the server against /home/w/git/ualib/agda-algebras/branch-B
    (set the matching *_ROOT variable, or pass a --library-file whose
    'agda-algebras' entry points there).
```

The refusal is returned **before** `agda` is spawned and before any in-place patching, which the test suite pins by pointing `agdaBin` at a path that does not exist and asserting the call still fails as a refusal rather than as a crash.

One limit of the check is worth stating plainly, because it is invisible otherwise: the comparison is against the registry, so a configured `--library-file` that **does not exist** leaves nothing to compare against and no mismatch can be found.  The response says so — `project.librariesFile` still names the configured path (it is in `command.args`, so omitting it would make the echo read as "no registry configured") and `project.librariesFileMissing` is `true`.  A stale `.mcp.json` naming a deleted worktree's `agda/libraries` is exactly this case.

One limit worth stating.  The name comparison is exact, so a library that declares `agda-algebras` in one checkout and `agda-algebras-2.0` in another reads as two different libraries rather than as a mismatch.  That is the right reading — Agda treats the suffix as a version — but it means the check catches stale *worktrees*, not stale *versions*.

## 5.  Operator checklist

+  Launch the server through `scripts/run-server.sh`; it anchors the shell to this repository.  Launching the binary some other way is fine, but then `--library-file` and `-l` are entirely yours to get right.
+  Pass **absolute** `filePath`s from any client that is not standing in this repository.  A relative one is resolved against the server's working directory, not yours; when it names nothing there the call is refused with both paths in the message, so a wrong answer is not among the outcomes.
+  Read `project.root` in any response to confirm which tree answered.  If it is not the tree you are editing, the server will have told you so rather than guessed.
+  A `[agda] WARNING: this does not look like the agda-native-air checkout` line on startup means the shell could not identify this repository; the Agda configuration it wrote will not work, and nothing downstream will be trustworthy.
+  Nothing needs adding to a client project's `.gitignore` any more — the server writes nothing into it.  If you want belt and braces for older launches, `agda/` and `target/` are the two names to cover.
