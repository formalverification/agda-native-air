<!-- File: docs/agda-mcp/connecting-an-agent.md -->

# Connecting an agent to agda-mcp

This page takes a reader from nothing to an agent session that calls
agda-mcp's `check_file`.  Three terms first, as follows:

+  An *agent harness* is the program that runs a language model as an agent
   in your terminal: it reads and edits your files and runs commands, with
   your permission.  Claude Code, OpenAI's Codex CLI, GitHub's Copilot CLI
   and Moonshot's Kimi Code CLI are four.
+  The *Model Context Protocol* (MCP) is how a harness gives its model tools
   that another program provides, and that program is an *MCP server*.
   agda-mcp is one: it answers tool calls such as `check_file` (does this
   file type-check?) and `get_goal` (what does this hole need?) by running
   Agda on your files.
+  A *registration* is the few lines of JSON or TOML that tell a harness how
   to start a server.  The harness starts the server when a session begins
   and stops it when the session ends.

The server's tools run Agda and report what it says; editing files and
running other commands are the harness's own tools, under the harness's own
permissions.

There is one section per harness: Claude Code with Anthropic's models;
Claude Code pointed at another provider's Anthropic-compatible endpoint
(Moonshot's Kimi K3, or a local model through Ollama); Kimi Code CLI; Codex
CLI; and Copilot CLI.  Each takes the same eight steps in the same order, as
follows:

1.  **Plan and cost**.  It says what to sign up for, the price and the
    allowance, and what the provider may do with the code a session sends.
2.  **Install**.  It gives the command, its prerequisites, and the version
    tested.
3.  **Sign in**.  It covers the browser flow, the flow for a machine without
    a browser, and the key route.
4.  **Model and effort**.  It names the model id, and the flag or key that
    sets the reasoning effort, with the levels it takes.
5.  **Instructions and skills**.  It lists the instruction files the harness
    reads and the skill directories it searches.
6.  **Registering agda-mcp**.  It gives the registration in the harness's own
    format, for this repository and for another project.
7.  **Smoke test**.  It runs the same three calls as every other section,
    non-interactively.
8.  **Known issues**.  It records what the field reports of [#243] and this
    page's own runs met.

**Run and read**.  Every step says which it is.  A step marked *run* was
carried out on 2026-10-11 on Ubuntu 24.04 with the harness version it names.
A step marked *read* comes from the vendor's page, read that day and linked,
and was not carried out here (a sign-up, a purchase, a provider whose key had
no balance).  Prices, allowances and model lists change monthly: the vendors'
pages are the source, and this page is the map.

A key or a token never goes in a file inside a repository, and the
registrations below hold none.  Keep a key in your harness's own credential
store, or in a file outside every repository that only you can read, and pass
it to the one command that needs it.

## The harnesses at a glance

Prices are the vendors' own, read on 2026-10-11, before tax.  No route was
run at no cost: Copilot Free, which chooses its models itself, and Ollama
were not tried.

| Harness | Models | Plan or key, and price | Registers the server in | Smoke test, 2026-10-11 |
| --- | --- | --- | --- | --- |
| Claude Code 2.1.282 | Anthropic's Claude models | Claude Pro, $20 a month ($17 billed annually); or an Anthropic Console API key, per token | a project's `.mcp.json`, or `claude mcp add` | passed (run) |
| Claude Code, another provider | Kimi K3; a local model | a Moonshot platform key, $3.00 in and $15.00 out per million tokens; Ollama, free on your own hardware | as Claude Code | Kimi K3: reached Moonshot, refused for want of balance (run); Ollama: read |
| Kimi Code CLI 2.1.1 | Kimi K3 | the Moonshot platform key, or a Kimi membership | `.kimi-code/mcp.json` | stopped by folder trust and the balance (run) |
| Codex CLI 0.162.1 | GPT-6.1 Sol, GPT-6 Astra | ChatGPT Plus, $20 a month; or an OpenAI API key, per token | an `[mcp_servers.agda]` table in `.codex/config.toml` | passed (run) |
| Copilot CLI 1.0.95 | the models a Copilot plan offers, among them GPT-6.1 Sol, Claude and Kimi K3 | Copilot Pro, $10 a month for 1,500 AI credits; Pro+, $39, for GPT-6.1 Sol | a project's `.mcp.json`, or `~/.copilot/mcp-config.json` | passed (run) |

## Before any harness: the server

*Run*, 2026-10-11.

Every registration on this page runs [`scripts/run-server.sh`][launcher], the
launcher in this repository.  It enters the flake's `.#backend` shell, so
`agda`, GHC and the standard library come from Nix rather than from your
`PATH`; it keeps the shell's banner off the JSON-RPC stream; and it starts
the server in the directory the harness started it in, substituting that
directory for a literal `${PWD}` in an argument (issue [#242]).  The server
therefore needs a checkout of this repository and a build in it, once per
checkout, as follows:

```sh
git clone https://github.com/formalverification/agda-native-air.git
cd agda-native-air
nix develop .#backend --command bash -c 'cd agda-mcp && cabal build -v0 exe:agda-mcp'
make agda-mcp-smoke   # optional, from the checkout's root: a JSON-RPC round trip, no agent
```

Nix 2.28 or later is the one prerequisite (from [nixos.org/download]), with
its `nix-command` and `flakes` features turned on
(`experimental-features = nix-command flakes` in `nix.conf`).  The flake pins
Agda 2.9.0 and the standard library, so nothing else needs installing, and an
Agda you already have is left alone.  The first `nix develop` asks once
whether to trust the flake's binary cache, `formalverification.cachix.org`;
answering yes is what lets Nix download the toolchain prebuilt rather than
build it.  That first entry is the expensive one: the shell the launcher
enters was 13.9 GiB on disk here (988 store paths), since it carries the
toolchains the rest of this repository uses as well.  After it, the server's
build took 31 s in a fresh worktree.  [`docs/HowToRun.md` § 13][howtorun-13]
covers building, testing and running the server by hand, and the server's
[command-line options] say what each flag below does.

Driven directly over JSON-RPC, the launcher answered `initialize` 2.5 s after
it started, and 5.8 s with the 224 MB agda-algebras corpus loaded; the
sessions of [#243] waited 5 to 16 s, and [#249] measured up to 32 s when the
checkout's working tree was dirty, which makes `nix develop` evaluate the
flake again.  The build step above has already downloaded the shell, so a
harness never waits for that; if a garbage collection removes it, run the
build step again before the next session.  Each harness's startup timeout
has to cover the half minute, and each section says how to set it.  A
registration that names your own Agda can skip the shell, and the half
minute with it (see *Your own Agda project*).

### The smoke test

Every harness gets the same prompt, run from the root of an agda-native-air
checkout, with tool approval limited to the two tools it calls wherever the
harness allows that.  The sections below keep it in a shell variable, as
follows:

```sh
cd /path/to/agda-native-air
PROMPT='Use the agda MCP server and no other tool.  1. List the names of the tools it offers.  2. Call check_file on agda-dojang/data/fixtures/Fixture01.agda and report its success field and how many holes it lists.  3. Call get_goal on the same file with holeIndex 0 and report the goal and the context.  Answer in five lines or fewer.'
```

Success looks like the following:

+  The tool list has ten names, or thirteen when the registration loads a
   search corpus (the repository's `.mcp.json` loads the bundled fixture
   corpus).
+  `check_file` answers `success: false` with three holes and the diagnostic
   `UnsolvedInteractionMetas` (Agda's exit code 42).  The fixture has three
   open holes and a file with holes does not check, so `false` here is the
   server working.
+  `get_goal` on hole 0 answers the goal `A` in the context `A : Set`,
   `x : A`.

An answer that names no tools, or a call that is refused or never returns, is
a registration problem; each section's known issues name the ones met here.

## Your own Agda project

*Run*, 2026-10-11, on a scratch library (an `.agda-lib` that depends only on
`standard-library`, and one module with a hole), driven over JSON-RPC the way
a harness drives the server.

Start the agent in your project, and register the server there: the
launcher starts the server in the directory the session starts in, and Agda
finds your `.agda-lib` by walking up from that directory.  Which Agda then
checks your files depends on the registration, as follows:

+  **This repository's Agda**, by default: Agda 2.9.0 with the standard
   library 2.3 patched for it, and the libraries file the launcher's shell
   writes (`agda/libraries` in the checkout, which registers
   `standard-library`, `agda-dojang` and `agda-algebras`).  Your own
   `~/.agda/libraries` is not read.  If your library type-checks under those
   versions, the registration needs no Agda flags at all.
+  **Your own Agda**: `--agda-bin` names it, and `--library-file`, inside
   `--agda-flags`, names the libraries file it reads.  Pass the libraries
   file even where your Agda finds it unaided: the server reads it too, to
   decide which tree a file belongs to.  The server splits `--agda-flags` on
   whitespace, so no path in it may contain a space.

For Claude Code and Copilot CLI the registration is a `.mcp.json` at your
project's root, as follows; the Codex and Kimi Code sections show the same
command and arguments in their formats.

```json
{
  "mcpServers": {
    "agda": {
      "command": "/path/to/agda-native-air/scripts/run-server.sh",
      "args": ["--timeout", "600"]
    }
  }
}
```

With your own Agda, the arguments are these instead:

```json
"args": [
  "--agda-bin", "/path/to/your/bin/agda",
  "--agda-flags", "--library-file=/path/to/your/.agda/libraries",
  "--timeout", "600"
]
```

Both forms answered on the scratch library: `check_file` gave
`success: false` with the hole and `UnsolvedInteractionMetas`, `get_goal`
gave the goal `suc (n + 0) ≡ suc n` in the context `n : ℕ`, and every
response named the library's own directory as the project root.  The
response's `command` and `project` blocks named the Agda binary and the
libraries file in use, so a reader can always see which Agda answered.  The
rest of the arguments are optional, as follows:

+  `--timeout` bounds one check, in seconds (default 300).  A first check of
   a large library builds Agda's interface files for its whole import graph
   and can take minutes, so 600 is the safer bound.
+  `--corpus` names a search corpus built from a library, which adds the
   three search tools; without one the server offers ten tools.
+  `--check-command` names the project's own gate for `check_project`;
   without it the server looks for a `check` target in the nearest Makefile,
   or an `Everything` module.
+  `-i /path/to/agda-native-air/agda-dojang/agda`, in `--agda-flags`, makes
   the `AgdaDojang.Debug` module visible, which `get_goal`'s fallback imports
   into the file; the templates pass it, and `get_goal` answered here without
   it.

One more setting is optional, and it goes in the registration's environment
rather than its arguments (in a `.mcp.json`, an `"env"` object beside
`"args"`).  With `--agda-bin` given, `"AGDA_MCP_BIN": "/path/to/agda-mcp"`,
the path `cabal list-bin exe:agda-mcp` prints in the checkout after the build
step, makes the launcher run the server without the shell, so it answers in
milliseconds plus any corpus load (issue [#249]).  The server then takes
`make`, `$AGDA_DIR` and the rest of its environment from the harness rather
than from this repository's shell, so pass the libraries file as above and
name your Agda in `--check-command`; [the server's README][without-the-shell]
lists what changes.

What the server does to your files: `check_file` writes Agda's interface
files, as `agda` does; `get_goal` and `fill_hole` patch the file on disk for
the length of a call and restore it byte for byte, on the timeout path too,
so an editor with the file open may notice the file change and change back.
A project that pins its own Agda through Nix (agda-algebras,
formal-ledger-specifications) has a template in
[`agda-mcp/examples/`][examples-readme], with the commands that build the
paths it names.

## Claude Code

The reference harness: every measurement in this repository's benchmark ran
in it.

### Plan and cost

*Read*, 2026-10-11, on Anthropic's [pricing page][claude-pricing],
[data-usage page][claude-data-usage] and the privacy center's
[model-improvement article][claude-privacy-setting].

+  Claude Code needs a Pro, Max, Team, Enterprise or Console account; the
   free claude.ai plan does not include it.  Claude Pro was $20 a month
   billed monthly, or $17 a month billed annually, and Max started at $100
   a month.  Claude Code "shares the same usage limits as the rest of your
   plan".
+  An Anthropic Console API key bills each token at API rates instead, with
   no subscription.
+  What leaves the machine is the prompts, the files a session reads, and
   the tool results, agda-mcp's answers included.  Anthropic "will train new
   models using data from Free, Pro, and Max accounts when this setting is
   on (including when you use Claude Code from these accounts)".  The
   pricing page lists model training on those plans as opt-out; the switch
   is "Help Improve our AI models", under Privacy in claude.ai's settings.
   With it on, Anthropic keeps the data five years; with it off, 30 days.
+  Under commercial terms (Team, Enterprise, and an API key), Anthropic does
   not train on Claude Code's code or prompts unless the customer chooses
   to provide them, and keeps them 30 days.
+  Telemetry carries no code: `DISABLE_TELEMETRY=1` turns off the metrics,
   and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` all non-essential
   traffic.

### Install

*Read*, 2026-10-11, on Anthropic's [setup page][claude-setup]; the version
check was run.

```sh
curl -fsSL https://claude.ai/install.sh | bash   # the recommended native install
brew install --cask claude-code                  # or Homebrew
npm install -g @anthropic-ai/claude-code         # or npm, which needs Node.js 22 or later
claude --version                                 # 2.1.282 here, installed with npm
```

The native install needs no Node.js and updates itself in the background;
the Homebrew install does not update itself.  Ubuntu 20.04, Debian 10,
macOS 13 and Windows 10 1809 are the oldest systems the setup page lists.

### Sign in

*Read*, 2026-10-11, on Anthropic's [authentication page][claude-auth];
`claude auth status` was run.

+  The first `claude` opens a browser to sign in; `/login` in a session
   does the same, and `claude auth status` shows the account in use.
+  Over SSH or in a container, where the browser cannot reach Claude Code's
   local callback, the browser shows a code to paste at the terminal's
   `Paste code here if prompted` prompt.  For CI, `claude setup-token` makes
   a one-year token for the `CLAUDE_CODE_OAUTH_TOKEN` variable.
+  An API key goes in the `ANTHROPIC_API_KEY` environment variable.  When it
   is set, Claude Code uses it instead of a subscription login; an
   interactive session asks once, and `claude -p` uses it without asking.

### Model and effort

*Run* (`claude --help`, 2.1.282) and *read* (Anthropic's
[model configuration page][claude-model-config]).

+  `--model` takes an alias (`opus`, `sonnet`, `haiku`, `fable`) or a full
   model name.  `/model` changes it in a session, and `ANTHROPIC_MODEL` or
   the `model` setting sets a default.
+  `--effort` takes `low`, `medium`, `high`, `xhigh` or `max`, for that
   session only.  `/effort` changes it in a session, and the `effortLevel`
   setting or `CLAUDE_CODE_EFFORT_LEVEL` sets a default; the setting does
   not accept `max`.  The default was `high`, except on Opus 5.5, Sonnet 5.5
   and Haiku 5.5, which default to `medium`.

### Instructions and skills

*Read*, 2026-10-11, on Anthropic's [memory page][claude-memory] and
[skills page][claude-skills]; the symlinks were run.

+  Claude Code reads `CLAUDE.md` (or `.claude/CLAUDE.md`) and
   `CLAUDE.local.md` in the directory it starts in and in every directory
   above it, and `~/.claude/CLAUDE.md` in every session.  It reads
   `AGENTS.md` only where there is no `CLAUDE.md` (version 2.1.277 and
   later).
+  It loads skills from `~/.claude/skills/` and from `.claude/skills/` in
   the start directory and each parent up to the repository root.  A
   `.claude/` directory that is a symlink is followed, and so is a symlinked
   skill inside it (observed on 2026-10-11 in a worktree whose `.claude/` is
   a symlink).

### Registering agda-mcp

*Run*, 2026-10-11, Claude Code 2.1.282, except where marked.

**In this repository** there is nothing to register.  The root's
[`.mcp.json`][root-mcp-json] starts the server through the launcher with the
agda-dojang flags and the bundled fixture corpus, as follows:

```json
{
  "mcpServers": {
    "agda": {
      "command": "./scripts/run-server.sh",
      "args": [
        "--agda-flags", "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library -l agda-algebras",
        "--corpus", "agda-mcp/test/resources/corpus-fixture.jsonl",
        "--timeout", "600",
        "--verbose"
      ]
    }
  }
}
```

Start `claude` at the checkout's root and approve the `agda` server when it
asks.  The paths are relative because the server starts in the directory
Claude Code started in; copied into another project, they point at nothing.

**Approving a project server**.  Claude Code connects a server from a
project's `.mcp.json` only once you approve it.  The first interactive
`claude` in the folder asks, after the folder-trust prompt, and records the
answer in `.claude/settings.local.json` as
`"enabledMcpjsonServers": ["agda"]`.  Writing that line yourself approves
the server too, but only in a folder whose trust prompt you have accepted:
in an untrusted folder the line is ignored and the server stays pending.
`claude -p` cannot ask, and loads a project's servers without asking
([MCP page][claude-mcp], read), so `claude -p` in a cloned repository runs
whatever its `.mcp.json` names: read the file first.
To see the state without starting a session, run the following:

```sh
claude mcp list        # every server, with its state
claude mcp get agda    # one server's scope and state
```

The state reads ``⏸ Pending approval (run `claude` to approve)`` before
approval, `✔ Connected` once the server is approved and answering, and
`✘ Failed to connect` with `CONNECTION_CLOSED` when the launcher fails (see
the known issues).  `claude mcp reset-project-choices` forgets the answers.
In a session, `/mcp` shows `agda · ✔ connected`.

**Another project**: launch Claude Code from that project's checkout and
attach the server there, so that the project keeps its own `CLAUDE.md`, git
history and permissions.  The launcher works from any directory: it enters
this repository's shell, then starts the server back in the project.  For a
library like the one in [Your own Agda project](#your-own-agda-project), the
`.mcp.json` shown there is the whole registration.  A project that pins its
own Agda through Nix registers it in one of two ways, shown here for
agda-algebras; Option A is recommended, since it is a plain file, immune to
shell aliasing, and self-documenting.

*Option A: a project `.mcp.json`*.  Copy the template
[`agda-mcp/examples/agda-algebras.mcp.json`][example-mcp-json] into the
checkout as `.mcp.json`, replace its `/ABS/PATH/TO/...` placeholders with
absolute paths, and keep it out of that project's history.  The template
names no worktree: `--cwd ${PWD}` anchors the server wherever Claude Code
starts, so one file serves every worktree of the clone.  Its three
machine-specific inputs (the project's own Agda, the libraries file that
Agda reads, and the search corpus) are realized once, with the commands in
the [examples README][examples-readme].  Then run the following:

```sh
cd /path/to/your-project
cp /path/to/agda-native-air/agda-mcp/examples/agda-algebras.mcp.json ./.mcp.json
# edit ./.mcp.json: replace every /ABS/PATH/TO/... placeholder with a real path
echo '.mcp.json' >> "$(git rev-parse --git-common-dir)/info/exclude"   # once per clone
claude   # approve the "agda" server when asked; then /mcp shows agda · ✔ connected
```

In a worktree `.git` is a file, so the exclude file is named through
`git rev-parse --git-common-dir`, whose `info/exclude` covers every worktree
of the clone.  What each argument does, and why the server checks the
project with the project's own Agda, is in
[`docs/HowToRun.md` § 13.4][howtorun-134].

*Option B: `claude mcp add`*.  The same registration, from the command
line in the checkout:

```sh
claude mcp add agda --scope local \
  -- /path/to/agda-native-air/scripts/run-server.sh \
     --cwd "$PWD" \
     --agda-bin /path/to/agda-algebras-agda-root/bin/agda \
     --agda-flags "--library-file=/path/to/agda-algebras-libraries -i /path/to/agda-native-air/agda-dojang/agda" \
     --corpus /path/to/agda-algebras-corpus-v0.1/corpus.jsonl \
     --timeout 600 \
     --check-command "make check AGDA=/path/to/agda-algebras-agda-root/bin/agda" \
     --check-timeout 3600
```

`--scope local`, the default, keeps the registration in your own per-project
configuration rather than in the project's files.  That configuration is per
directory, so each worktree needs its own `claude mcp add`, and the shell
expands `"$PWD"` to that worktree when you run it.  (*Run*, verbatim but for
the placeholders, against a throwaway `CLAUDE_CONFIG_DIR`: `claude mcp get
agda` then showed it with the local scope.)  `--scope user` registers the
server for every project instead (*read*).

**One session only**.  `claude --mcp-config <file> --strict-mcp-config`
takes the servers from a registration file for that run and ignores every
other.

**Timeouts**.  Claude Code waits 30 s for a server to start (`MCP_TIMEOUT`,
in milliseconds), which covers the launcher's usual few seconds but not the
32 s of a dirty working tree: `MCP_TIMEOUT=120000 claude` covers that too.
A tool call has no practical bound (`MCP_TOOL_TIMEOUT` defaults to about 28
hours), so the server's own `--timeout` decides (*read*,
[environment variables][claude-env-vars]).

### Smoke test

*Run*, 2026-10-11, Claude Code 2.1.282, Sonnet 5 at `low`, from the
checkout's root:

```sh
claude -p "$PROMPT" --model sonnet --effort low \
  --allowedTools "mcp__agda__check_file mcp__agda__get_goal" --output-format json
```

`--allowedTools` names the two tools; `mcp__agda` would allow the whole
server.  It answered in 15 s and four turns, as follows:

```text
1. Tools: check_file, check_project, get_goal, fill_hole, resolve_name, definition_of, exports_of, normalize, type_of, get_dependencies, get_diagnostics, search_by_name, search_by_type.
2. check_file: success=false (exitCode 42, UnsolvedInteractionMetas), 3 holes listed.
3. get_goal (holeIndex 0): goal is `A`, context is `A : Set`, `x : A`.
```

### Known issues

From this page's runs and the issues each item names, except where marked
read.

+  **A fresh worktree has no server binary** (*run*: this page's own session
   met it).  `dist-newstyle/` is
   gitignored, so the launcher has nothing to run until `cabal build
   exe:agda-mcp` has run in that checkout, or `AGDA_MCP_BIN` names a
   prebuilt binary.  Claude Code shows only `CONNECTION_CLOSED`; the
   launcher's stderr names the missing build.
+  **Deferred tools**.  Claude Code defers MCP tools by default: the model
   sees only the server's tool names, without their descriptions, until it
   searches for them.
   `"alwaysLoad": true` in the server's entry, or `ENABLE_TOOL_SEARCH=false`,
   loads them up front (*read*, [MCP page][claude-mcp]).  The benchmark's
   arms run with the latter.
+  **Descriptions are cut at 2,048 characters**.  The cut applies to each
   tool's description and to the server's instructions alike;
   `CLAUDE_CODE_MAX_MCP_DESCRIPTION_LENGTH` changes the limit (version
   2.1.280 and later, *read*).  agda-mcp's instructions are written to fit.
+  **A wrapped `claude`** (*read*, from [`docs/HowToRun.md`][howtorun-13]).
   If `claude mcp add` fails with an error about an unrecognized option, your
   shell has `claude` aliased or wrapped (under `script`, say), so the
   arguments reach the wrapper.  `type claude` shows it;
   `command claude mcp add ...` bypasses it, or use Option A.
+  **Started from inside `nix develop`**.  This works since issue [#153],
   whose fix clears the `LD_LIBRARY_PATH` that this flake's shells export before
   the launcher runs `nix`.

## Claude Code with another provider's endpoint

Claude Code sends its requests to any endpoint that speaks Anthropic's
Messages API once three environment variables say so, as follows:

+  `ANTHROPIC_BASE_URL` names the provider's endpoint.
+  `ANTHROPIC_AUTH_TOKEN` holds the provider's key, which Claude Code sends
   as a bearer token.
+  `ANTHROPIC_API_KEY` is set to the empty string, so that an Anthropic key
   in your environment is not sent instead.

Then `--model` names the provider's model.  Each provider below takes the
eight steps in order; where a step is Claude Code's own (the install, the
instruction files, the skills, the registration of agda-mcp), it says so,
and the Claude Code section holds for it.

**One session, not every session**.  Moonshot's guide puts these variables
in the `env` block of `~/.claude/settings.json`, which moves every Claude
Code session to the provider and keeps the key in that file.  Set them for
one session instead: a settings file that holds no secret, passed with
`--settings`, and the key read from your shell when the session starts.  An
`env` block overrides the shell's variable of the same name, so the key
must not be in the settings file either.  For Moonshot, as follows:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.moonshot.ai/anthropic",
    "ANTHROPIC_MODEL": "kimi-k3",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "kimi-k3",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "kimi-k3",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "kimi-k3",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "kimi-k3",
    "CLAUDE_CODE_SUBAGENT_MODEL": "kimi-k3"
  }
}
```

```sh
# ~/.config/moonshot/api-key holds the key (chmod 600), outside every repository
claude-kimi() {
  ANTHROPIC_AUTH_TOKEN="$(cat ~/.config/moonshot/api-key)" ANTHROPIC_API_KEY="" \
    claude --settings ~/.config/moonshot/claude-kimi.json "$@"
}
```

A plain `claude` in another terminal stays on your Anthropic login.  A
session pointed elsewhere loses Anthropic-only features: the claude.ai
connectors (Claude Code says so when it starts), Remote Control and
server-managed settings (*read*, [feature availability][claude-features]).
It also turns off tool search, so agda-mcp's tools load up front.

### Kimi K3 through Moonshot

*Read*, 2026-10-11, on Moonshot's [Claude Code guide][moonshot-claude-code],
[pricing][moonshot-pricing], [rate limits][moonshot-limits] and
[terms][moonshot-terms], except where marked run.  The eight steps are as
follows:

+  **Plan and cost**.  Moonshot's platform bills by the token from a prepaid
   balance, with no subscription.  `kimi-k3` cost $3.00 per million input
   tokens, $0.30 per million cached input tokens, and $15.00 per million
   output tokens, with a context of 1,048,576 tokens.  The first recharge is
   at least $1, but below $10 of cumulative recharge (tier 0) the account
   may run one request at a time, three a minute and 1.5 million tokens a
   day; from $10 (tier 1) it may run 15 at a time, 100 a minute, with no
   daily cap.  For scale, Claude Code's smoke test above read about 297,000
   input tokens in its four turns, most of them from cache (whether Moonshot
   counts cached tokens against the daily cap was not read).  A project can
   carry a daily spending limit.  What leaves the machine: Moonshot's terms
   (last updated 30 July 2026) let it use customer content to improve its
   services, model training included, unless a written agreement says
   otherwise, and a customer who wants that restricted is to contact
   Moonshot about an enterprise arrangement.  Its privacy policy stores data
   in Singapore, and it offers zero data retention to enterprise customers
   on request.  No self-serve opt-out was found.  A Kimi membership is a
   separate product, whose Kimi Code allowance works from other harnesses
   through its own key and endpoint (`https://api.kimi.ai/coding/`, with the
   key in `ANTHROPIC_API_KEY` and a model such as `k3[1m]`, by
   [Kimi's Claude Code page][kimi-claude-code]); the two kinds of key are
   not interchangeable, and the membership's prices did not render for a
   script on 2026-10-11, so read the plan page signed in.
+  **Install**.  Claude Code, as in its own section; nothing else.  The
   settings file and the `claude-kimi` launcher above are the whole setup.
+  **Sign in**.  The key comes from the platform console at
   `platform.kimi.ai`; keep it as the launcher above does.  A session started
   with the launcher sends that key, not your Anthropic login.
+  **Model and effort**.  `--model kimi-k3`, or `kimi-k3[1m]` to tell Claude
   Code the model has a one-million-token window.  Moonshot documents K3's
   effort levels as `low`, `high` and `max`, with `max` the default; K3
   refused `xhigh` in the sessions of [#243].  Moonshot's guide sets
   `CLAUDE_CODE_EFFORT_LEVEL` to `max`; name the level you ran.
+  **Instructions and skills**.  Claude Code's own, unchanged: `CLAUDE.md`
   and `.claude/skills/` as in the Claude Code section.
+  **Registering agda-mcp**.  Unchanged: the same `.mcp.json` and the same
   approval.  With the base URL pointed away from Anthropic, Claude Code
   turns tool search off, so the server's tools load up front.
+  **Smoke test**.  *Run*, 2026-10-11, Claude Code 2.1.282 with the settings
   file and launcher above, `--model kimi-k3 --effort low`, and the smoke
   test's `--allowedTools`.  The request reached Moonshot's endpoint with
   the key, and Moonshot answered `429`, "suspended due to insufficient
   balance".  The route is verified as far as the provider's billing check;
   the smoke test proper waits for a funded key, as do the bench arm of
   [#238] and the trials of [#235].
+  **Known issues**.  An empty balance is a `429` that Claude Code retries
   for about three minutes before it gives up.  Claude Code prints
   `[claude-code:unrecognized_model]` for a model id it does not know, which
   is harmless.

### A local model through Ollama

*Read*, 2026-10-11, on Ollama's [Claude Code page][ollama-claude-code],
[Anthropic compatibility page][ollama-anthropic],
[context length page][ollama-context] and [cloud page][ollama-cloud].
Ollama was not installed here, so nothing in this subsection was run; the
bench arm of [#240] and the model server of [#241] are where it will be.
The eight steps are as follows:

+  **Plan and cost**.  Ollama is free and runs on your own hardware.  Its
   `:cloud` models run on Ollama's servers instead.  What leaves the
   machine: nothing, for a local model.  For a cloud model, Ollama
   "processes cloud prompts and responses to answer your requests.  We do
   not use them to train models."  Setting `"disable_ollama_cloud": true` in
   `~/.ollama/server.json` keeps every request local.
+  **Install**.  Claude Code, as in its own section, and Ollama: on Linux,
   `curl -fsSL https://ollama.com/install.sh | sh`; on macOS and Windows,
   the download from `ollama.com/download`.  `ollama launch claude` offers
   to install Claude Code too.
+  **Sign in**.  None, for a local model.  Set `ANTHROPIC_BASE_URL` to
   `http://localhost:11434`, `ANTHROPIC_AUTH_TOKEN` to `ollama` (required,
   but the local server does not check it) and `ANTHROPIC_API_KEY` to the
   empty string, for the one session, as in the settings file above;
   `ollama launch claude` sets them itself.
+  **Model and effort**.  `claude --model <a model you have pulled>`.
   Ollama's default context is 4k tokens on a machine with less than 24 GiB
   of VRAM, too small for a coding agent; its pages ask for at least 64k,
   for example `OLLAMA_CONTEXT_LENGTH=64000 ollama serve`.  The pages read
   do not say whether Ollama honors Claude Code's effort setting.
+  **Instructions and skills**.  Claude Code's own, unchanged.
+  **Registering agda-mcp**.  Unchanged: the same `.mcp.json` and the same
   approval, with tool search off as above.
+  **Smoke test**.  Not run; [#240] is where it will be.
+  **Known issues**.  Ollama's Anthropic compatibility does not support
   `tool_choice` or prompt caching.

## Kimi Code CLI

Moonshot's own harness, the `kimi` command.

### Plan and cost

*Read*, 2026-10-11.  The Moonshot platform key of the previous section, or a
Kimi membership with Kimi Code; the same prices and the same terms apply.

### Install

*Read*, 2026-10-11, on Kimi Code's [getting started page][kimi-start]; the
version check was run.

```sh
curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash   # needs no Node.js
npm install -g @moonshot-ai/kimi-code                          # or npm, with Node.js 22.19.0 or later
kimi --version                                                 # 2.1.1 here
```

### Sign in

*Read*, 2026-10-11, on the [getting started page][kimi-start].

+  `/login` in a session offers Kimi Code (a device-code flow, for a
   membership) or a Kimi platform API key; `kimi login` runs the device-code
   flow from the shell (`--region global` for `kimi.ai`).
+  The key is stored under `~/.kimi-code/` (moved by `KIMI_CODE_HOME`), and
   Kimi Code does not read keys from environment variables.

### Model and effort

*Run* (`kimi --help`, 2.1.1) and *read* (the configuration pages).

+  `-m <alias>` for one run, `default_model` in `~/.kimi-code/config.toml`,
   or `/model` in a session.
+  Each model's entry in the configuration lists the effort levels it
   supports (for K3, `low`, `high` and `max`, default `max`), and
   `[thinking] effort` chooses one.

### Instructions and skills

*Read*, 2026-10-11, on Kimi Code's [agents][kimi-agents] and
[skills][kimi-skills] pages.

+  It reads `AGENTS.md` in the project (or `.kimi-code/AGENTS.md`), and
   `~/.kimi-code/AGENTS.md` and `~/.agents/AGENTS.md` for you; the pages
   read do not mention `CLAUDE.md`.
+  Skills come from `.kimi-code/skills/` and `.agents/skills/` in the
   project and from `~/.kimi-code/skills/` and `~/.agents/skills/`, not from
   `.claude/skills/`.

### Registering agda-mcp

*Read*, 2026-10-11, on Kimi Code's [MCP page][kimi-mcp], except where marked
run.

The registration is `.kimi-code/mcp.json` at the project's root, or
`~/.kimi-code/mcp.json` for every project, in the `mcpServers` shape of
`.mcp.json` plus two timeouts in milliseconds: `startupTimeoutMs` (default
30000) and `toolTimeoutMs`.  `/mcp-config` edits it and `/mcp` shows the
state; version 2.1.1 has no `kimi mcp` subcommand (*run*).  For this
repository, as follows:

```json
{
  "mcpServers": {
    "agda": {
      "command": "/path/to/agda-native-air/scripts/run-server.sh",
      "args": [
        "--agda-flags", "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library",
        "--timeout", "600"
      ],
      "startupTimeoutMs": 120000,
      "toolTimeoutMs": 1860000
    }
  }
}
```

A project file loads only in a folder you have trusted.  *Run*: `kimi -p` in
an untrusted checkout printed "Warning: this folder is not trusted; skipped 1
project-level MCP server: agda", and "Run `kimi` here and choose "Trust this
folder" to enable them."

### Smoke test

*Run*, 2026-10-11, Kimi Code CLI 2.1.1:

```sh
kimi -p "$PROMPT" --output-format stream-json < /dev/null
```

It was stopped first by the folder's trust, as above, and then by the
account's balance (the same `429` as in the previous section), so it has not
yet passed.  In `-p` mode Kimi Code asks for no approval: tool calls run
under its `auto` permission policy, and static deny rules still apply.

### Known issues

From this page's runs, except where marked read.

+  **An empty balance** stops `kimi -p` at once with the provider's `429`,
   without retrying.
+  **Permission rules** (*read*) name the server's tools `mcp__agda__<tool>`
   (`[[permission.rules]]` in `config.toml`).

## OpenAI Codex CLI

### Plan and cost

*Read*, 2026-10-11, on OpenAI's [pricing page][codex-pricing],
[models page][codex-models] and [authentication page][codex-auth].

+  Codex comes with ChatGPT plans, not with a separate subscription.
   ChatGPT Plus, $20 a month, is the least plan with GPT-6.1 Sol in Codex;
   Free and Go do not include it.  On Plus the pricing page estimated 15 to
   160 local messages with GPT-6.1 Sol in five hours, and 5 to 45 with
   GPT-6 Astra, by the size of the task, and weekly limits may apply too.
   OpenAI's Pro started at $100 a month (plans at $100, $200 and $500), with
   no five-hour limit.
+  An OpenAI API key bills by the token at API rates instead, without
   Codex's cloud features.
+  What leaves the machine: the pricing page marks "No training on API or
   business data by default" as unavailable on Plus and Pro, and available
   on Business, Enterprise and the API.  On a personal plan, ChatGPT's data
   controls decide whether Codex sessions may train OpenAI's models; OpenAI's
   help article on that setting refused a script on 2026-10-11, so read it
   signed in.  Business, Enterprise and Edu workspace data "is not used to
   train OpenAI models by default", and with an API key the API
   organization's settings apply.
+  Codex also sends anonymous usage data, which `[analytics] enabled = false`
   in `~/.codex/config.toml` turns off.

### Install

*Read*, 2026-10-11, on OpenAI's [Codex CLI page][codex-cli]; the version
check was run.

```sh
npm install -g @openai/codex                           # 0.162.1 here, under Node.js 22
curl -fsSL https://chatgpt.com/codex/install.sh | sh   # or the standalone installer
brew install --cask codex                              # or Homebrew
codex --version
```

### Sign in

*Read*, 2026-10-11, on the [authentication page][codex-auth]; `codex login
status` was run.

+  `codex login` signs in through the browser.  On a machine without one,
   `codex login --device-auth` uses a device code, after you enable device
   code login in ChatGPT's security settings (a beta).
+  An API key goes through standard input:
   `printenv OPENAI_API_KEY | codex login --with-api-key`.  For CI,
   `CODEX_API_KEY` serves `codex exec`.
+  `codex login status` prints the method in use (`Logged in using
   ChatGPT` here).  Codex keeps the credential in `~/.codex/auth.json`, in
   plain text, or in the system's keyring (`cli_auth_credentials_store`);
   treat that file like a password.

### Model and effort

*Run* (`codex exec --help`, 0.162.1) and *read* (the
[models page][codex-models] and [configuration reference][codex-config]).

+  `-m gpt-6.1-sol` for one run, `model = "gpt-6.1-sol"` in the
   configuration, or `/model` in a session; the ids include `gpt-6.1-sol`,
   `gpt-6-astra` and `gpt-6-luna`.
+  `model_reasoning_effort` takes `low`, `medium`, `high`, `xhigh`, `max`
   or `ultra`, as far as the model supports them.  `-c` sets any key for
   one run, its value parsed as TOML: `-c 'model_reasoning_effort="low"'`.

### Instructions and skills

*Read*, 2026-10-11, on OpenAI's [AGENTS.md page][codex-agents-md] and
[skills page][codex-skills].

+  Codex reads `~/.codex/AGENTS.md` (or `AGENTS.override.md` beside it),
   then one `AGENTS.md` per directory from the project root down to the
   directory it starts in, up to `project_doc_max_bytes` (32 KiB by
   default).  It reads no `CLAUDE.md` unless `project_doc_fallback_filenames`
   names it.
+  It loads skills from `.agents/skills/` in every directory from the start
   directory up to the repository root, and from `~/.agents/skills/`, and it
   follows symlinked skill folders.  The pages name no `.claude/skills/`.

### Registering agda-mcp

*Run*, 2026-10-11, Codex CLI 0.162.1, except where marked.

Codex does not read `.mcp.json`.  Its registration is a `[mcp_servers.agda]`
table, in `~/.codex/config.toml` for every project or in a project's
`.codex/config.toml`, which Codex reads only for a project you trust.  For
this repository, as follows:

```toml
[mcp_servers.agda]
command = "/path/to/agda-native-air/scripts/run-server.sh"
args = [
  "--agda-flags", "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library",
  "--timeout", "600",
]
startup_timeout_sec = 120
tool_timeout_sec = 1860
required = true
default_tools_approval_mode = "approve"

[mcp_servers.agda.tools.check_project]
approval_mode = "prompt"
```

For another project,
[`agda-mcp/examples/agda-algebras.codex.toml`][example-codex] is the
agda-algebras registration as a table, with the same placeholders as the
`.mcp.json` template; it was run on an agda-algebras checkout (see the smoke
test).  Each choice in the table is there for a reason, as follows:

+  `startup_timeout_sec`: Codex's default is 10 s, and the launcher took 2.5
   to 16 s in the runs above, and up to 32 s with a dirty working tree.
+  `tool_timeout_sec`: Codex's documented default is 60 s, and a first check
   of a large library can take minutes.  The value sits above the server's
   own bounds, `--timeout` for a check and `--check-timeout` for
   `check_project` (1800 s by default, 3600 in the template), so that the
   server's timeout answer, which names the bound, arrives first.  (Observed:
   a 90 s call completed with the key unset, in 0.162.1; the documentation is
   what a later version may enforce.)
+  `required = true`: without it, `codex exec` sends its first request
   before the server is up, and the model finds no agda tools; this is what
   happened in the Codex session of [#243].
+  `default_tools_approval_mode = "approve"`: agda-mcp's tools carry no
   read-only annotation, so Codex asks before every call, and `codex exec`,
   which cannot ask, refuses them with "MCP tool call requires approval, but
   approval policy is never".  Every tool leaves the checkout as it found it
   (`get_goal` and `fill_hole` restore the file byte for byte) except
   `check_project`, which runs the project's gate and stays on a prompt.
   `tools.<tool>.approval_mode` sets one tool at a time.
+  No `--cwd`: Codex expands no variables and starts the server in the
   directory it started in, and the launcher passes that directory as
   `--cwd` itself.  A registration copied from Claude Code's may keep
   `--cwd ${PWD}`, which the launcher substitutes.

`codex mcp add agda -- /path/to/agda-native-air/scripts/run-server.sh
<arguments>`, with the `args` of the table as the arguments, writes the
table's first lines to `~/.codex/config.toml`, and the other keys are added
by hand (*run* against a throwaway `CODEX_HOME`, which got exactly `command`
and `args`).
`codex mcp list` shows the servers Codex will start, and a trusted project's
table among them.

**Trusting a project**.  Codex records the projects you trust as
`[projects."<path>"]` tables with `trust_level = "trusted"` in
`~/.codex/config.toml` (observed in the configuration here; the pages read do
not say how an interactive session asks).  For one run, pass the table on the
command line:
`-c 'projects={"/path/to/checkout"={trust_level="trusted"}}'`.  The dotted
form, `-c 'projects."/path/to/checkout".trust_level="trusted"'`, was
silently ignored here: the project's table did not load.

**One run only**.  `-c` overrides register the server for one run with no
file at all, which is how the smoke test below ran.

### Smoke test

*Run*, 2026-10-11, Codex CLI 0.162.1, GPT-6.1 Sol at `low`, from the
checkout's root, with every key passed by `-c`:

```sh
codex exec --json -m gpt-6.1-sol -c 'model_reasoning_effort="low"' -s read-only \
  -c 'mcp_servers.agda.command="/path/to/agda-native-air/scripts/run-server.sh"' \
  -c 'mcp_servers.agda.args=["--agda-flags", "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library", "--timeout", "600"]' \
  -c 'mcp_servers.agda.startup_timeout_sec=120' \
  -c 'mcp_servers.agda.tool_timeout_sec=660' \
  -c 'mcp_servers.agda.required=true' \
  -c 'mcp_servers.agda.tools.check_file.approval_mode="approve"' \
  -c 'mcp_servers.agda.tools.get_goal.approval_mode="approve"' \
  "$PROMPT" < /dev/null
```

The last two overrides approve the two tools the prompt calls, and no
other.  It answered in 22 s, as follows:

```text
Tools: `check_file`, `check_project`, `definition_of`, `exports_of`, `fill_hole`, `get_diagnostics`, `get_goal`, `normalize`, `resolve_name`, `type_of`.
`check_file`: `success: false`; 3 holes.
`get_goal` (holeIndex 0): goal `A`.
Context: `A : Set`, `x : A`.
```

The same prompt with the table in the checkout's `.codex/config.toml`, the
project trusted by `-c`, answered the same in 18 s.  The agda-algebras
template, filled in and placed in an agda-algebras checkout's
`.codex/config.toml`, gave thirteen tools (its corpus loaded), a green
`check_file` on `src/Overture/Operations.lagda.md`, and a response naming
that checkout as both the project root and the directory Agda ran in.

### Known issues

From this page's runs and the field report of [#243], except where marked
read.

+  **The sandbox on Ubuntu 24.04**.  Codex's Linux sandbox runs commands
   under bubblewrap, which Ubuntu 24.04's AppArmor policy stops from
   creating its namespaces.  Every sandboxed shell command then fails, while
   `codex doctor` still reports the sandbox healthy (*run*: both).  The
   probe that shows it is `codex sandbox -P :workspace -C <dir> -- echo hi`,
   which printed `bwrap: loopback: Failed RTM_NEWADDR: Operation not
   permitted` here.  agda-mcp's calls do not go through the sandbox: the
   smoke test passed under `-s read-only` with the sandbox broken.  The fix
   follows this list.
+  **Approval prompts** (*read*).  `approvals_reviewer = "auto_review"` hands
   the prompts that `on-request` would show you to Codex's reviewer agent
   instead, which costs extra model calls; it grants no permission the
   sandbox does not.
+  **`codex exec` reads standard input**.  Whenever standard input is not a
   terminal, `codex exec` appends it to the prompt.  Run from a script or
   another agent, it waits for an end of input that never comes (*run*: it
   waited until killed).  End the command with `< /dev/null`.
+  **Tools behind code mode**.  In the Codex session of [#243], Codex showed
   the model MCP tools only through its code mode's `ALL_TOOLS` array, and
   sent none of the server's instructions; the tool descriptions carry the
   verdict contract on their own.  `required = true` is what lets the model
   find the tools at its first look.

The sandbox's fix, from OpenAI's [sandboxing page][codex-sandboxing] (*read*;
it needs root, and was not run here), loads the AppArmor profile bubblewrap
needs, as follows:

```sh
sudo apt install apparmor-profiles apparmor-utils
sudo install -m 0644 /usr/share/apparmor/extra-profiles/bwrap-userns-restrict \
  /etc/apparmor.d/bwrap-userns-restrict
sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
```

## GitHub Copilot CLI

### Plan and cost

*Read*, 2026-10-11, on GitHub's [plans page][copilot-plans],
[individual billing page][copilot-billing],
[supported models][copilot-models] and
[account policies page][copilot-policies].

+  Copilot plans are GitHub's, not OpenAI's.  Copilot Pro was $10 a month
   with 1,500 GitHub AI Credits (1,000 base and a flex allotment of 500),
   Pro+ $39 with 7,000, and Max $100 with 20,000.  A credit is worth a
   cent and is spent by the token at the model's price; credits do not
   carry over between months.  Copilot Free includes the CLI, with models
   by automatic selection only.
+  Pro offers Kimi K3, Claude Sonnet 5 and 5.5, Claude Haiku, GPT-6 Luna
   and several GPT-5 models, among others; GPT-6.1 Sol, GPT-6 Astra, Claude
   Opus and Claude Fable need Pro+ or Max.  A legacy annual plan still
   counts premium requests (300 a month on Pro), one per prompt to the CLI
   with the default model.
+  What leaves the machine: since 24 April 2026, on Free, Pro, Pro+ and
   Max, GitHub may use a session's "inputs, outputs, code snippets, and
   associated context" to train and improve AI models.  To opt out, set
   "Allow GitHub to use my data for AI model training" to Disabled at
   `github.com/settings/copilot/features`.  GitHub does not train on
   Copilot Business or Enterprise data.  Copilot CLI also syncs local
   sessions to your GitHub account by default (the `remote` setting).

### Install

*Read*, 2026-10-11, on GitHub's [install page][copilot-install]; the version
check was run.

```sh
npm install -g @github/copilot                 # needs Node.js 22 or later; 1.0.95 here
brew install --cask copilot-cli                # or Homebrew
curl -fsSL https://gh.io/copilot-install | bash   # or the install script
copilot --version
```

### Sign in

*Read*, 2026-10-11, on GitHub's [authentication page][copilot-auth]; the
first `copilot -p` showed the sign-in current.

+  `copilot login`, or `/login` in a session, offers a browser flow and a
   device-code flow; SSH sessions, containers and CI get the device code by
   default, and `--device-code` or `--web-flow` forces one.  The token goes
   to the system keychain (libsecret on Linux), or, with no keychain, to a
   plain-text `~/.copilot/config.json` after asking.
+  A token in `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` or `GITHUB_TOKEN` overrides
   the stored login: a fine-grained personal access token with the "Copilot
   Requests" permission works, and a classic one does not.

### Model and effort

*Run* (`copilot --help`, 1.0.95) and *read* (the
[command reference][copilot-cmdref]).

+  `--model <id>` for one run (`gpt-6.1-sol`, `kimi-k3`, `claude-sonnet-5.5`,
   and so on), `COPILOT_MODEL`, `/model` in a session, or `model` in
   `~/.copilot/settings.json`.
+  `--reasoning-effort` takes `none`, `minimal`, `low`, `medium`, `high`,
   `xhigh` or `max` by the local help, as far as the model supports them;
   `effortLevel` in `settings.json` sets a default.

### Instructions and skills

*Read*, 2026-10-11, on GitHub's [custom instructions page][copilot-instructions]
and [skills page][copilot-skills].

+  Copilot reads `AGENTS.md`, `CLAUDE.md` (and `.claude/CLAUDE.md`),
   `GEMINI.md`, `.github/copilot-instructions.md` and
   `.github/instructions/**/*.instructions.md` in the repository root and
   the start directory (all but the last in the directories between them as
   well), and `~/.copilot/copilot-instructions.md` for you.
+  It loads skills from `.github/skills/`, `.agents/skills/` and
   `.claude/skills/` in the repository, and from `~/.copilot/skills/` and
   `~/.agents/skills/`.  The pages do not say whether it follows symlinks;
   it loaded symlinked skills in the sessions of [#243].

### Registering agda-mcp

*Run*, 2026-10-11, Copilot CLI 1.0.95, except where marked.

**In this repository** there is nothing to register.  Copilot reads a
project's `.mcp.json` (in any directory from the start directory up to the
repository root) and `.github/mcp.json`, once you have trusted the folder at
its first launch; in an untrusted folder it skips them without a word.  The
smoke test below ran with no registration of its own.

+  `copilot -p` cannot ask for trust.  In an untrusted checkout it skipped
   the project's `.mcp.json` (*run*), and
   `GITHUB_COPILOT_PROMPT_MODE_WORKSPACE_MCP=true` made it load the file
   (*run*).  In a worktree of a repository whose main checkout had been
   trusted, the file loaded with no variable (*run*; not documented).
+  When the launcher fails, Copilot reports the server's last line of
   stderr, which names the cause.

**Another project**: the `.mcp.json` template,
[`agda-mcp/examples/agda-algebras.mcp.json`][example-mcp-json], works
unchanged.  Copilot does not expand `${PWD}` in arguments, and the launcher
substitutes it.  Filled in and placed in an agda-algebras checkout, it
checked the whole library (`src/agda-algebras.lagda.md`) green in 27 s, with
the interfaces of 92 modules left by an earlier run.

**Every project**.  `copilot mcp add agda -- <command> <arguments>`, with the
launcher, `/path/to/agda-native-air/scripts/run-server.sh`, as the command
and the `args` of the `.mcp.json` entry you would otherwise use as the
arguments, writes the server to `~/.copilot/mcp-config.json` (*run* against a
throwaway, private `COPILOT_HOME`, which got the entry below).  The file's
entry has the following shape, and takes `env`, `cwd` and `timeout` too:

```json
{"mcpServers": {"agda": {"type": "local", "command": "...", "args": ["..."], "tools": ["*"]}}}
```

With no `--cwd`, the server starts in each session's start directory.  For
one session only, `--additional-mcp-config @<file>` takes a file of the same
shape (*run*).

**Timeouts**.  The documented `timeout` is in milliseconds, "for tool
discovery and tool calls", with a default of 30000; for the connection, the
budget it sets is floored at 60000 ms (*read*), which covers the launcher's
32 s worst case.  Observed in 1.0.95: a 90 s call completed with no
`timeout` set.  A registration that runs long
gates may set `"timeout": 3660000` against a later version that enforces it.

**Tool names**.  The model sees `agda-check_file`; permission patterns are
`agda(check_file)` for one tool and `agda` for the whole server.

### Smoke test

*Run*, 2026-10-11, Copilot CLI 1.0.95, GPT-6.1 Sol at `low`, from the
checkout's root:

```sh
copilot -p "$PROMPT" --model gpt-6.1-sol --reasoning-effort low \
  --allow-tool='agda(check_file)' --allow-tool='agda(get_goal)' \
  --output-format json < /dev/null
```

GPT-6.1 Sol needs Pro+ or Max; on Pro, name a model Pro includes, such as
`claude-sonnet-5.5`.  It answered in 16 s, and the plan it ran on counted one
premium request; on a plan billed in AI credits, the same run is charged by
its tokens.  The answer was as follows:

```text
Tools: check_file, check_project, definition_of, exports_of, fill_hole, get_dependencies, get_diagnostics, get_goal, normalize, resolve_name, search_by_name, search_by_type, type_of.
Fixture01.agda: `success: false`; holes listed: **3**.
Hole 0 goal: `A`.
Context: `A : Set`, `x : A`.
```

### Your own key

*Run* and *read* (`copilot help providers`, 1.0.95).  With
`COPILOT_PROVIDER_BASE_URL` set, Copilot sends its model requests to that
provider "instead of GitHub Copilot's model routing", and "GitHub
authentication is not required".  A model is required (`COPILOT_MODEL` or
`--model`).  `COPILOT_PROVIDER_TYPE` is `openai` (the default), `azure` or
`anthropic`, and `COPILOT_PROVIDER_API_KEY_COMMAND` names a command that
prints the key for each request, so that the key never sits in the
environment.  For Moonshot, as follows:

```sh
COPILOT_PROVIDER_BASE_URL=https://api.moonshot.ai/v1 \
COPILOT_PROVIDER_API_KEY_COMMAND='cat ~/.config/moonshot/api-key' \
COPILOT_MODEL=kimi-k3 \
  copilot -p "$PROMPT" --allow-tool='agda(check_file)' --allow-tool='agda(get_goal)' < /dev/null
```

*Run*, 2026-10-11: the project's agda server connected as usual, the model
request went to Moonshot, which refused it for want of balance, and the
session reported `premiumRequests: 0`.  Copilot still sends its telemetry to
GitHub in this mode unless it is offline (*read*).

### Known issues

From the field reports of [#243], except where marked read.

+  **Server instructions**.  Copilot sends the server's `initialize`
   instructions only for allowlisted servers, or under
   `--allow-all-mcp-server-instructions`; in [#243], one model saw none of
   them and another the first 157 characters.  The tool descriptions carry
   the verdict contract on their own.
+  **Skills with loose YAML**.  Copilot drops a skill whose frontmatter is
   not strict YAML (an unquoted colon in a description, for example), and
   `copilot skill list` names the ones it refused.
+  **Path checks are per tool**.  In [#243] Copilot refused a `view` of a
   file outside the checkout, and let a shell redirection to the same file
   through.
+  **Commit trailers**.  Copilot adds a `Co-authored-by` trailer to commits
   its agent makes unless `includeCoAuthoredBy` is `false` in
   `~/.copilot/settings.json` (*read*).

## Reporting a result

A model at `low` and the same model at `max` are two instruments: they spend
different amounts, take different times, and do not solve the same problems.
When you report a result, name the harness and its version, the model, and
the effort level together.  The field reports of [#243] ran GPT-6.1 Sol at
`xhigh` and Kimi K3 at `max`.  The benchmark's arms (see [the results
guide][results-guide]) passed no effort flag and removed every variable and
settings source that sets one, as their `report.json` files record, so they
ran at Claude Code 2.1.261's default for Opus 5 and Sonnet 5, which the
records do not name.  The smoke tests on this page ran at `low`, which three
tool calls do not strain.

## Adding a harness

A harness added later gets a section of the same shape: the eight steps in
order, each marked run or read with the version and the date, and the smoke
test above with its output.  Its known issues come from a field report in
[`docs/mcp-field-reports.md`][field-reports].

## Sources

The vendors' pages were all read on 2026-10-11, as follows:

+  Anthropic's pages read were [pricing][claude-pricing],
   [data usage][claude-data-usage],
   [model-improvement setting][claude-privacy-setting],
   [setup][claude-setup], [authentication][claude-auth],
   [model configuration][claude-model-config], [memory][claude-memory],
   [skills][claude-skills], [MCP][claude-mcp],
   [environment variables][claude-env-vars] and
   [feature availability][claude-features].
+  Moonshot's pages read were [Claude Code with Kimi][moonshot-claude-code],
   [pricing][moonshot-pricing], [rate limits][moonshot-limits],
   [terms][moonshot-terms] and [Kimi Code with Claude Code][kimi-claude-code],
   with Kimi Code CLI's [getting started][kimi-start], [MCP][kimi-mcp],
   [skills][kimi-skills] and [agents][kimi-agents] pages.
+  Ollama's pages read were [Claude Code][ollama-claude-code],
   [Anthropic compatibility][ollama-anthropic],
   [context length][ollama-context] and [cloud][ollama-cloud].
+  OpenAI's pages read were [pricing][codex-pricing], [models][codex-models],
   [Codex CLI][codex-cli], [authentication][codex-auth],
   [configuration reference][codex-config], [AGENTS.md][codex-agents-md],
   [skills][codex-skills], [MCP][codex-mcp] and
   [sandboxing][codex-sandboxing].
+  GitHub's pages read were [plans][copilot-plans],
   [billing][copilot-billing], [supported models][copilot-models],
   [account policies][copilot-policies], [install][copilot-install],
   [authentication][copilot-auth], [command reference][copilot-cmdref],
   [custom instructions][copilot-instructions], [skills][copilot-skills] and
   [MCP servers][copilot-mcp].

[#153]: https://github.com/formalverification/agda-native-air/issues/153
[#235]: https://github.com/formalverification/agda-native-air/issues/235
[#238]: https://github.com/formalverification/agda-native-air/issues/238
[#240]: https://github.com/formalverification/agda-native-air/issues/240
[#241]: https://github.com/formalverification/agda-native-air/issues/241
[#242]: https://github.com/formalverification/agda-native-air/issues/242
[#243]: https://github.com/formalverification/agda-native-air/issues/243
[#249]: https://github.com/formalverification/agda-native-air/issues/249
[launcher]: ../../scripts/run-server.sh
[root-mcp-json]: ../../.mcp.json
[example-mcp-json]: ../../agda-mcp/examples/agda-algebras.mcp.json
[example-codex]: ../../agda-mcp/examples/agda-algebras.codex.toml
[examples-readme]: ../../agda-mcp/examples/README.md#agda-algebrasmcpjson
[command-line options]: ../../agda-mcp/README.md#command-line-options
[without-the-shell]: ../../agda-mcp/README.md#without-the-shell
[howtorun-13]: ../HowToRun.md#13--agda-mcp-ai-assisted-proof-development
[howtorun-134]: ../HowToRun.md#134--using-agda-mcp-on-another-agda-project
[field-reports]: ../mcp-field-reports.md
[results-guide]: ../reading-the-results.md
[nixos.org/download]: https://nixos.org/download/
[claude-pricing]: https://claude.com/pricing
[claude-data-usage]: https://code.claude.com/docs/en/data-usage
[claude-privacy-setting]: https://privacy.claude.com/en/articles/12109829-how-do-i-change-my-model-improvement-privacy-settings
[claude-setup]: https://code.claude.com/docs/en/setup
[claude-auth]: https://code.claude.com/docs/en/authentication
[claude-model-config]: https://code.claude.com/docs/en/model-config
[claude-memory]: https://code.claude.com/docs/en/memory
[claude-skills]: https://code.claude.com/docs/en/skills
[claude-mcp]: https://code.claude.com/docs/en/mcp
[claude-env-vars]: https://code.claude.com/docs/en/env-vars
[claude-features]: https://code.claude.com/docs/en/feature-availability
[moonshot-claude-code]: https://platform.kimi.ai/docs/guide/claude-code-kimi
[moonshot-pricing]: https://platform.kimi.ai/docs/pricing/chat
[moonshot-limits]: https://platform.kimi.ai/docs/pricing/limits
[moonshot-terms]: https://platform.kimi.ai/docs/agreement/modeluse
[kimi-claude-code]: https://www.kimi.com/code/docs/en/third-party-tools/claude-code.html
[kimi-start]: https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started.html
[kimi-mcp]: https://www.kimi.com/code/docs/en/kimi-code-cli/customization/mcp.html
[kimi-skills]: https://www.kimi.com/code/docs/en/kimi-code-cli/customization/skills.html
[kimi-agents]: https://www.kimi.com/code/docs/en/kimi-code-cli/customization/agents.html
[ollama-claude-code]: https://docs.ollama.com/integrations/claude-code
[ollama-anthropic]: https://docs.ollama.com/api/anthropic-compatibility
[ollama-context]: https://docs.ollama.com/context-length
[ollama-cloud]: https://docs.ollama.com/cloud
[codex-pricing]: https://learn.chatgpt.com/docs/pricing
[codex-models]: https://learn.chatgpt.com/docs/models
[codex-cli]: https://learn.chatgpt.com/docs/codex/cli
[codex-auth]: https://learn.chatgpt.com/docs/auth
[codex-config]: https://learn.chatgpt.com/docs/config-file/config-reference
[codex-agents-md]: https://learn.chatgpt.com/docs/agent-configuration/agents-md
[codex-skills]: https://learn.chatgpt.com/docs/build-skills
[codex-mcp]: https://learn.chatgpt.com/docs/extend/mcp
[codex-sandboxing]: https://learn.chatgpt.com/docs/sandboxing
[copilot-plans]: https://docs.github.com/en/copilot/get-started/plans
[copilot-billing]: https://docs.github.com/en/copilot/concepts/billing-and-usage/individuals/billing
[copilot-models]: https://docs.github.com/en/copilot/reference/ai-models/supported-models
[copilot-policies]: https://docs.github.com/en/copilot/how-tos/manage-your-account/manage-policies
[copilot-install]: https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli
[copilot-auth]: https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli
[copilot-cmdref]: https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference
[copilot-instructions]: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions
[copilot-skills]: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills
[copilot-mcp]: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers
