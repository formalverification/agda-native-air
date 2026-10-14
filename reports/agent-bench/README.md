<!-- File: reports/agent-bench/README.md -->

# Agent-in-the-loop runs: the archive

This directory holds every run of the agent-in-the-loop evaluation (Issue
[#154], [M1-10]) that a document quotes: a frontier model over the benchmark
suite, one fresh non-interactive session per obligation, judged by the gold
verifier's own `agda` invocation.  Each run is one **arm**, and an arm is one
instrument (Issue [#162]): `mcp` gives the subject the `agda-mcp` server,
`shell` gives it the pinned `agda` on a shell, `both` gives it both.  The runs
made before 2026-09-21 are all the `mcp` arm, from before the knob existed.
The decision record is
[ADR 0001](../../docs/adr/0001-proof-search-on-agda-mcp.md) § 9; the
explanatory note is [`docs/proof-search/overview.md`](../../docs/proof-search/overview.md);
the harness is `struxdriver.agentbench` in `strux-driver/`, run by
`make agent-bench`.  Each run directory is written by `make agent-bench-archive`
from the harness's own output and never edited by hand.
How to read the numbers a run reports, beside every other measurement in the
repository, is [`docs/reading-the-results.md`](../../docs/reading-the-results.md).

## The protocol, fixed for every run below

+  **Subject**.  One `claude -p` session per obligation (Claude Code 2.1.261
   through the [#162] arms, 2.1.282 from [#184] on; each run's
   `protocol.json` records its own; Agda 2.8.0 through the runs of
   2026-10-03 and 2.9.0 from [#236] on, which the system prompt names),
   with its working directory a staged copy of the one obligation file and
   nothing else; its tools are the arm's, plus Read and Edit on that file; no
   settings, no CLAUDE.md, no skills, no memory; the tools presented eagerly
   with their descriptions; the file tools confined to the work directory and
   to the read roots below.  An arm with the server starts it through the
   committed launcher with the row's library corpus: the stdlib v0 corpus,
   digest `14e0d47e`, for `agda-stdlib` rows and the agda-algebras v0.1
   corpus, digest `af864432`, for the others.  The subject's server runs with the
   judge's `--safe`, so the `check_file` verdict it sees is the judge's (the
   three archived arms ran their subjects' servers without it: no final file
   carries a safe-flag refusal, and every subject's last `check_file`
   verdict agrees with the judge's, so no verdict depends on the
   difference).  The flag set, the environment additions, and the prompts
   are recorded verbatim in each run's `report.json` and `prompts/`, and the
   protocol (every knob a subject sees and the judge applies, and every
   input the run reads by content: the index, the corpora, the server, and
   the extractor by SHA-256) in `protocol.json`, written before the first
   subject spawns, the arm named there and in each subject's own
   `subject.json` together with the roots it was given.
+  **The arms** ([#162]).  `--arm` decides the instrument, and within a
   comparison it is the only knob that differs, except where a run's section
   says the server itself changed ([#184], [#191]) or that the arm exposed
   only some of the server's tools (`--expose`, [#191], recorded as `expose`
   in `protocol.json` and each `subject.json`).  The arm decides two client
   values and one file: the built-in tools
   (`Edit,Read` for `mcp`, `Bash,Edit,Read` for `shell` and `both`), the
   pre-approvals (`mcp__agda`, `Bash`, or both), and whether a
   `--mcp-config` is passed at all.  `--restricted` is on for every arm: on
   this client it removes the code-running tools only when `--tools` does not
   name them, so a shell arm keeps Bash and still gets what the flag gives
   every arm, the file tools confined and the settings files ignored.  A
   shell arm's prompt states the row's own `agda` command, which is the
   judge's (`GoldVerifier.agdaCommand`, `--safe` included), names
   `agda --interaction-json` in one sentence with no protocol documentation,
   and gives the path of the row's corpus JSONL; its rules add one, that
   every command runs in the directory the file is in.  Since PR [#200] the
   shell and `both` prompts also name each registered library's source
   directory, and the directory of Agda's own `Agda.Builtin` and
   `Agda.Primitive` modules, and say not to search the rest of the
   filesystem; the header-free arms of 2026-09-29 are the first archived
   runs with that prompt.
+  **Read roots**, the same on every arm.  Besides its own directory, a
   subject may read every registered library's directory and source roots and
   the Agda registry directory, whose `libraries` file the judge's command
   names, and since PR [#200] the directory of Agda's primitive modules
   (`lib/prim` under `agda --print-agda-data-dir`), which three [#162]
   subjects searched `/` for; the file tools reach them through
   `--add-dir`.  This is why the
   arms are comparable: the archived `mcp` arm refused eleven library-source
   reads for Sonnet and two for Opus as a confinement side effect, and a
   shell arm that can `cat` a module while the server arm cannot would
   confound the comparison.
+  **The endpoint** ([#237]).  A subject inherits the harness's environment
   less every `CLAUDE*` variable, so an exported `ANTHROPIC_BASE_URL` and its
   credential point it at another provider's Anthropic-compatible endpoint
   (Moonshot's for Kimi K3, [#238]; an Ollama server for a local model,
   [#240]).  `protocol.json` and each `subject.json` record it as an
   `endpoint` block: `ANTHROPIC_BASE_URL` (its scheme, host, port, and path,
   with any path segment of 16 characters or more, where a gateway might
   carry a key, as `<redacted>`; `absent` when it is unset or empty, the
   client's default, Anthropic's API;
   `unparsed` when it is no absolute URL, which is never recorded verbatim and
   counts as another host); the client's model variables (`ANTHROPIC_MODEL`,
   `ANTHROPIC_SMALL_FAST_MODEL`, `ANTHROPIC_DEFAULT_*_MODEL`) when set; and
   the credential variables it reads (`ANTHROPIC_API_KEY`,
   `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_CUSTOM_HEADERS`) as `set`, never their
   values.  A variable exported empty is unset, for the client and for the
   record: Ollama's and OpenRouter's setups clear `ANTHROPIC_API_KEY` that
   way.  A `--resume` under a changed endpoint is refused naming the field,
   as a changed model is.  A fresh run whose base URL names another host than
   Anthropic's is refused when it names no price table (below), and when both
   `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` are set, since the client
   would send both to that host.  Every archived run predates the record,
   and every session behind it was served by Anthropic's API: the 1,486
   sessions behind the 1,634 subject records in 72 runs (the five
   `rejudge290-*` runs re-judge copies of 148 of them, with no model call)
   authenticated with the client's own login (`apiKeySource: "none"` in the
   init record) and report every model as `provider: "firstParty"`.  A protocol
   recorded before the endpoint and the price table reads as the client's
   default endpoint and the current table, as one recorded before `--expose`
   reads as the full surface, so a run in flight across the change can still be
   resumed.
+  **No credential in a run directory** ([#237]).  The harness writes none,
   but a subject can: on an arm with a shell it inherits every exported
   secret, and one that runs `env` writes them into its transcript, which the
   archive commits.  So after each subject the harness replaces every
   credential value in its transcript and its stderr, then in its final
   file, with `<redacted:NAME>` before anything is judged (the logs first, so
   a final file the subject deleted leaves nothing behind), and names the
   variables in `run.json` (`redacted`) and the row's `outcome.json`
   (`credentialsRedacted`).  A credential is a variable whose name contains
   TOKEN, KEY, SECRET, PASSWORD, PASSWD, CREDENTIAL, AUTH, or HEADERS, in any
   case, or whose value is a URL carrying userinfo, a query, or a fragment (a
   base URL with a key in it, a proxy with a password), and the base URL when
   a path segment is long enough to be a token; its value, each
   whitespace-separated piece of it, and those parts of a URL are looked for
   when at least 16 characters long, as written and as they read inside a
   JSON string.  Path segments count in the base URL alone: elsewhere they are
   ordinary names, a repository's or a directory's, that transcripts are full
   of.
   When the report is written, the harness searches the run directory (the
   work copies aside, which are never archived) for every value, and if one
   is left it fails the run, naming the variable and the file, and adds them
   to `credential-leaks.json`, which no later run removes: the operator does,
   once the files it names are checked.  `make agent-bench-archive` refuses a
   run directory that has that file, or that holds the value of any exported
   variable whose name says it is a credential or whose value is a URL with
   userinfo, a query, or a fragment (handed to `grep` on standard input, never
   on its command line).
+  **Caps**.  30 turns, 900 s of wall, USD 3.00 of the client's own cost
   accounting, per subject; three subjects at a time, so wall clocks are
   indicative only.  The cost cap stays the client's, on its own figure
   (`--max-budget-usd`); the harness enforces no second cap on the priced
   figure, which would mean reading the stream as it is written and killing
   a subject mid-turn ([#237]).  On Anthropic's API the client's figure is the
   list price for every model it has a price for.  For a model the client has no
   price for, it prices the tokens at what it calls its default model's rate
   and marks the figure `costBasis: "unknown"` ("a guess at the default model's
   rate", in client 2.1.282's words).  That rate is not one the run chooses, nor
   a fixed one: on one client and one account, [#236]'s 83 Sonnet 5.5 subjects
   were priced at Claude Fable 5.1's rates (USD 10 and 50 per million input
   and output tokens) on 79 rows and at Claude Opus 5.5's (4 and 20) on the
   other 4, each to the micro-dollar.  The cap is then a token budget at an
   unknown rate, as tight as Fable 5.1's: the most expensive subject of
   `hard219-opus5-mcp-1`, USD 2.06 at Opus 5's prices, would count 3.19
   against it at Fable 5.1's, over the library tier's USD 3.00 cap though
   under the 6.00 that run had, and 14.41 on an endpoint that reports every
   prompt token as uncached input.  So an arm on another endpoint reads its
   cost pair's token counts first and sets `--max-budget-usd` high enough
   that the turn and wall caps are the ones that bind (the value is in its
   protocol like any cap), and the report's `pricing.clientCostBasis` says
   which basis the client used.  This covers the `claude -p` subject; a
   Codex subject ([#239]) has no client caps, and the harness enforces all
   three (the next section).
+  **Cost, priced** ([#237]).  Beside the client's `costUsd`, every row
   carries `pricedCostUsd`: what each model the session called spent, from
   the result record's `modelUsage`, priced at a table the run names
   (`--prices`; copy `data/benchmarks/prices-anthropic.json`, whose
   `schemaVersion`, `asOf`, and rows of exactly `input`, `cacheWrite`,
   `cacheRead`, and `output`, in USD per million tokens, the reader requires).
   The default is Anthropic's list prices as of 2026-10-13, the cache write
   at the one-hour rate (twice the input price, the write the client asks
   for); at it, the priced figure equals the client's on every archived
   subject the client priced at its list prices (1,551 subjects in 68 runs),
   which `PricingSpec` pins, so a typo in a row a list-priced archived
   subject uses cannot pass.  The Opus 5.5 arms of [#236] pin the
   `claude-opus-5-5` row (from client 2.1.282's own catalog).  The
   `claude-sonnet-5-5` row (Anthropic's published list price, which client
   2.1.296 prices at) is still unpinned: client 2.1.282 priced [#236]'s 83
   Sonnet 5.5 subjects as `unknown`, so the spec leaves them out, and the row
   is the price [#236] quotes them at.
   The archived reports predate the field, so their `totals.costUsd` stands
   for both, and a re-judge writes the same figure as `totals.pricedCostUsd`,
   except on the four Sonnet 5.5 runs, where it writes the list price from
   `modelUsage` (2.09 for `suite236-sonnet55-mcp-1`, whose `costUsd` is 9.69).
   The report's `tokens` is not what is priced: it is the main loop's `usage`
   block, which misses calls, the Haiku call of about USD 0.0011 that client
   2.1.261 made beside each session (335 subjects in 9 runs) and one Sonnet 5
   call of USD 0.0131 (`suite219-sonnet5-mcp-1`, client 2.1.282).  A fresh
   run copies its table into the run directory as `prices.json` and records
   it in `protocol.json` by that name and its digest; a re-judge and a resume
   price at that copy (the committed table, for a run made before it
   existed) unless given another, so a row added to the committed table never
   stops a run in flight; a resume under a different table is refused, and so
   is a re-judge at a copy whose digest is not the one `protocol.json` names.
   The report's `pricing` block names the table that priced it and carries
   the rates of every row it used, so its figures can be recomputed from it
   alone.  A row with no figure (a wall-cap kill or a crash leaves no result
   record; a model with no row) has `pricedCostUsd: null` and an `unpriced`
   reason, and each slice sums its priced rows beside `unpricedRows`, the
   count of the rest, so its figure is a lower bound whenever that count is
   not 0.  A provider with no cache-write price has its input price in that
   column; an endpoint that counts cached tokens inside input would be priced
   twice for them, since the client's counts are priced as reported.  A run on
   another endpoint names its own table (a fresh run whose model has no row
   in it is refused; on Anthropic's endpoint it is a warning, and the rows
   come out unpriced; a resume of such a run prices at its own copy and needs
   no `--prices`), and its figure is checked against the provider's usage
   page by the per-model counts in `pricing.byModel` and each subject's
   `startedAt`.
+  **Judge**.  Every fact about the final file is Agda's own answer, asked
   through the server (started with `--safe` in its flags) and the agda-strux
   extractor.  The gates, named in order: *preservation* (the module line and
   every original import line still present, a line diff with comments
   stripped on both sides, added import lines allowed and logged; and the
   definition still of the statement it was given: its elaborated type as
   Agda holds it internally, extracted by `agda-strux` as a structural AST,
   equal to the committed gold's, binder names aside), *escape* (`check_file` reports none of
   Agda's safe-flag refusals), *holes* (`check_file`'s hole list is empty),
   and *typecheck* (the gold verifier's `agda` command,
   `GoldVerifier.agdaCommand`, with `--safe` added, exit-code verdict;
   `check_file`'s exit code is recorded beside it).  A file that passes every
   gate but whose definition refers to the library's own lemma for the
   statement is *restated*, in its own column, never solved; the reference is
   the extractor's `bodyRefs` (Agda's internal terms, closed over the file's
   own helpers) and the original is the index row's `restates:` tag.  Beside
   the verdict, and changing none, the judge reports whether that original's
   own proof was in view before the subject's last edit (the `original`
   column, [#188]), since a body that transcribes the proof cites nothing the
   restated rule can see.  The server's interaction lane plays no part in
   the judge: a printed type is not a statement.  The arms were first judged
   by a textual reading and re-judged under these gates to the same verdict
   on every row; the archived reports and per-subject outcomes are the
   re-judge's.
   `JudgeSpec` and `AgentBenchIntegrationSpec` pin the rules and the live
   gates.
+  **Isolation, verified per subject**.  From each transcript: the server
   connected; the tools presented Read, Edit, and the server's tools, not
   deferred: at least the thirteen the first arms had (fourteen since
   `search_in_scope`, PR [#161], and any agda tool admitted), or under
   `--expose` exactly the exposed ones and no other; no tool used beyond
   them; and no Read or Edit outside the
   work directory that succeeded (refused attempts are counted separately).
   A subject that never had that instrument (the first two, a tool presented
   beyond that set included, used or not) is an anomaly, not a row, as is
   one whose process ended with no result record at all (a crash; a wall-cap
   kill is a stated cap) and one whose file left the judge without an answer
   it should have (a `check_file` that timed out or gave no usable verdict, a
   disagreement between the two batch verdicts, a file Agda checked that the
   extractor could not read).  An anomalous row is never counted a solve or a
   restatement, whatever its file earned, so the measured columns and the
   anomaly count never describe the same row.  A subject that used a tool
   beyond that set or left the work directory fails the isolation gate.
+  **Isolation on an arm with a shell**, which the client cannot enforce.
   `--restricted` confines Read and Edit; nothing confines a pre-approved
   Bash, so the shell arms' confinement is an audit over the paths each
   command names (`ShellAudit`, pinned by `ShellAuditSpec`), and it is
   deliberately conservative: a command the reader cannot account for is a
   violation, never a pass.  Reads must lie under the work directory, the read
   roots, or the row's corpus; writes only under the work directory, which
   covers redirection targets and the destination of a write-capable program.
   A `cd` into the roots is read (the working directory is carried across the
   simple commands of a call, so the paths after it resolve where the shell
   would), a `cd` out of them is a violation.  So is a construct the reader
   cannot see through (command substitution, parameter expansion, an
   unterminated quote) and a program it does not model, which is anything that
   runs another program, any shell keyword, and any interpreter.  A here-doc
   body is standard input rather than a path the shell opens, so it is
   stripped before lexing and the redirection carrying it is audited like any
   other; that is what lets a subject drive `agda --interaction-json`.  The
   confinement is therefore post-hoc by necessity: a row whose commands left
   the roots fails the isolation gate and is not a result, and its
   `outcome.json` names the command.  Widening the audit's program list is a
   change to the audit, and the rule is that every arm of a comparison is
   re-judged under one audit, which costs no sweep.

## A Codex subject (from [#239])

`--harness codex` makes each subject one `codex exec --json` session (Codex
CLI 0.162.1) instead of a `claude -p` one, for OpenAI's models, which have no
Anthropic-compatible endpoint.  A Codex row measures the harness with the
model, as every other row measures Claude Code with its model; no number it
yields is the model's alone, and a sentence that quotes one says so.  The
judge, the caps' values, the prompts' rules, and the fixtures are the Claude
subject's.  `protocol.json` names the harness and its version (`harness`,
`harnessVersion`; a protocol recorded before [#239] reads as `claude`), as
each Codex subject's `subject.json` and init record do.  What differs is as
follows:

+  **The instrument is the `mcp` arm's**.  A Codex run is the `mcp` arm, one
   subject at a time.  Codex's shell is off (`features.shell_tool = false`): a
   shell reaches the libraries' sources by search, which is the instrument the
   `mcp` arm withholds ([#162]).  The subject's Read is `read`, the one tool of
   a second MCP server, `files` (`scripts/python/bench_read_server.py`),
   confined to the work directory and the read roots, numbering its lines from
   1; its Edit is Codex's `apply_patch`, whose writes the sandbox confines to
   the work directory.  The agda server is the Claude subject's, byte for
   byte.  The system prompt (`agentbench/codex/system-prompt-mcp.md`) differs
   from Claude's in the sentence that names the tools and says there is no
   shell.
+  **What the model is shown**.  Both servers' tools are top-level function
   tools with their full JSON schemas (`omit_tools_from = ["deferred",
   "code_mode"]`), presented eagerly, one model step per call, as a Claude
   subject's are.  Claude Code cuts a server's descriptions and instructions at
   2,048 characters ([#191]) and Codex does not, so a Codex subject reads
   agda-mcp's descriptions whole.  The catalog makes Codex a code-mode harness
   for these models: `apply_patch` is a function inside the JavaScript `exec`
   tool, beside three MCP-resource functions and a clock, and `exec`, `wait`,
   and `request_user_input_async` are presented beside the servers' tools,
   which the isolation gate admits for this harness alone
   (`Harness.fixedSurface`); `exec` reaches no file and starts no process.
   Codex's environment, permissions, and collaboration-mode context blocks are
   off, so the model's input is three blocks: Codex's base instructions, the
   system prompt as `developer_instructions`, and the user prompt.  What was
   presented is read from Codex's own trace of its first request
   (`codex-surface.json`), not inferred.
+  **Nothing of the operator's**.  Each subject gets a fresh `CODEX_HOME`
   outside the run directory (`.codex-homes/<run-id>/<id>` beside it), removed
   afterward unless `--persist-sessions` is on.  It holds the configuration the
   harness wrote (`prompts/codex-config.toml` is its template; Codex runs with
   `--strict-config`, so a key it does not know refuses the subject) and
   `auth.json` as a symbolic link to the operator's login, so no token is
   copied and a refreshed one lands in the operator's file.  AGENTS.md
   discovery, skills, plugins, apps, hooks, memories, web search, and agents
   are off, and the model catalog is the run's pinned copy
   (`codex-models.json`, from `data/benchmarks/codex-models.json`), never
   fetched.  The sandbox is a named permission profile: the system directories
   (`:minimal`), the work directory writable, Codex's own package readable,
   the network off.  The environment is the harness's less every `CLAUDE*`,
   `OPENAI*`, `CODEX*`, and `ANTHROPIC*` variable, `RUST_LOG` (at `info`,
   Codex logs the account's e-mail address), and `LD_LIBRARY_PATH`.
+  **Effort**.  An OpenAI model takes a reasoning effort, which a Claude
   subject is not given; `--effort` sets it, the default is the catalog's for
   the model, and `protocol.json` records it.
+  **Caps, enforced by the harness**.  Codex has no turn or budget cap, so the
   harness reads the session's rollout as Codex writes it and interrupts the
   subject (SIGINT, which `codex exec` ends as an interrupted turn) once it
   has made `maxTurns` model responses, or once their tokens (a compaction's
   included) cost `maxBudgetUsd` at the run's price table; the wall cap is the
   same kill as a Claude subject's, and counts the servers' start as a Claude
   subject's does (Codex waits up to 600 s for agda's handshake, which took
   63 s on a loaded machine).  As Claude Code's `--max-turns` does, the
   stop waits until the last response's calls have returned, since agda-mcp's
   `fill_hole` edits the work file in place and restores it only when it
   returns, and it never interrupts a response that called nothing, which is
   the turn ending on its own.  A code-mode cell that yielded counts as
   returned: under this protocol a cell reaches only `apply_patch` and Codex's
   own resource tools, never an agda tool.  A stop can lag its cap by a
   response, never land early: when the poll misses the moment between two
   responses, when a response called nothing without ending the turn, or when
   Codex never recorded a compaction's summary, which then counts as a
   response.  The protocol's `capsEnforced` names who enforced each cap
   (`client` for a Claude run's turns and budget, `harness` for all three
   here), and a stopped subject's `terminal` is `max_turns` or `budget`, as a
   Claude subject's is; a subject ended while `fill_hole` or `get_goal` was
   running is an anomaly, since its final file is not known to be its own.
+  **The transcript is derived**.  The adapter (`CodexTranscript`, version 1)
   writes `transcript.jsonl` in the client's `stream-json` schema from three
   files the subject leaves, archived beside it: `codex-events.jsonl` (the
   `--json` event stream), `codex-rollout.jsonl` (Codex's session log, with
   the account's identifiers dropped and the base instructions and encrypted
   reasoning replaced by their digest and length), and `codex-surface.json`.
   One model response is one assistant turn with its tokens; a compaction is
   no turn, but its tokens are in the row's usage and price.  A call is named
   as the judge expects: an agda tool as `mcp__agda__<tool>`, the `files`
   server's `read` as `Read`, and each hunk of an `apply_patch` as an `Edit`
   of the file it names, the hunks of one patch counting as one call; a patch
   Codex refused before applying it is one failed `Edit`, as a Claude
   subject's refused Edit is, of the files the refusal names, else of every
   file the cell's patches name.  Calls are in the order the response issued
   them.  A call's result is the text the model was shown, cut to the model's
   budget, and a server call Codex never completed (a stop, arguments that
   were no JSON) is a failed call of its response.  A re-judge derives the
   transcript again from the archived files, so a fix to the adapter reaches
   every archived Codex row at no model cost.  A subject whose records disagree
   (a required server that did not start, a rollout shorter than the event
   stream, no trace of the first request, a version, model, or effort other
   than the protocol's, a model the backend rerouted, a system prompt missing
   from the model's input, a nested call whose response cannot be told) is an
   anomaly that names the reason, never a row.
+  **Cost, and the usage windows**.  On a ChatGPT login a Codex session is
   billed against the plan's five-hour and weekly windows, not per token, so a
   Codex row's client figure, `costUsd`, is `null` (`costBasis: "none"` in its
   `modelUsage`), and `pricedCostUsd` is the list price of the tokens Codex
   reported, at `data/benchmarks/prices-openai.json` (OpenAI's API prices;
   Codex reports cache writes as 0, so the figure is at most 20 % under on
   written tokens).  A row's `rateLimit` carries the windows' percentages after
   it.  The harness launches no further subject once the five-hour window
   reaches 95 % or the weekly one 97 %, after a usage limit or a failed login,
   after two subjects in a row that did not start (a required server, or Codex
   itself) or that the harness failed on after launching them, and while the
   account holds ChatGPT credits (which a run would spend) unless
   `--allow-credits` is on; the rows it did not launch are anomalies (`not
   run`, with the reason), and a `--resume` launches them, with
   `--allow-credits on` when that was the reason.
+  **Credentials**.  Besides the environment's, the login's own values (its
   tokens, account identifier, and e-mail address, read from `auth.json` in
   memory only) are replaced in everything a subject wrote, searched for in
   the run directory when the report is written, and searched for by `make
   agent-bench-archive`, which refuses a run directory holding one, and
   refuses a Codex run (one whose protocol or report names the harness) when
   the search cannot run (no `jq`, or no login to read;
   `AGENT_BENCH_ARCHIVE_NO_LOGIN=1` archives a run whose login is gone, with a
   warning).  The archive searches for the login as it is then: a token
   refreshed since the run is searched for by the run's own scrub, which reads
   the login again after every subject, and not by the archive.  A login of
   another kind than a ChatGPT login or an API key (an access token, an agent
   identity) is refused at start, since its secrets are not the ones searched
   for.
+  **A resume, and a re-judge**.  A `--resume` across harnesses is refused in
   one line naming the change (`harness: "claude" -> "codex"`) rather than
   every field the two protocols do not share; within a Codex run,
   `--allow-credits` and `--persist-sessions` may change, since neither
   changes what a subject sees or how it is judged.  `make agent-bench-rejudge`
   re-judges a Codex run as it does any other, with no flag, since the run's
   protocol names its harness.

## What a run directory holds

| path | contents |
|---|---|
| `report.json` | the run: `config` (the protocol below, and the run's own knobs), `corpora` (paths and digests), `pricing` (the table that priced the report, by path, digest, and date, with the rates of the rows it used; per model the run's token counts, the client's figure, the priced one, and the row that priced it, which are the counts to check against a provider's usage page; the models no row priced; how many rows have no figure, `unpricedRows`; the client's price bases), `totals`, `perTier`, `perStratum` (each with `solved`, `restated`, and `solvedOriginalInView`, which is `null` on a slice with no original, and `costUsd` beside `pricedCostUsd` and `unpricedRows`), `perTool`, and one `outcomes[]` entry per obligation (`solved`, `restated`, `gate`, `restatementEvidence`, `original`, `addedImports`, `terminal`, `turns`, `toolCalls`, `wallMs`, `costUsd`, `pricedCostUsd` with `unpriced` and `unpricedModels` when it is `null`, `pricingCaveats`, `tokens` (the main loop's `usage` block, which can miss calls), `usageByModel` (every model's, as priced), `credentialsRedacted`, `isolation`, `agdaExit`) |
| `protocol.json` | the protocol, written before the first subject spawns: the arm, the model, the `endpoint` block, the caps, the client's flags and version, the tools, the read roots, the prompts by digest, and every input by content (the index, the binaries, the corpora, the price table); a `--resume` is refused when it differs |
| `prices.json` | the price table the run was priced at, byte for byte, so a re-judge and a resume price at the run's own (from [#237]) |
| `credential-leaks.json` | present only when a run found a credential value left in its directory: the files and the variables, never the values; the archive target refuses the run while it exists (from [#237]) |
| `results.jsonl` | one `eval-proof-completion.v0` attempt row per `fill_hole` the subject probed, the refused ones included: a reply that was an error (no hole at the address the call named, or no address) or that the strict reader could not decode is a row with `status` `crash`, `elapsedMs` 0, and `rc` -1, the reader's defaults, with no `agda` run behind it (`Audit.attemptRows`); a run whose subjects never called `fill_hole`, such as every `shell` arm, has an empty file |
| `fixtures.jsonl` | one `eval-proof-completion.v0` fixture row per obligation, plus `restated`, `gate`, and `terminal` |
| `prompts/` | the system prompt and the user-prompt template, verbatim |
| `subjects/<id>/transcript.jsonl` | the client's `stream-json` output: every tool call with its result, the model's text, the init and result records (a Codex subject's is derived in that schema from its own records, below) |
| `subjects/<id>/final/<Stem>.agda` | the file as the subject left it, which is what was judged |
| `subjects/<id>/outcome.json` | the judge's verdict and the transcript audit for that row, with its `original` block: the restated lemma's file, whether its proof was in view before the last edit (`inView`, `how`, `at`, the call's index from 0), and the successful and refused calls that named the file (`reads`, `refusedReads`); `null` on a row with no original |
| `subjects/<id>/subject.json` | the arm the subject ran under, the roots its tools and commands were allowed, which is what a re-judge audits against, and the `endpoint` block that served it (from [#237]) |
| `subjects/<id>/mcp.json`, `prompt.txt`, `system-prompt.txt`, `run.json` | the subject's server configuration (an arm with the server), its two rendered prompts, and how its process ended (`run.json`: exit code, wall, whether the wall cap killed it, and from [#237] when it started and the credential variables whose values were replaced in what it wrote) |
| `subjects/<id>/stderr.log` | the client's standard error, archived when it is not empty; this is what an anomaly message means by "see stderr.log" |
| `codex-models.json`, `prompts/codex-config.toml`, `prompts/codex-base-instructions-<sha12>.md` | a Codex run's pinned model catalog, the template of its subjects' configuration, and Codex's base instructions, once per digest (from [#239]) |
| `subjects/<id>/codex-events.jsonl`, `codex-rollout.jsonl`, `codex-surface.json`, `codex-config.toml` | a Codex subject's own records, from which its `transcript.jsonl` is derived: the `--json` event stream, Codex's session log (filtered), what its first request presented, and the configuration it ran under (from [#239]) |

A subject that ended early has only what it wrote: the archive copies each of
these when it exists, so a run with anomalous rows archives like any other.

The work copies, the staging server's log, and Agda's interface files stay
behind under `data/benchmarks/reports/agent-bench/<run-id>/` (gitignored).

## The runs

Every run dated before 2026-09-29 had the fixture headers' hints in view (the
"header hints" column): a subject works on a byte-for-byte copy of its
obligation, and until [#219] every obligation's header carried a `Strategy:`
line sketching the proof, the haystack tier's a `Needle:` line naming the
lemma the tier asks a searcher to find, and the mined tiers' a `Source:` line
naming the module that holds the original.  The runs dated 2026-09-29 had
none, and neither has any run since: the headers were stripped from every tier
first (PRs [#220] and [#221]), and what they said is in each tier's README.
The composition tier's arms and the hard tier's header-free re-runs (the
`comp-*` and `hard219-*` runs, [#160] and [#219]) are among them.  Neither the
loop nor the judge reads comments, so no verdict of an old run would change
under a re-judge; what changed is what a subject was told.  The old runs stay
as archived, and the section on the header-free arms below says which of their
figures the new runs replace.

The cost column is the client's own figure, `totals.costUsd`.  Every run
below ran on Anthropic's API, where that figure is the list price for every
model the client can price: priced from each transcript at the committed
table it comes out the same, as `PricingSpec` checks, though these reports
predate the `pricedCostUsd` field ([#237]).  The exception is Sonnet 5.5
(the `*sonnet55*` rows), which client 2.1.282 cannot price: its column is
priced from each subject's `modelUsage` at the committed table's
`claude-sonnet-5-5` row, with the client's figure beside it.  A run on another
endpoint quotes `totals.pricedCostUsd` there instead, at the table it names,
and so does a Codex run (the `*239*` rows, [#239]), whose client reports no
cost: it is the list price of the tokens Codex reported, at OpenAI's table.  A
Codex row measures Codex CLI with the model, as every other row measures
Claude Code with its model, so no figure in it is the model's alone.

| run id | arm | model | date | header hints | obligations | solved | restated | original in view (of agda-algebras solves) | anomalies | turns | tool calls | cost (USD, list) | quoted in |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `smoke-haiku-1` | `mcp` | `claude-haiku-4-5-20251001` | 2026-09-15 | in view | 1 | 1 | 0 | not re-judged | 0 | 4 | 3 | 0.04 | the isolation verification on [#154] |
| `cost-sonnet-1` | `mcp` | `claude-sonnet-5` | 2026-09-15 | in view | 2 | 1 | 1 | not re-judged | 0 | 10 | 8 | 0.28 | the cost estimate on [#154] |
| `cost-opus-1` | `mcp` | `claude-opus-5` | 2026-09-15 | in view | 2 | 2 | 0 | not re-judged | 0 | 12 | 10 | 0.47 | the cost estimate on [#154] |
| `agent-sonnet5-1` | `mcp` | `claude-sonnet-5` | 2026-09-15 | in view | 55 | 46 | 8 | 0 of 13 | 0 | 327 | 272 | 4.62 | ADR 0001 § 9, README, [#154] |
| `agent-opus5-1` | `mcp` | `claude-opus-5` | 2026-09-15 | in view | 55 | 54 | 1 | 0 of 20 | 0 | 325 | 270 | 9.14 | ADR 0001 § 9, README, [#154] |
| `agent-opus5-2` | `mcp` | `claude-opus-5` (second seed) | 2026-09-15 | in view | 55 | 54 | 1 | 0 of 20 | 0 | 338 | 283 | 9.46 | ADR 0001 § 9, [#154] |
| `arm162-shell-1` | `shell` | `claude-sonnet-5` | 2026-09-21 | in view | 55 | 50 | 0 | 15 of 18 | 0 | 308 | 253 | 2.88 | ADR 0001 § 9, ADR 0002 § 12, [#162] |
| `arm162-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-21 | in view | 55 | 47 | 6 | 4 of 14 | 0 | 342 | 287 | 5.28 | ADR 0001 § 9, ADR 0002 § 12, [#162] |
| `arm162-both-1` | `both` | `claude-sonnet-5` | 2026-09-21 | in view | 55 | 51 | 2 | 16 of 19 | 0 | 327 | 272 | 4.25 | ADR 0001 § 9, ADR 0002 § 12, [#162] |
| `iso184-1` | `mcp` | `claude-sonnet-5` | 2026-09-25 | in view | 1 | 1 | 0 | not re-judged | 0 | 4 | 3 | 0.11 | the isolation check for client 2.1.282 on [#184] |
| `cost184-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-25 | in view | 2 | 1 | 1 | not re-judged | 0 | 10 | 8 | 0.12 | the cost pair on [#184] |
| `cost184-both-1` | `both` | `claude-sonnet-5` | 2026-09-25 | in view | 2 | 1 | 1 | not re-judged | 0 | 15 | 13 | 0.27 | the cost pair on [#184] |
| `arm184-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-25 | in view | 55 | 46 | 8 | 3 of 12 | 0 | 359 | 304 | 4.63 | [#184], PR [#190] |
| `arm184-both-1` | `both` | `claude-sonnet-5` | 2026-09-25 | in view | 55 | 49 | 2 | 14 of 18 | 0 | 318 | 263 | 4.00 | [#184], PR [#190] |
| `cost-surface-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-26 | in view | 2 | 0 | 1 | 0 of 0 | 0 | 11 | 9 | 0.15 | the cost pairs on [#191] |
| `cost-surface-both-1` | `both` | `claude-sonnet-5` | 2026-09-26 | in view | 2 | 1 | 1 | 0 of 0 | 0 | 14 | 12 | 0.23 | the cost pairs on [#191] |
| `cost-verdict-mcp-1` | `mcp`, four tools exposed | `claude-sonnet-5` | 2026-09-26 | in view | 2 | 0 | 1 | 0 of 0 | 0 | 17 | 15 | 0.16 | the cost pairs on [#191] |
| `arm-surface-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-26 | in view | 55 | 48 | 7 | 6 of 14 | 0 | 345 | 290 | 3.83 | [#191], PR [#193] |
| `arm-surface-both-1` | `both` | `claude-sonnet-5` | 2026-09-26 | in view | 55 | 46 | 4 | 8 of 14 | 0 | 318 | 263 | 3.55 | [#191], PR [#193] |
| `arm-verdict-mcp-1` | `mcp`, four tools exposed | `claude-sonnet-5` | 2026-09-26 | in view | 55 | 52 | 1 | 9 of 20 | 0 | 458 | 403 | 3.78 | [#191], PR [#193] |
| `arm-verdict-mcp-2` | `mcp`, four tools exposed (second seed) | `claude-sonnet-5` | 2026-09-26 | in view | 55 | 53 | 2 | 6 of 19 | 0 | 461 | 406 | 3.84 | [#191], PR [#193] |
| `arm-surface-mcp-2` | `mcp` (second seed) | `claude-sonnet-5` | 2026-09-26 | in view | 55 | 45 | 8 | 2 of 13 | 0 | 349 | 294 | 3.74 | [#191], PR [#193] |
| `cost-hard-shell-1` | `shell` | `claude-opus-5` | 2026-09-27 | in view | 2 | 1 | 0 | no original | 0 | 25 | 23 | 1.50 | the cost pairs on [#189] |
| `cost-hard-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-27 | in view | 2 | 2 | 0 | no original | 0 | 28 | 26 | 2.66 | the cost pairs on [#189] |
| `cost-hard-both-1` | `both` | `claude-opus-5` | 2026-09-27 | in view | 2 | 1 | 0 | no original | 0 | 30 | 28 | 2.17 | the cost pairs on [#189] |
| `hard-opus5-shell-1` | `shell` | `claude-opus-5` | 2026-09-27 | in view | 14 (hard tier) | 8 | 0 | no original | 0 | 174 | 160 | 6.41 | [#189], PR [#197], the guide's § 4.5 |
| `hard-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-27 | in view | 14 (hard tier) | 14 | 0 | no original | 0 | 143 | 129 | 7.82 | [#189], PR [#197], the guide's § 4.5 |
| `hard-opus5-both-1` | `both` | `claude-opus-5` | 2026-09-27 | in view | 14 (hard tier) | 8 | 0 | no original | 0 | 162 | 148 | 6.62 | [#189], PR [#197], the guide's § 4.5 |
| `cost-suite219-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-29 | none | 2 | 1 | 1 | 0 of 0 | 0 | 10 | 8 | 0.15 | the cost pairs on [#219] |
| `cost-suite219-sonnet5-shell-1` | `shell` | `claude-sonnet-5` | 2026-09-29 | none | 2 | 1 | 1 | 0 of 0 | 0 | 13 | 11 | 0.14 | the cost pairs on [#219] |
| `cost-suite219-sonnet5-both-1` | `both` | `claude-sonnet-5` | 2026-09-29 | none | 2 | 1 | 1 | 0 of 0 | 0 | 12 | 10 | 0.20 | the cost pairs on [#219] |
| `cost-suite219-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-29 | none | 2 | 2 | 0 | 1 of 1 | 0 | 12 | 10 | 0.36 | the cost pairs on [#219] |
| `suite219-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-29 | none | 55 | 44 | 9 | 4 of 11 | 0 | 347 | 292 | 3.99 | ADR 0001 § 9, ADR 0002 § 12, README, the site, [#219] |
| `suite219-sonnet5-shell-1` | `shell` | `claude-sonnet-5` | 2026-09-29 | none | 55 | 47 | 4 | 12 of 14 | 0 | 345 | 290 | 3.42 | ADR 0001 § 9, ADR 0002 § 12, the site, [#219] |
| `suite219-sonnet5-both-1` | `both` | `claude-sonnet-5` | 2026-09-29 | none | 55 | 48 | 5 | 11 of 16 | 0 | 353 | 298 | 4.13 | ADR 0001 § 9, ADR 0002 § 12, the site, [#219] |
| `suite219-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-29 | none | 55 | 55 | 0 | 4 of 21 | 0 | 323 | 268 | 7.07 | ADR 0001 § 9, README, the site, [#219] |
| `cost-comp-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-29 | none | 2 (composition) | 2 | 0 | no original | 0 | 19 | 17 | 0.71 | the cost pairs on [#160] |
| `cost-comp-opus5-shell-1` | `shell` | `claude-opus-5` | 2026-09-29 | none | 2 (composition) | 1 | 0 | no original | 0 | 28 | 26 | 0.74 | the cost pairs on [#160] |
| `cost-comp-opus5-both-1` | `both` | `claude-opus-5` | 2026-09-29 | none | 2 (composition) | 2 | 0 | no original | 0 | 25 | 23 | 0.96 | the cost pairs on [#160] |
| `cost-comp-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-29 | none | 2 (composition) | 1 | 0 | no original | 0 | 37 | 35 | 0.69 | the cost pairs on [#160] |
| `cost-comp-sonnet5-shell-1` | `shell` | `claude-sonnet-5` | 2026-09-29 | none | 2 (composition) | 2 | 0 | no original | 0 | 28 | 26 | 0.50 | the cost pairs on [#160] |
| `cost-comp-sonnet5-both-1` | `both` | `claude-sonnet-5` | 2026-09-29 | none | 2 (composition) | 0 | 0 | no original | 0 | 30 | 28 | 0.53 | the cost pairs on [#160] |
| `comp-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-29 | none | 12 (composition) | 12 | 0 | no original | 0 | 128 | 116 | 4.05 | the guide's § 4.7, [#160] |
| `comp-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-29 | none | 12 (composition) | 3 | 0 | no original | 0 | 206 | 194 | 3.55 | the guide's § 4.7, [#160] |
| `hard219-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-29 | none | 14 (hard tier) | 14 | 0 | no original | 0 | 139 | 125 | 7.71 | the guide's § 4.5, the site, [#219] |
| `comp-opus5-shell-1` | `shell` | `claude-opus-5` | 2026-09-29 | none | 12 (composition) | 10 | 0 | no original | 0 | 130 | 118 | 4.14 | the guide's § 4.7, [#160] |
| `comp-opus5-both-1` | `both` | `claude-opus-5` | 2026-09-29 | none | 12 (composition) | 10 | 0 | no original | 0 | 148 | 136 | 4.87 | the guide's § 4.7, [#160] |
| `comp-sonnet5-shell-1` | `shell` | `claude-sonnet-5` | 2026-09-29 | none | 12 (composition) | 6 | 0 | no original | 0 | 157 | 145 | 2.60 | the guide's § 4.7, [#160] |
| `comp-sonnet5-both-1` | `both` | `claude-sonnet-5` | 2026-09-29 | none | 12 (composition) | 5 | 0 | no original | 0 | 179 | 167 | 3.39 | the guide's § 4.7, [#160] |
| `hard219-opus5-shell-1` | `shell` | `claude-opus-5` | 2026-09-29 | none | 14 (hard tier) | 10 | 0 | no original | 0 | 148 | 134 | 6.31 | the guide's § 4.5, the site, [#219] |
| `hard219-opus5-both-1` | `both` | `claude-opus-5` | 2026-09-29 | none | 14 (hard tier) | 10 | 0 | no original | 0 | 174 | 160 | 6.56 | the guide's § 4.5, the site, [#219] |
| `cost-answers-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-10-03 | none | 2 (hard tier) | 2 | 0 | no original | 0 | 32 | 30 | 2.42 | the cost pairs on [#185] and [#201] |
| `cost-answers-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-10-03 | none | 2 | 2 | 0 | 0 of 1 | 0 | 14 | 12 | 0.17 | the cost pairs on [#185] and [#201] |
| `hard-answers-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-10-03 | none | 14 (hard tier) | 14 | 0 | no original | 0 | 127 | 113 | 6.34 | [#185], [#201], PRs [#228] and [#229] |
| `suite-answers-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-10-03 | none | 55 | 47 | 6 | 5 of 15 | 0 | 332 | 277 | 3.56 | [#185], [#201], PRs [#228] and [#229] |
| `cost202-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-10-03 | none | 2 | 1 | 1 | 0 of 0 | 0 | 10 | 8 | 0.20 | the cost pair on [#202], [#203] |
| `arm202-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-10-03 | none | 55 | 43 | 9 | 3 of 11 | 0 | 317 | 262 | 3.54 | [#202], [#203], PRs [#231], [#232] |
| `rejudge290-suite219-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-29, re-judged 2026-10-13 | none | 55 | 55 | 0 | 4 of 21 | 0 | 323 | 268 | no model call | the re-judge under Agda 2.9.0, [#236] |
| `rejudge290-suite219-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-29, re-judged 2026-10-13 | none | 55 | 44 | 9 | 4 of 11 | 0 | 347 | 292 | no model call | the re-judge under Agda 2.9.0, [#236] |
| `rejudge290-comp-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-29, re-judged 2026-10-13 | none | 12 (composition) | 12 | 0 | no original | 0 | 128 | 116 | no model call | the re-judge under Agda 2.9.0, [#236] |
| `rejudge290-comp-sonnet5-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-29, re-judged 2026-10-13 | none | 12 (composition) | 3 | 0 | no original | 0 | 206 | 194 | no model call | the re-judge under Agda 2.9.0, [#236] |
| `rejudge290-hard219-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-09-29, re-judged 2026-10-13 | none | 14 (hard tier) | 14 | 0 | no original | 0 | 139 | 125 | no model call | the re-judge under Agda 2.9.0, [#236] |
| `cost236-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-10-13 | none | 2 | 2 | 0 | 1 of 1 | 0 | 12 | 10 | 0.37 | the cost pairs on [#236] |
| `cost236-sonnet55-mcp-1` | `mcp` | `claude-sonnet-5-5` | 2026-10-13 | none | 2 | 1 | 1 | 0 of 0 | 0 | 11 | 9 | 0.12 (the client's figure 0.59) | the cost pairs on [#236] |
| `cost236-opus55-mcp-1` | `mcp` | `claude-opus-5-5` | 2026-10-13 | none | 2 | 2 | 0 | 1 of 1 | 0 | 11 | 9 | 0.24 | the cost pairs on [#236] |
| `suite236-opus5-mcp-1` | `mcp` | `claude-opus-5` | 2026-10-13 | none | 55 | 54 | 0 | 5 of 21 | 0 | 309 | 254 | 6.91 | the guide's § 4.8, [#236] |
| `suite236-sonnet55-mcp-1` | `mcp` | `claude-sonnet-5-5` | 2026-10-13 | none | 55 | 51 | 4 | 3 of 17 | 0 | 281 | 226 | 2.09 (the client's figure 9.69) | the guide's § 4.8, [#236] |
| `comp236-sonnet55-mcp-1` | `mcp` | `claude-sonnet-5-5` | 2026-10-13 | none | 12 (composition) | 11 | 0 | no original | 0 | 119 | 107 | 1.26 (the client's figure 5.40) | the guide's § 4.8, [#236] |
| `hard236-sonnet55-mcp-1` | `mcp` | `claude-sonnet-5-5` | 2026-10-13 | none | 14 (hard tier) | 14 | 0 | no original | 0 | 145 | 131 | 1.81 (the client's figure 7.65) | the guide's § 4.8, [#236] |
| `suite236-opus55-mcp-1` | `mcp` | `claude-opus-5-5` | 2026-10-13 | none | 55 | 37 | 1 | 0 of 4 | 0 | 270 | 215 | 3.78 | the guide's § 4.8, [#236] |
| `comp236-opus55-mcp-1` | `mcp` | `claude-opus-5-5` | 2026-10-13 | none | 12 (composition) | 4 | 0 | no original | 0 | 109 | 97 | 2.07 | the guide's § 4.8, [#236] |
| `hard236-opus55-mcp-1` | `mcp` | `claude-opus-5-5` | 2026-10-13 | none | 14 (hard tier) | 10 | 0 | no original | 0 | 118 | 104 | 2.51 | the guide's § 4.8, [#236] |
| `smoke239-sol-2` | `mcp`, Codex CLI 0.162.1 at effort `low` | `gpt-6.1-sol` | 2026-10-14 | none | 1 | 1 | 0 | 0 of 0 | 0 | 4 | 3 | 0.05 (priced; Codex reports none) | the Codex subject's smoke, [#239] |
| `cost239-sol-mcp-2` | `mcp`, Codex CLI 0.162.1 at effort `low` | `gpt-6.1-sol` | 2026-10-14 | none | 2 | 2 | 0 | 1 of 1 | 0 | 9 | 7 | 0.07 (priced) | the cost pairs on [#239] |
| `cost239-astra-mcp-2` | `mcp`, Codex CLI 0.162.1 at effort `low` | `gpt-6-astra` | 2026-10-14 | none | 2 | 1 | 1 | 0 of 0 | 0 | 9 | 7 | 0.41 (priced) | the cost pairs on [#239] |
| `suite239-sol-mcp-1` | `mcp`, Codex CLI 0.162.1 at effort `low` | `gpt-6.1-sol` | 2026-10-14 | none | 55 | 54 | 1 | 6 of 20 | 0 | 266 | 209 | 2.09 (priced) | the guide's § 4.9, the Codex arms, [#239] |
| `comp239-sol-mcp-1` | `mcp`, Codex CLI 0.162.1 at effort `low` | `gpt-6.1-sol` | 2026-10-14 | none | 12 (composition) | 12 | 0 | no original | 0 | 95 | 74 | 0.89 (priced) | the guide's § 4.9, the Codex arms, [#239] |
| `hard239-sol-mcp-1` | `mcp`, Codex CLI 0.162.1 at effort `low` | `gpt-6.1-sol` | 2026-10-14 | none | 14 (hard tier) | 14 | 0 | no original | 0 | 116 | 94 | 1.09 (priced) | the guide's § 4.9, the Codex arms, [#239] |
| `hard239-astra-mcp-1` | `mcp`, Codex CLI 0.162.1 at effort `low` | `gpt-6-astra` | 2026-10-14 | none | 14 (hard tier) | 14 | 0 | no original | 0 | 117 | 100 | 5.76 (priced) | the guide's § 4.9, the Codex arms, [#239] |
| `hard239-sol-high-mcp-1` | `mcp`, Codex CLI 0.162.1 at effort `high` | `gpt-6.1-sol` | 2026-10-14 | none | 14 (hard tier) | 14 | 0 | no original | 0 | 146 | 113 | 1.26 (priced) | the guide's § 4.9, the Codex arms, [#239] |

The column "original in view" is the judge's `original` reading ([#188]):
of the run's agda-algebras solves, the number whose restated lemma's own
proof came back in one of the subject's tool answers before its last edit of
the work file (a call that names the lemma's file without showing its proof
does not count).  It is a column, not a gate: no verdict depends on it.  The
eight full arms were re-judged on copies to add it, with every verdict as
archived; the six subset runs made before it were not, since three of them
predate the judge's Agda-based gates and a re-judge would rewrite more than
this column, and none has more than one agda-algebras row.  The [#191] runs
were judged with it.

Per stratum, solved and restated (first arms), beside the loop's fixed space
and retrieval under exclusion on `main`, and beside the floor: what Agda's own
proof search solves at the hole with no model and no corpus, each term judged
by `fill_hole` under `--safe` ([`reports/auto-floor/`](../auto-floor/README.md),
issue [#205]):

| stratum | n | Agda's search alone | loop fixed | loop retrieval | Sonnet 5 | Opus 5 |
|---|---|---|---|---|---|---|
| agda-stdlib | 22 | 6 | 6 | 6 | 21 solved | 22 solved |
| agda-stdlib/haystack | 12 | 0 | 0 | 6 | 12 solved | 12 solved |
| agda-algebras/using | 11 | 4 | 2 | 2 | 9 solved, 2 restated | 11 solved |
| agda-algebras/wholesale | 10 | 7 | 0 | 0 | 4 solved, 6 restated | 9 solved, 1 restated |

Agda's search alone solves 17 of the 55, so an arm's count is read against
that floor.  On the wholesale stratum, where the loop finds nothing, Agda
solves seven rows from the context and the records' own fields; four of the
six rows the Sonnet arm restated there are among them, and so is the one row
both Opus seeds restate (`algebras-homs-mon-to-hom`).  So most of those
restatements cited a lemma for a row that Agda's own search, which no arm
was offered, proves by itself.

The two Opus seeds solve the same 54 rows and restate the same one
(`algebras-homs-mon-to-hom`); 44 of their 55 final files are byte-identical,
31 rows took the same number of turns, and the arms differ by 13 turns and 13
tool calls in total, so on this suite the model's run-to-run variance shows in
how it gets there, not in what it solves.

The one Sonnet row that is neither solved nor restated
(`stdlib-nat-mul-comm`) appended `; trans` to an original `using` list rather
than adding an import line, which the preservation gate refuses by the
protocol; its `outcome.json` records that the file type-checks (`agdaExit` 0).

These first arms had the headers' hints in view; their header-free re-runs
are `suite219-sonnet5-mcp-1` and `suite219-opus5-mcp-1`, in
[the header-free arms](#the-header-free-arms-2026-09-29-219) below.

## The attribution arms (2026-09-21, [#162])

The three arms above were run fresh at one protocol version, one arm at a
time, to ask what the server is worth: `shell` gives the subject Bash and the
pinned `agda`, `mcp` gives it the server, `both` gives it both.  Zero
anomalies in all three; USD 12.41 together.  Their subjects had the headers'
hints in view; the same three arms without them are the `suite219-sonnet5-*`
runs in [the header-free arms](#the-header-free-arms-2026-09-29-219) below.

| stratum | n | archive `mcp` | `shell` | `mcp` | `both` |
|---|---|---|---|---|---|
| agda-stdlib | 22 | 21 solved | 20 solved | 21 solved | 20 solved |
| agda-stdlib/haystack | 12 | 12 solved | 12 solved | 12 solved | 12 solved |
| agda-algebras/using | 11 | 9 solved, 2 restated | 9 solved | 9 solved, 1 restated | 11 solved |
| agda-algebras/wholesale | 10 | 4 solved, 6 restated | 9 solved | 5 solved, 5 restated | 8 solved, 2 restated |
| **total** | 55 | **46 solved, 8 restated** | **50 solved, 0 restated** | **47 solved, 6 restated** | **51 solved, 2 restated** |

The `both` arm is the decisive column: offered both instruments, the subject
took **all 55 verdicts from `check_file`** and ran `agda` on the shell not
once, while using Bash 65 times, every call a library-source read.  The
server's knowledge tools collapse beside a shell (`definition_of` 19 calls in
the `mcp` arm and 0 in the `both` arm; `search_by_name` 18 and 1; `type_of` 34
and 11), and `check_file` does not move (56 and 57).  The restated column
follows: the `shell` arm consulted library sources 82 times against the `mcp`
arm's 13, because `grep` over a tree needs no prior knowledge of where a thing
is.  What that reading put in view is the judge's `original` column ([#188]):
the restated lemma's own proof came back before the last edit for 15 of the
`shell` arm's 18 agda-algebras solves, 4 of the `mcp` arm's 14, and 16 of the
`both` arm's 19, and for none of the archived arms', whose reads of the
library were refused.  The column records what was shown, not what was
written from it.  Some bodies are the library's own (`⊙-hom′` and the two
lines of `≤-trans-≅′` differ from it only by the prime on the name), but an
identical body proves no copying either: Opus wrote the library's
`mon→hom` term in the [#154] cost pair with no read of the library at all.
The restated rule reads references, so it refuses a citation and cannot see
a transcription.

Three protocol differences from the archived arms, all recorded and none of
them measurable in the verdicts: the server presents fourteen tools rather
than thirteen (`search_in_scope`, PR [#161], called zero times in either
server arm); the libraries' sources are readable on every arm; and the
subjects' servers carry the judge's `--safe`.  The `mcp` arm re-run differs
from `agent-sonnet5-1` on 7 of 55 rows, which cancel to 47 and 6 against 46
and 8, inside the run-to-run variance the two Opus seeds already document.

Five rows across the two shell-bearing arms failed the isolation gate, and
every one of those files type-checks with its statement preserved and no
restatement evidence, so 50 and 51 are lower bounds and the files earned 54
and 52.  Three of the five are subjects hunting for Agda's own primitive
modules (`Agda.Builtin.*`, which ship in Agda's data directory and belong to
no registered library, so no read root contains them) and searching the
filesystem to find them; two are the audit refusing `xargs`, which takes its
paths from standard input and so names none the reader can account for.
Neither was changed while the comparison was running, because one audit
across three arms is what makes them comparable.

Two things no subject did, in either shell-bearing arm: drive
`agda --interaction-json`, which both prompts name in a sentence (class count
0 against `agda-batch` 56), and grep the corpus, whose path both prompts give
(class count 0).  The extracted corpus is a retrieval substrate, not something
an agent reads.

## The lean-answer arms (2026-09-25, [#184])

The `mcp` and `both` arms of [#162], run again with one change to the
server (PR [#190]): its default answer is lean, keeping only
`verdict.exitCode`, `project.root` and `project.rootSource`, and `lane.load`
from the old echo, with the rest on `verbose: true`; and `exports_of` answers
a page of 20 typed members with the rest named.  Everything else is the [#162] protocol: the
prompts' digests, the index's and the corpora's digests, the caps, and the
read roots are identical.  Two things differ besides the server: the client
(2.1.282 against 2.1.261; `iso184-1` checked it with a persisted session and
found nothing deferred), and the day.  Zero anomalies; USD 8.63 together.

| | `shell` #162 | `mcp` #162 | `mcp` #184 | `both` #162 | `both` #184 |
|---|---:|---:|---:|---:|---:|
| solved | 50 | 47 | 46 | 51 | 49 |
| restated | 0 | 6 | 8 | 2 | 2 |
| lost to a gate | 5 | 2 | 1 | 2 | 4 |
| turns | 308 | 342 | 359 | 327 | 318 |
| tool calls | 253 | 287 | 304 | 272 | 263 |
| USD | 2.88 | 5.28 | 4.63 | 4.25 | 4.00 |
| output tokens | 70,403 | 76,732 | 82,831 | 67,269 | 66,634 |
| cached tokens read per turn | 10,060 | 21,289 | 22,407 | 24,485 | 25,331 |
| characters the tools returned | 259,520 | 929,386 | 534,272 | 474,562 | 223,797 |
| per call | 1,025 | 3,238 | 1,757 | 1,744 | 850 |

Per tool, calls and characters per call:

| tool | `mcp` #162 | `mcp` #184 | `both` #162 | `both` #184 |
|---|---:|---:|---:|---:|
| `check_file` | 56 × 3,358 | 59 × 485 | 57 × 3,384 | 56 × 418 |
| `type_of` | 34 × 3,162 | 15 × 677 | 11 × 3,405 | 11 × 594 |
| `fill_hole` | 11 × 2,890 | 15 × 532 | 9 × 3,396 | 6 × 718 |
| `definition_of` | 19 × 4,327 | 15 × 602 | 0 | 0 |
| `get_goal` | 7 × 2,268 | 4 × 689 | 4 × 2,574 | 1 × 707 |
| `exports_of` | 11 × 23,283 | 17 × 10,219 | 2 × 15,673 | 2 × 764 |
| `search_by_name` | 18 × 6,930 | 31 × 5,099 | 1 × 2,155 | 1 × 2,155 |
| `search_by_type` | 2 × 9,382 | 3 × 10,132 | 0 | 0 |
| `get_dependencies` | 3 × 1,049 | 12 × 643 | 0 | 0 |
| `Bash` | 0 | 0 | 65 × 1,231 | 69 × 1,444 |

The answers shrank as designed and nothing else followed.  Offered a shell
too, the subject called the knowledge tools exactly as rarely as before
(`definition_of` 0, `search_by_name` 1, `exports_of` 2, `type_of` 11) and
again took all 55 verdicts from `check_file`, so the flooding was not why
[#162]'s `both` arm abandoned them.  Given the server alone, it shifted its
mix rather than its volume (87 knowledge calls to 93: `search_by_name` and
`get_dependencies` up, `type_of` down).  Cost fell 12 % and 6 %, not toward
the shell arm's USD 2.88, because a server arm pays for context on every
turn, not for its answers: about 22 to 25 thousand cached tokens a turn
against the shell arm's 10 thousand.  The difference is the fourteen tools'
descriptions and schemas, 68,391 characters before PR [#190] and 77,603
after it, which every turn re-reads.

Three things to read beside the table.

+  **`exports_of`'s page is opted out of**.  Six calls narrowed with
   `pattern` and cost 1.2 to 8.2 thousand characters each; four asked for
   `limit: 0` with no pattern and took the whole surface, 24 to 39 thousand
   each and 112 thousand together, 65 % of the tool's total.  The description
   offers that ("limit 0 returns every member typed"), and the subject took
   the offer.
+  **The solves did not move beyond run-to-run variance**.  On the 34 rows
   with no original to copy, 34 and 31 solved against [#162]'s 33 and 32.
   On the 21 agda-algebras rows the original lemma's proof was in view (the
   judge's `original` column, [#188], read in
   [the results guide](../../docs/reading-the-results.md) § 4.3) for 3 of
   the [#184] `mcp` arm's 12 solves and 14 of its `both` arm's 18, against 4
   of 14 and 16 of 19 in [#162].
+  **Four `both` rows lost a verdict to a gate and type-check** with their
   statements preserved: three preservation-gate rows (`stdlib-nat-mul-*`,
   the edited `using` list the protocol refuses) and one isolation row
   (`algebras-kernels-ker-con`, whose subject ran `find /`).  The `mcp` arm's
   one gate row (`algebras-homs-mon-to-intohom`) left a hole.

## The tool-surface arms (2026-09-26, [#191])

The server's tool surface, cut to a contract stated once (PR [#193]), and a
second variable beside it: how many tools an arm is given.  What every tool
shares now travels once, in the server's `initialize` instructions, and each
description carries its own tool's contract under the 2,048 characters at
which Claude Code 2.1.282 truncates one; before, eleven of the fourteen
descriptions were cut there, so part of the contract never reached a subject.
`tools/list` fell from 77,603 characters to 24,094, plus 1,989 of
instructions (1,981 in the PR's final build, whose `tools/list` is the same,
after review fixes scoped their exit-code rule to `success`; the arms ran
the 1,989).  `arm-surface-mcp-*` and `arm-surface-both-1` are the `mcp` and
`both` arms on that surface; `arm-verdict-mcp-*` is the `mcp` arm with only
`check_file`, `fill_hole`, `get_goal`, and `type_of` exposed (`--expose`),
the four tools the earlier arms took their verdicts and goals from.  The two
`mcp` configurations ran twice each.  Everything else is the [#184]
protocol: the prompts', index's, and corpora's digests, the caps, the read
roots, and the client (2.1.282) are identical; the extractor the judge runs
is a fresh build of unchanged source.  Zero anomalies in the published rows.

| | `shell` #162 | `mcp` #184 | `mcp` #191 (two seeds) | `both` #184 | `both` #191 | four tools (two seeds) |
|---|---:|---:|---:|---:|---:|---:|
| solved | 50 | 46 | 48, 45 | 49 | 46 | 52, 53 |
| restated | 0 | 8 | 7, 8 | 2 | 4 | 1, 2 |
| lost to a gate | 5 | 1 | 0, 2 | 4 | 5 | 2, 0 |
| solved, the 34 rows with no original | 32 | 34 | 34, 32 | 31 | 32 | 32, 34 |
| agda-algebras solved (of 21) | 18 | 12 | 14, 13 | 18 | 14 | 20, 19 |
| of those, the library's proof verbatim | 14 | 9 | 11, 8 | 14 | 11 | 13, 13 |
| of those, original in view (the judge) | 15 | 3 | 6, 2 | 14 | 8 | 9, 6 |
| turns | 308 | 359 | 345, 349 | 318 | 318 | 458, 461 |
| tool calls | 253 | 304 | 290, 294 | 263 | 263 | 403, 406 |
| USD | 2.88 | 4.63 | 3.83, 3.74 | 4.00 | 3.55 | 3.78, 3.84 |
| output tokens | 70,403 | 82,831 | 76,583, 82,054 | 66,634 | 70,780 | 118,006, 114,237 |
| first-turn context (median) | 8,263 | 20,016 | 13,037, 13,037 | 24,866 | 17,915 | 7,405, 7,405 |
| cached tokens read per turn | 10,060 | 22,407 | 15,503, 14,293 | 25,331 | 18,838 | 9,649, 9,524 |

"The library's proof verbatim" is the gold term (the index's `goldTerm`,
which is the library's own proof) appearing in the final file's definition
of the hole after whitespace is normalized; a short gold (`refl`,
`Setoid.refl 𝑨`) is easily found without reading anything, so the column
means reproduction only together with the judge's in-view column.

Per tool, calls and characters per call ("not exposed" where the arm's
protocol did not give the tool, never 0):

| tool | `mcp` #184 | `mcp` #191, seed 1 | seed 2 | four tools, seed 1 | seed 2 |
|---|---:|---:|---:|---:|---:|
| `check_file` | 59 × 485 | 58 × 474 | 58 × 462 | 55 × 415 | 75 × 322 |
| `type_of` | 15 × 677 | 18 × 735 | 27 × 679 | 60 × 663 | 54 × 649 |
| `get_goal` | 4 × 689 | 4 × 836 | 10 × 718 | 23 × 893 | 14 × 760 |
| `fill_hole` | 15 × 532 | 10 × 491 | 15 × 540 | 20 × 538 | 20 × 542 |
| `exports_of` | 17 × 10,219 | 23 × 4,368 | 12 × 6,505 | not exposed | not exposed |
| `search_by_name` | 31 × 5,099 | 23 × 6,260 | 20 × 4,952 | not exposed | not exposed |
| `search_by_type` | 3 × 10,132 | 3 × 5,067 | 2 × 5,336 | not exposed | not exposed |
| `definition_of` | 15 × 602 | 16 × 924 | 12 × 737 | not exposed | not exposed |
| `get_dependencies` | 12 × 643 | 8 × 721 | 6 × 613 | not exposed | not exposed |
| `resolve_name` | 0 | 0 | 3 × 1,399 | not exposed | not exposed |
| `Read`, the work file | 56 | 55 | 56 | 56 | 57 |
| `Read`, the library (failed) | 15 (4) | 13 (1) | 11 (1) | 131 (111) | 125 (97) |

Where each arm's dollars went, by token kind, at prices implied by the
reports themselves (a least-squares fit of every subject's `costUsd` on its
four token counts, exact to a tenth of a cent per subject):

| | `shell` #162 | `mcp` #184 | `mcp` #191 (two seeds) | four tools (two seeds) |
|---|---:|---:|---:|---:|
| cache reads (the context, re-read each turn) | 0.61 | 1.59 | 1.05, 0.98 | 0.87, 0.87 |
| cache writes (each turn's new content) | 1.50 | 2.20 | 2.00, 1.92 | 1.72, 1.83 |
| output | 0.70 | 0.82 | 0.76, 0.82 | 1.17, 1.14 |
| total | 2.88 | 4.63 | 3.83, 3.74 | 3.78, 3.84 |

**The smaller surface closed the per-turn gap, and not the cost gap**.  The
trim took a third of a server arm's context away (a first turn of 20,016
tokens down to 13,037; 22,407 cached tokens a turn down to 15,503 and
14,293) and cut its cost by 17 % and 19 %, about 70 % of the saving in cache
reads and the rest in cache writes.  With four tools the context fell below
the shell arm's (7,405 against 8,263 on the first turn, about 9,600 against
10,060 a turn), yet the arm cost USD 3.78 and 3.84 against 2.88: half the
difference is output (116 thousand tokens against 70) and the rest is 150
more turns, most of them spent reading the library by trial, 131 and 125
reads of which 111 and 97 failed (a directory, or a path guessed with the
wrong extension).

**The trimmed text left the tool mix where it was; the smaller tool set
changed the route, and the route is what the agda-algebras rows measure**.
Given all fourteen tools, the subject used the corpus and navigation tools
73 and 55 times, inside the range of the untrimmed runs (53 on [#162], 78
on [#184]), restated as often (7 and 8 against 6 and 8), and beside a shell
used them as rarely as before; every verdict of both `both` arms came from
`check_file`.  One description change did move behavior: the four
`limit: 0` calls of #184, which took `exports_of`'s whole surface, fell to
none once that offer was stated only on the `limit` property.  Given four
tools, the subject restated once and twice instead of seven and eight
times, in both seeds: five agda-algebras rows were restated in both seeds of
the full surface and solved in both seeds of the subset
(`homs-id-hom`, `homs-mon-to-intohom`, `inverses-inv-inverse-l`,
`inverses-range-to-image`, `subalgebras-sub-reflexive`).  The transcripts
say why.  With the search tools the subject found the library's lemma by
name (`search_by_name`, `exports_of`) and cited it in four to six calls.
Without them it opened the library's modules until it reached the one
holding the original, and wrote the proof out: on those five rows the
original's proof was in view in 7 of the 10 subset subjects, and 5 of the
10 final proofs are the library's verbatim (`homs-mon-to-intohom`'s are the
same proof with the pair pattern-matched).  The judge counts that as
solved, because the restated gate catches naming the lemma and not copying
its proof ([#188] records the same for the shell arm).  So the higher solve
count is not better proving: on the 34 rows with no original to find, every
arm solves 31 to 34, and the subset arm's two seeds solve 32 and 34.

Three things to read beside the tables.

+  **The seeds agree**.  Five full-surface server-only runs now exist (three
   on the untrimmed surface, two trimmed): they solve 45 to 48 and restate 6
   to 8.  The subset's two seeds solve 52 and 53 and restate 1 and 2.
+  **Lost verdicts are a lower bound on the solves**.  Every gate row of
   the [#191] arms type-checks with its statement preserved: the
   preservation gate refusing an edited `using` list
   (`stdlib-nat-plus-comm`, `stdlib-nat-mul-distrib-l`), two subjects that
   ran `find /` (`algebras-subalgebras-sub-trans`, and
   `algebras-kernels-ker-con`, which did the same on [#184]), and the audit
   not modeling `xargs` over a path inside the roots
   (`algebras-homs-id-hom`).  The audit was not changed while the
   comparison ran.
+  **Two subjects of `arm-verdict-mcp-2` were run twice**.  Their servers
   failed to start (status `failed`, empty stderr) when processes on the
   machine were killed by hand at 11:27 UTC; the harness flagged them as
   anomalies, and `--resume on` under the same protocol re-ran just those
   two (both solved) and re-judged the other 53 to their archived verdicts.
   The discarded attempts cost USD 0.12, outside the totals above.  A scan
   of both seed-2 arms for tool results from a killed process found none.

## The hard-tier arms (2026-09-27, [#189])

The first runs on rows with no proof on disk: the fourteen obligations of the
two hard tiers (`data/benchmarks/agda-stdlib-hard-v0/` and
`agda-algebras-hard-v0/`, strata `agda-stdlib/novel` and
`agda-algebras/novel`), posed for the purpose, each with a gold, and with no
`restates:` tag, so no row can be restated and the column "original in
view" has nothing to count.  Opus 5, one seed per arm, at twice the mined
tiers' caps (60 turns, 1,800 s, USD 6.00), parallelism 2, from a frozen copy
of the server and the extractor and a frozen snapshot of the driver's
classes; client 2.1.282, as on [#184] and [#191].  Each arm ran after a
two-row cost pair on rows 1 and 14.  Zero anomalies.

| | `shell` | `mcp` | `both` |
|---|---:|---:|---:|
| final file type-checks, statement kept | 14 | 14 | 14 |
| solved, as run | 4 | 14 | 7 |
| solved, as archived (re-judged) | 8 | 14 | 8 |
| isolation gate, as archived | 5 | 0 | 6 |
| preservation gate | 1 | 0 | 0 |
| turns | 174 | 143 | 162 |
| tool calls | 160 | 129 | 148 |
| USD (list) | 6.41 | 7.82 | 6.62 |

+  **The archive holds the re-judged verdicts**.  The runs were judged as run
   by the audit of commit `d50dcb4`, archived so (commit `7fe76c8`), and
   re-judged under the audit of `0f04050`, which reads `$?` and a variable
   the call itself binds to a literal path (`G=<library>/src/...; sed ...
   $G/...`), both of which the earlier audit refused though neither can
   name a path outside the roots.  Five rows moved, each from the isolation
   gate to solved; nothing else moved but the re-judge's own fields, and no
   verdict of an earlier archived arm moves under the new audit.
+  **Every remaining isolation finding is the subject leaving the
   protocol**: a `find /` or a read at the repository root, looking for
   agda-algebras' sources, which the prompt says are on disk without saying
   where (nine rows across the two arms); a `cd` to the repository root and
   a recursive grep there, which listed the row's own gold by path (row 17,
   `shell`); or a program the audit does not model (`perl -i` editing the
   work file, `git diff`, `time agda`).  No subject saw a gold's text: no
   tool answer in the 48 transcripts shows a line of its row's gold proof
   that the subject had not written itself.
+  **The preservation failure** (row 6, `shell`) added `_,_` to an import
   line's `using` list rather than adding an import line, which the
   protocol refuses, as on `stdlib-nat-mul-comm` above.
+  **Which tools**.  `mcp`: `definition_of` 14 times, each followed by a
   `Read` of the file it named (49 reads), every verdict from `check_file`,
   and `fill_hole` 5, `search_by_name` and `exports_of` 7 each, `type_of`
   5, `normalize` 3, `get_goal` 2; no `search_by_type` or
   `search_in_scope`.  Every final file passed the first `check_file` after
   its subject's edits.  `both`: the shell for the library (68 of 86 Bash
   calls read library sources), `check_file` for 10 of the 14 final
   verdicts and `agda` by hand for 4, `fill_hole` 9, `type_of` once, and no
   other knowledge tool.

What the numbers mean is the guide's § 4.5
([`docs/reading-the-results.md`](../../docs/reading-the-results.md)); the
per-row account, what each subject tried and which tools it used, is on
[#189].

## The header-free arms (2026-09-29, [#219])

The four 55-row arms behind every agent figure the documents and the site
quote, run again with the fixture headers stripped of their hints (see the
sentence above the run table): Sonnet 5 in the `mcp`, `shell`, and `both`
arms, and Opus 5 in the `mcp` arm.  One arm at a time, parallelism 3, the
caps of every 55-row arm (30 turns, 900 s, USD 3.00), client 2.1.282, from
one frozen copy of the server and the extractor and one snapshot of the
driver's classes; each arm after a two-row cost pair whose isolation audit
came back clean; the 55 rows named with `--ids`, since the index now holds
81.  Zero anomalies; USD 18.61 for the four.  `gold-leak.py`, which
now also reports any call or answer naming the index or a tier README
(where the headers' hints went), finds nothing in any of them.

What each replaces, and how comparable the two are, is as follows:

+  **`suite219-sonnet5-mcp-1`** replaces `agent-sonnet5-1` and
   `arm162-mcp-1`.  Its server, prompts, client, and caps are those of the
   two [#191] seeds (`arm-surface-mcp-1`, `-2`), so that comparison is the
   clean one: the headers are the one variable, besides the read roots'
   gaining Agda's primitive modules (PR [#200]).
+  **`suite219-sonnet5-shell-1` and `suite219-sonnet5-both-1`** replace
   `arm162-shell-1` and `arm162-both-1`.  Their prompts now name each
   library's source directory (PR [#200]), and the `both` arm's server has
   the lean answers and the trimmed surface, so each differs from the run it
   replaces in more than the headers.
+  **`suite219-opus5-mcp-1`** replaces `agent-opus5-1`, whose protocol
   predates everything [#162], [#184], and [#191] changed.

| | `shell` | `mcp` | `both` | Opus `mcp` |
|---|---:|---:|---:|---:|
| solved | 47 | 44 | 48 | 55 |
| restated | 4 | 9 | 5 | 0 |
| lost to a gate | 4 | 2 | 2 | 0 |
| solved, the 34 rows with no original | 33 | 33 | 32 | 34 |
| agda-algebras solved and restated (of 21) | 14, 4 | 11, 9 | 16, 5 | 21, 0 |
| of those solves, original in view (the judge) | 12 | 4 | 11 | 4 |
| haystack rows solved with no query before the final check | not read | 3 | not read | 1 |
| haystack needle named before any search (of 12) | 6 | 7 | 6 | 10 |
| turns | 345 | 347 | 353 | 323 |
| tool calls | 290 | 292 | 298 | 268 |
| USD | 3.42 | 3.99 | 4.13 | 7.07 |
| output tokens | 92,135 | 87,335 | 81,546 | 74,363 |

+  **Every gated file type-checks with its statement kept**.  The `shell`
   arm's four are two subjects that ran `find /` although the prompt names
   the directories (`algebras-inverses-image-f-f`,
   `algebras-inverses-range-to-image`), one `xargs` over a path inside the
   roots, which the audit does not model (`algebras-kernels-ker-con`, whose
   file also cites `kercon`), and one edited `using` list
   (`haystack-nat-plus-zero-diag`).  The `mcp` arm's two are edited `using`
   lists (`stdlib-nat-mul-comm`, as in `agent-sonnet5-1`, and
   `algebras-injective-comp-injective`, which appends the original it then
   cites), and so are the `both` arm's (`stdlib-nat-mul-distrib-r`,
   `haystack-list-map-append-diag`).  So the files earned 50, 45, and 50
   solves.  The Opus arm has no gate row.
+  **The `both` arm keeps its shape**: all 55 verdicts from `check_file`,
   `agda` on the shell never, Bash 84 calls (83 library reads and one grep
   of the row's corpus, as in the `shell` arm), and the knowledge tools
   beside the shell
   `definition_of` 0, `search_by_name` 4, `exports_of` 4, against 11, 21,
   and 23 in the `mcp` arm.
+  **What moved against the runs these replace** (the haystack tier's route,
   about three agda-algebras rows per Sonnet arm from solved to restated) and
   what a difference can mean with one seed a side are the guide's § 4.6
   ([`docs/reading-the-results.md`](../../docs/reading-the-results.md)).

## The composition tier's arms, and the hard tier's without hints (2026-09-29, [#160], [#219])

Nine arms from one detached driver, one seed each, at the hard tier's caps
(60 turns, 1,800 s, USD 6.00), parallelism 2, client 2.1.282, from one frozen
copy of the server and the extractor (built from `main` at `e9c1ee5`, whose
server source differs from the hard tier's `.bin-189` only by a comment) and
one snapshot of the driver's classes: Opus 5 and Sonnet 5 in the `shell`,
`mcp`, and `both` arms on the twelve composition rows
(`agda-algebras-composition-v0/`, stratum `agda-algebras/composition`), and
Opus 5 in the three arms on the fourteen hard rows again, header-free.  Each
model and arm ran a two-row cost pair first, on rows 5 and 1 of the
composition tier (`comp-lattice-below-join-bound`,
`comp-variety-subalgebra-of-model`); the hard-tier arms share the Opus pairs,
and [#189]'s `cost-hard-*-1` give the hard tier's cost per row.  Zero
anomalies; USD 47.28 for the nine arms and six pairs, and the account's
seven-day window went from 0.32 to 0.39.  `gold-leak.py`, which since this
run also flags an answer by its content (an index record, or a README line
that the obligation does not itself contain), finds no gold proof line and
no README line in any of them.

| | Opus `shell` | Opus `mcp` | Opus `both` | Sonnet `shell` | Sonnet `mcp` | Sonnet `both` |
|---|---:|---:|---:|---:|---:|---:|
| composition: final file checks, statement kept | 12 | 12 | 12 | 12 | 12 | 12 |
| composition: solved | 10 | 12 | 10 | 6 | 3 | 5 |
| composition: preservation, isolation | 0, 2 | 0, 0 | 0, 2 | 5, 1 | 9, 0 | 5, 2 |
| composition: USD | 4.14 | 4.05 | 4.87 | 2.60 | 3.55 | 3.39 |
| hard, header-free: final file checks, statement kept | 14 | 14 | 14 | | | |
| hard, header-free: solved | 10 | 14 | 10 | | | |
| hard, header-free: USD | 6.31 | 7.71 | 6.56 | | | |

+  **Every final file type-checks with its statement kept**, 72 of 72 on
   the composition tier and 42 of 42 on the hard tier.  The solved counts
   are lowered by the protocol only.
+  **The preservation rows are all one edit**.  Each of the 19 Sonnet rows
   (and the three in its cost pairs) differs from its obligation only in
   `using` lists: the fixture imports every needle's module through a
   `using` list of decoys, and Sonnet appended the needle there, which the
   prompt forbids; Opus added an import line on every row.
+  **The isolation rows are of two kinds**.  The subject left its roots on
   four composition rows and five hard rows: `find /` for agda-algebras'
   modules although the prompt names their directory, a `cd` to the
   repository root, a relative path that climbs out of the worktree, and a
   `find` at the repository root (on `comp-group-normal-of-smaller-congruence`,
   `both`, it listed three gold directories' `.agda-lib` files and no
   proof).  The other six are the audit's limits: `perl -pi` and Python
   editing or reading the subject's own file, `xargs grep` inside
   agda-algebras' sources, and a grep pattern whose Markdown backticks,
   inside double quotes, read as a command substitution.
+  **The hard tier's `mcp` re-run is the clean comparison with the hinted
   one**: the same prompts, tools, caps, flags, client, and corpora, and
   only the index and one read root (Agda's primitive modules) differ.  It
   solves 14 of 14 again, in 139 turns against 143.

What the numbers mean is the guide's § 4.5 and § 4.7
([`docs/reading-the-results.md`](../../docs/reading-the-results.md)); the
per-row accounts are on [#160] (the composition tier: each row's route per
arm and where each needle came from) and [#219] (the hard tier, against the
hinted runs).

## The server-answer arms (2026-10-03, [#201], [#185])

The header-free `mcp` arms of [#219], run again with two changes to the
server (PRs [#228] and [#229], built together from the second's branch):
`fill_hole` and `get_goal` reach the hole of a one-hole file from any
position on its line, or from no address, and say how in `addressed`
([#201]); and `definition_of` quotes each definition's source beside its
site ([#185]).  Everything else is the protocol of `hard219-opus5-mcp-1` and
`suite219-sonnet5-mcp-1`, byte for byte: the index (81 rows), both corpora,
the prompts, the caps, the read roots (Agda's primitive modules included,
since PR [#200]), the client (2.1.282), and the judge's extractor (the same
frozen binary, digest `85beae1f`).  Against the older baselines below
(`hard-opus5-mcp-1`, `arm-surface-mcp-1` and `-2`) the header hints, the
index, and the primitive read roots differ as well.  Zero anomalies.  The
first attempt at `cost-answers-opus5-mcp-1` met a full five-hour usage
window (one subject refused at USD 0.27, outside the report's totals); the
run was resumed after the reset with the same protocol.

| | hard, Opus 5: `hard-opus5` | `hard219-opus5` | **`hard-answers`** | 55 rows, Sonnet 5: `arm-surface` 1 / 2 | `suite219` | **`suite-answers`** |
|---|---:|---:|---:|---:|---:|---:|
| solved | 14 | 14 | 14 | 48 / 45 | 44 | 47 |
| restated | 0 | 0 | 0 | 7 / 8 | 9 | 6 |
| turns | 143 | 139 | 127 | 345 / 349 | 347 | 332 |
| tool calls | 129 | 125 | 113 | 290 / 294 | 292 | 277 |
| USD | 7.82 | 7.71 | 6.34 | 3.83 / 3.74 | 3.99 | 3.56 |
| cached tokens read per turn | 23,291 | 24,406 | 20,053 | 15,503 / 14,293 | 15,491 | 14,968 |
| `definition_of` calls | 14 | 18 | 22 | 16 / 12 | 11 | 47 |
| `Read` of a file a `definition_of` answer had named | 16 | 19 | 11 | 11 / 8 | 8 | 8 |
| every `Read` outside the work file | 35 | 31 | 23 | 13 / 11 | 11 | 9 |
| `fill_hole` and `get_goal` refused for the address | 2 | 3 | 0 | 5 / 7 | 3 | 0 |
| addresses the one-hole rule reached | | | 2 | | | 8 |

+  **The refusals are gone, and the turns they cost with them**.  Every
   address the new arms sent reached its hole: 10 of them by the one-hole
   rule (7 `fill_hole`, 3 `get_goal`), each of which the old server would
   have refused, against 3 refusals in each header-free baseline.
+  **Sonnet adopted `definition_of`**: 47 calls in 25 of the 55 sessions,
   against 11 calls in 8 sessions (and 16 and 12 in the two older seeds),
   at 1,100 characters an answer.  It took them from the other knowledge
   tools rather than adding them: `exports_of` 8 calls against 23,
   `type_of` 7 against 23, `search_by_name` 14 against 21, so the knowledge
   calls overall stayed level (81 against 85).  The reads it made of a file
   an answer had named did not grow with the calls (8 and 8).
+  **Opus read less**.  It called `definition_of` a little more (22 against
   18 and 14), followed fewer of the answers with a `Read` of the named file
   (11 against 19 and 16), and read the library less overall (23 against 31
   and 35).  Every quote came back whole (28 of 28), and the reads that
   remain are of the module around a definition, 50 to 200 lines at a time
   and twice the whole file: the neighborhood, not the definition.  Its arm
   cost 18 % less than its header-free baseline, USD 1.37, of which 0.78 is
   cache writes (what the tools returned entering the context, 319 thousand
   characters against 440), 0.43 cache reads, and 0.16 output
   (`cost-split.py`).
+  **The restated rows fell by three, and the instrument is part of why**.
   Four agda-algebras rows moved from restated to solved, each with two or
   three `definition_of` calls in the new arm.  On one
   (`algebras-homs-mon-to-intohom`) the quote of the original lemma came
   back and the subject wrote its proof out, which the judge counts as
   solved with the original in view; on another the original arrived by a
   `Read`; on two nothing showed it.  Read the 47 and 6 beside the seed
   spread of the older pair (48 and 45, 7 and 8): one seed each, the solve
   counts are within it, the tool mix is not.

## The search-surface arm (2026-10-03, [#202], [#203])

One Sonnet 5 `mcp` arm on the 55 rows of the header-free arms, with a server
that carries both changes: `search_by_type` matching a type as a statement
writes it, with `patterns` and `qualified` ([#202], PR [#231]), and
`search_in_scope`'s question asked through `search_by_name`'s `inScopeAt`,
with `search_in_scope` itself off the default surface ([#203], PR [#232]).
The server was built from `main` with the two branches merged locally (at
`a18002c2` and `b7ae7730`), which the suite passes, 524 of 524; it predates
[#202]'s later commit that gives builtins the standard library's names, which
this arm's one `search_by_type` call is what found.  After a two-row cost pair
with a clean isolation audit, at parallelism 3, the caps of every 55-row arm,
and client 2.1.282.

Against `suite219-sonnet5-mcp-1` the server is the only variable: the
prompts (`5dae33ff`, `6ea5a0b3`), the index (`62092c1d`), the corpora, the
judge's extractor (`004b79b6`), the caps, the client, and the read roots are
that run's, and nothing else in the server or the harness changed on `main`
between the two.  Against the two [#191] seeds (`arm-surface-mcp-1`, `-2`)
the fixture headers differ as well: those ran with the hints [#219] removed,
on the index `ace10e29`.

| | `arm-surface-mcp-1` | `arm-surface-mcp-2` | `suite219-sonnet5-mcp-1` | `arm202-sonnet5-mcp-1` |
|---|---:|---:|---:|---:|
| header hints | in view | in view | none | none |
| tools presented | 14 | 14 | 14 | 13 |
| `tools/list` characters | 24,094 | 24,094 | 24,094 | 23,468 |
| first-turn context (tokens, median) | 13,037 | 13,037 | 13,124 | 12,835 |
| cached tokens per turn | 15,503 | 14,293 | 15,491 | 14,433 |
| solved / restated | 48 / 7 | 45 / 8 | 44 / 9 | 43 / 9 |
| turns / tool calls | 345 / 290 | 349 / 294 | 347 / 292 | 317 / 262 |
| USD | 3.83 | 3.74 | 3.99 | 3.54 |
| `search_by_type`: sessions / calls | 2 / 3 | 2 / 2 | 2 / 2 | 1 / 1 |
| `search_by_name`: sessions / calls | 15 / 23 | 13 / 20 | 17 / 21 | 8 / 10 |
| of which with `inScopeAt` | not offered | not offered | not offered | 2 / 2 |
| `search_in_scope`: calls | 0 | 0 | 0 | not presented |

+  **`search_by_type` is still not reached for**: one session of 55 called
   it, where two had in each of the three runs before.  That one call wrote
   a statement as the standard library writes it, `m + n ∸ o ≡ m + (n ∸ o)`,
   on `haystack-nat-plus-monus-assoc`, and found nothing, because the corpus
   prints `∸` by its builtin name (`Agda.Builtin.Nat.-`); the subject then
   found `+-∸-assoc` by name and solved the row.  PR [#231]'s later commit
   renders the standard library's names for builtins, and the same query
   now finds exactly that lemma.  The matching works on the query a model
   wrote; how often a model writes one is unchanged by it.
+  **`inScopeAt` was used where `search_in_scope` was not**: two of the ten
   `search_by_name` calls carried it (`∷-injective` on
   `haystack-list-cons-injective-head`, `*-mono-≤` on
   `haystack-nat-mul-mono-sq`), against no call of `search_in_scope` in the
   baseline and one in the 681 archived sessions it was offered in.
+  **The surface is smaller and the arm cheaper, within one seed's noise**:
   289 fewer tokens in the first turn's context, about a thousand fewer
   cached tokens a turn, 30 fewer turns, and USD 0.45 less than the
   baseline.  `search_by_name` was called half as often (10 against 21),
   which one seed cannot separate from chance.
+  **The verdicts are the baseline's, within a seed**: 43 solved and 9
   restated against 44 and 9; 12 of 12 haystack rows and 11 of 21
   agda-algebras rows solved, as in the baseline, though one row moved each
   way there (`algebras-kernels-ker-in-con` now solved,
   `algebras-inverses-inv-inverse-l` now restated); and the one row fewer
   is a third preservation gate (`stdlib-nat-plus-comm`, an edited `using`
   list, beside the two the baseline also had).

## The Agda 2.9.0 arms, and the current models (2026-10-13, [#236])

From 2026-10-13 every arm runs on Agda 2.9.0 ([#234]): the models read
Agda's error text, and 2.9.0 rewords it.  Seven arms and three cost pairs ran
one at a time from one detached driver script, launched twice (the three
pairs, then the seven arms), one seed each, client 2.1.282, from one frozen
copy of the server and the extractor built from `main` at `a5c4d8c6` and one
snapshot of the driver's classes.  Opus 5 ran on the 55 library rows, as the
baseline the library-tier arms are read against; Sonnet 5.5
(`claude-sonnet-5-5`) and Opus 5.5 (`claude-opus-5-5`) ran on the library,
composition, and hard tiers.  Each tier's rows are those of the archived run
it is compared with (`--ids`, from that run's `report.json`), at that run's
caps: 30 turns, 900 s, and USD 3.00 at parallelism 3 for the library tier,
and 60 turns, 1,800 s, and USD 6.00 at parallelism 2 for the other two.  Each
model's arms followed a two-row cost pair (`stdlib-nat-plus-comm`,
`algebras-homs-mon-to-hom`) whose isolation audit came back clean.  Zero
anomalies; USD 21.16 at list for the seven arms and the three pairs.
`gold-leak.py` finds nothing in any of them.

What differs from the archived runs is as follows:

+  **The toolchain**.  Agda 2.9.0 and the standard library 2.3 patched for
   it.  The system prompt names the version, its only change (digest
   `51a4f8f9` against `5dae33ff`).  The read roots are the 2.9.0 builds':
   agda-algebras' sources byte-identical, the standard library's changed by
   the patch (12 files changed, one module added), and Agda 2.9.0's own
   primitive modules.
+  **The server**.  Besides reading 2.9.0's diagnostics ([#246]), it
   carries five changes a subject can meet that reached `main` after the
   header-free arms' frozen servers (binary digests `800324ca` for the
   55-row arms and `a3e52cc9`, built from `main` at `e9c1ee5`, for the
   composition and hard arms): `fill_hole` and
   `get_goal` reach the only hole from any position on its line ([#228]);
   `definition_of` quotes the source ([#229]); `search_by_type` matches a
   statement as written ([#231]); `search_in_scope` is asked through
   `search_by_name`, so 13 tools are presented where the header-free arms
   had 14 ([#232]); and `get_goal` and `type_of` answer in `Simplified`
   ([#257]).  Two more server changes are off the default surface (the
   opt-in `auto` tool of PR [#230] and the launcher's `--cwd` handling of
   PR [#245]).
+  **Unchanged**: the user prompt (`6ea5a0b3`), the index (`62092c1d`),
   both corpora (`14e0d47e`, `af864432`), the caps, the client's flags, and
   the client.

So the Opus 5 arm measures the toolchain and the server together, and every
comparison of a new model with Sonnet 5 or with Opus 5's composition and
hard runs varies the model, the toolchain, and the server at once.  No arm
measures the toolchain alone, which would need the old server on the new
Agda.

**The judge under 2.9.0**.  Copies of the five baselines this section
compares with were re-judged under 2.9.0, each with its own ids and arm, and
archived as `rejudge290-<run-id>` (no model call).  Across their 148 rows no
verdict moves: solved, restated, gate, both exit codes, the statement's
equality, and the original-in-view column are the archive's on every row.
The one difference is a deprecation warning, `FixityDeclarationForNonOperator`,
which `check_file` now reports for every file that imports agda-algebras'
`Overture.Basic` (72 of the 148): Agda 2.9.0 deprecates the fixity
declaration of the closed operator `∣_∣` (`src/Overture/Basic.lagda.md`,
line 96), and on the 68 of those files that also import `Overture.Relations`
the same warning comes a second time, for `[_]`
(`src/Overture/Relations.lagda.md`, line 70).  A re-judged copy keeps its
run's own `config` and prompts, which name 2.8.0; the judge's 2.9.0 shows
only in those warnings, in the `agdaTail` and `checkCodes` of the 72 rows
that carry them.

*Opus 5 on the 55 library rows, before and after the move.*

| | `suite219-opus5-mcp-1`, Agda 2.8.0 | `suite236-opus5-mcp-1`, Agda 2.9.0 |
|---|---:|---:|
| solved / restated | 55 / 0 | 54 / 0 |
| final file checks, statement kept | 55 | 55 |
| lost to a gate | 0 | 1 (isolation, one refused call) |
| turns / tool calls | 323 / 268 | 309 / 254 |
| USD / output tokens | 7.07 / 74,363 | 6.91 / 70,079 |
| `check_file` answer on an agda-algebras row, mean characters | 423 | 1,122 |
| of those 21 answers, with the fixity warning | 0 | 20 |
| answers carrying Agda's error text | 2 | 1 |
| `definition_of` / `get_goal` / `type_of` / `fill_hole` calls | 10 / 14 / 17 / 42 | 24 / 4 / 7 / 35 |
| `fill_hole` refused for its address | 6 | 0 |

"Agda's error text" counts a `check_file` that failed and any server
answer carrying one of Agda's `error: [Code]` lines.

+  **The re-judge changed no verdict, and the re-run differs from its
   baseline as two seeds of one protocol did**.  Its one changed verdict
   is `haystack-nat-plus-zero-diag`, whose file checks with its statement
   kept and lost the isolation gate to a refused call (below), so the files
   earned 55.  41 of the 55 final files are byte-identical and 33 rows took
   the same number of turns; the two hinted Opus 5 seeds of 2026-09-15
   (`agent-opus5-1`, `-2`) had 44 and 31, and differed by 13 turns where
   these differ by 14.
+  **Where 2.9.0 reached the subject**.  In the warning, which every
   agda-algebras `check_file` answer but one now carries; three subjects
   mention it in their closing words, as a pre-existing library warning, and
   none acts on it (no tool input names it).  And hardly at all in error text,
   which reached Opus 5 in one answer in the 55 rows (a `fill_hole` answer
   carrying Agda's `NotInScope`), against two before.  So this arm cannot show
   what the rewording does to a model that errs.  The arms that meet error text
   often are Sonnet's (Sonnet 5 met it in 12 answers on these 55 rows and in
   25 on the twelve composition rows), and Sonnet 5 was not re-run.
+  **The tool mix moved more than the count did**: `definition_of` 24
   calls against 10 (Sonnet's rose the same way when the answer gained the
   quote, [#229]), `get_goal` 4 against 14, `type_of` 7 against 17, and no
   `fill_hole` refused for its address against 6 ([#228]).  The server's
   changes act on those tools, but this arm cannot separate them from the
   toolchain.  Of the 14 turns saved, 11 are on the agda-algebras rows (155
   against 166) and 3 on the haystack rows (63 against 66).

*The current models against the archived ones, per tier.*

| | Sonnet 5 | Sonnet 5.5 | Opus 5 | Opus 5.5 |
|---|---:|---:|---:|---:|
| library (55): solved / restated | 44 / 9 | 51 / 4 | 54 / 0 | 37 / 1 |
| library: lost to a gate | 2 (preservation) | 0 | 1 (isolation) | 17 (isolation) |
| library: solved / restated, refused calls not counted ([#266]) | 44 / 9 | 51 / 4 | 55 / 0 | 51 / 4 |
| library: turns / USD | 347 / 3.99 | 281 / 2.09 | 309 / 6.91 | 270 / 3.78 |
| composition (12): solved | 3 | 11 | 12 | 4 |
| composition: lost to a gate | 9 (preservation) | 1 (preservation) | 0 | 8 (isolation) |
| composition: solved, refused calls not counted | 3 | 11 | 12 | 12 |
| composition: turns / USD | 206 / 3.55 | 119 / 1.26 | 128 / 4.05 | 109 / 2.07 |
| hard (14): solved | not run | 14 | 14 | 10 |
| hard: lost to a gate | | 0 | 0 | 4 (isolation) |
| hard: solved, refused calls not counted | | 14 | 14 | 14 |
| hard: turns / USD | | 145 / 1.81 | 139 / 7.71 | 118 / 2.51 |

Runs: Sonnet 5 `suite219-sonnet5-mcp-1` and `comp-sonnet5-mcp-1` (Agda
2.8.0, the older servers; Sonnet 5 never ran the hard tier); Opus 5
`suite236-opus5-mcp-1` (2.9.0), `comp-opus5-mcp-1` and
`hard219-opus5-mcp-1` (2.8.0, the older server); Sonnet 5.5 and Opus 5.5
the `*236-*` runs.  These are the header-free baselines the re-judge
covers.  Two later 2.8.0 arms ran on a server nearer this one's, with
[#228] and [#229]: `suite-answers-sonnet5-mcp-1` (47 solved, 6 restated,
332 turns, USD 3.56) and `hard-answers-opus5-mcp-1` (14 solved, 127 turns,
USD 6.34).  USD is list price; for Sonnet 5.5 it is priced from `modelUsage`
(below).

+  **Every final file checks, in every arm**: all 81 of each new model's,
   with their statements kept.  What separates the counts is restatement
   and the gates, never a file that failed to check.
+  **Sonnet 5.5 narrows Sonnet 5's gap on the library tier, closes all but
   one row of it on the composition tier, and proves all fourteen hard
   rows**.  On the
   library tier seven rows move from Sonnet 5's other columns to solved and
   none moves back: the two edited `using` lists and five restatements.
   Its four restatements are rows Sonnet 5 restated too.  On the
   composition tier it solves 11 of 12 against 3, with one preservation
   gate against nine, and that one is the same habit: one of the original
   `using` lists extended (here an import line's, `Level` to
   `Level ; lift`) rather than a line added.  It took 19 % fewer turns on
   the library tier and 42 % fewer on the composition tier, at 48 % and
   64 % less cost.
+  **On the composition tier Sonnet 5.5 took Opus 5's route, not Sonnet
   5's**: 5 rows on the gold's whole route and 20 of the 33 needles named
   in its final files, where Opus 5 had 5 and 20 and Sonnet 5 had 11 and
   32 (`needle-source.py`), and row by row it named as many of each row's
   needles as Opus 5 did, on all twelve.  Like Opus 5 it unfolded the
   relations the needles are about where Sonnet 5 cited them, and on rows
   8 and 10 it wrote Opus 5's terms up to names: the pair `_≅_.from A≅B ,
   _≅_.fromIsSurjective A≅B` (Opus 5 opened `_≅_` and wrote `from A≅B ,
   fromIsSurjective A≅B`) in place of the gold's `HomImage-≅'`, and
   `λ x∈θ → φ≤N (θ⊆φ x∈θ)` (Opus 5's `λ p → φ≤N (θ⊆φ p)`) in place of
   `≤ⁿ-trans`.  Opus 5.5 took the same route but on row 7: 6 rows on the
   whole route, 22 needles.
+  **Opus 5.5 loses 29 rows to a slip the audit misreads**.  In 29 of its 81
   sessions it called a server tool by its bare name (`fill_hole`,
   `definition_of`, `search_by_name`, ...; 34 calls) without the `mcp__agda__`
   prefix.  The client refused each call (`No such tool available`), and every
   session went on under the full names, five of them after two refused calls
   (two of the five sent both in one turn); the audit counts any name outside
   the presented set as foreign use.  No such row has a path violation, and
   read without those calls the arms earned 51 solved and 4 restated, 12 of
   12, and 14 of 14.  Opus 5 made the slip once in 55 sessions (its one gated
   row above); no Sonnet arm and no earlier arm ever did.  The fix to the
   audit, and the re-judge that follows it, are [#266]; until then both
   numbers are quoted.
+  **Opus 5.5 restates where Opus 5 wrote the proof out**: four rows
   (`algebras-homs-id-hom`, `algebras-homs-mon-to-hom`,
   `algebras-subalgebras-sub-reflexive`,
   `algebras-subalgebras-sub-trans-iso`), with the refused calls not counted
   (one as measured, three behind the isolation gate), against none; three of
   them are rows Sonnet 5.5 restates too.  The client opens an Opus 5.5 session
   at `medium` effort, one level below the `high` it sends Opus 5 and both
   Sonnets (the first request of each, read off a loopback capture, client
   2.1.282, no settings); it also reports per-turn effort active for both 5.5
   models and not for Opus 5, and no record shows a later turn's level.  So
   here the model and the effort are one variable.
+  **Opus 5.5 costs about half what Opus 5 does**: at list, 45 %, 49 %, and
   68 % less on the three tiers, in 13 %, 15 %, and 15 % fewer turns and,
   on the library tier, with 27 % fewer output tokens.  The rest is its
   price: $4 and $20 per million input and output tokens and $0.20 for a
   cache read, against $5, $25, and $0.50.  The composition and hard
   figures are against Opus 5's 2.8.0 runs.
+  **The client's cost for Sonnet 5.5 is not a list price**.  Client 2.1.282
   has no price for `claude-sonnet-5-5` (`costBasis` `unknown` in every result
   record) and charges it at another model's rates: on 79 of its 83 subjects
   (the cost pair's two included) Fable 5.1's ($10 and $50 per million input
   and output tokens, $0.25 for a cache read, $20 for a one-hour cache write),
   and on four (two composition rows, two hard rows) Opus 5.5's.  The cost
   pair's stdlib row (6 input, 958 output, 38,683 cache-read, and 3,913
   cache-write tokens) is the client's USD 0.13589 to the cent at Fable 5.1's
   rates.  Every Sonnet 5.5 figure here is priced from each subject's
   `modelUsage` at the published list ($2 and $10, $0.10, and $4); the same
   pricing reproduces the client's own figure to the cent on every subject of
   the list-priced arms here and of the two `suite219` arms.  The reports'
   `costUsd` for the three arms is 9.69, 5.40, and 7.65.  The budget cap is the
   client's figure too, so for Sonnet 5.5 it stood at about a fifth of its
   list value (half on the four subjects priced as Opus 5.5); no subject came
   near it (the highest, 1.21 against 6.00), and every subject of the three
   arms ended `completed`.

What the numbers mean beside the other instruments is the guide's § 4.8
([`docs/reading-the-results.md`](../../docs/reading-the-results.md)).

## The Codex arms: GPT-6.1 Sol and GPT-6 Astra (2026-10-14, [#239])

OpenAI's models ran through the Codex subject of the protocol section "A
Codex subject" (Codex CLI 0.162.1, the `mcp` arm, one subject at a time), on
the ChatGPT Plus login, one seed each: GPT-6.1 Sol (`gpt-6.1-sol`) on the
library, composition, and hard tiers, and GPT-6 Astra (`gpt-6-astra`) on the
hard tier, both at the pinned catalog's default effort, `low`, and Sol once
more on the hard tier at `high`.  Each model's arms followed a two-row cost
pair (`cost239-sol-mcp-2`, `cost239-astra-mcp-2`).  The arms ran one at a
time from one detached driver, from the frozen server and extractor of the
[#236] arms themselves (digests `608ede24` and `e8858863`), so each row
differs from those baselines in the harness, the model, and the effort, and
in nothing the judge reads: the user prompt (`6ea5a0b3`), the index
(`62092c1d`), both corpora (`14e0d47e`, `af864432`), and each tier's caps
are theirs.  The system prompt (`a2399dd4`) differs from theirs
(`51a4f8f9`) in the one sentence that names the tools.  Each run was
re-judged under the harness's final code with no model call, and no verdict,
gate, turn count, tool count, or priced figure moved.  Zero anomalies;
`gold-leak.py` finds nothing, and no value of the login is in any run
directory.  USD 11.57 at OpenAI's list prices for the five arms and the two
pairs.

*Per tier, beside the [#236] baselines.*

| | Sol (Codex, `low`) | Astra (Codex, `low`) | Sol (Codex, `high`) | Sonnet 5.5 | Opus 5 |
|---|---:|---:|---:|---:|---:|
| library (55): solved / restated | 54 / 1 | not run | not run | 51 / 4 | 54 / 0 |
| library: turns / tool calls / USD | 266 / 209 / 2.09 | | | 281 / 226 / 2.09 | 309 / 254 / 6.91 |
| library: original in view (of agda-algebras solves) | 6 of 20 | | | 3 of 17 | 5 of 21 |
| composition (12): solved | 12 | not run | not run | 11 | 12 |
| composition: turns / tool calls / USD | 95 / 74 / 0.89 | | | 119 / 107 / 1.26 | 128 / 116 / 4.05 |
| hard (14): solved | 14 | 14 | 14 | 14 | 14 |
| hard: turns / tool calls / USD | 116 / 94 / 1.09 | 117 / 100 / 5.76 | 146 / 113 / 1.26 | 145 / 131 / 1.81 | 139 / 125 / 7.71 |
| five-hour window used, in points | 32 | 43 | 11 | | |

Runs: `suite239-sol-mcp-1`, `comp239-sol-mcp-1`, `hard239-sol-mcp-1`,
`hard239-astra-mcp-1`, and `hard239-sol-high-mcp-1`; the baselines are
those of the [#236] section's table (Opus 5's composition and hard runs are
Agda 2.8.0's, on an older server).  USD is list price: OpenAI's for the
Codex arms, priced from the tokens Codex reported, since a ChatGPT login is
billed against the plan's windows, not per token; the window took the five
arms from 3 % to 89 % of one five-hour window and the weekly one from 1 %
to 15 %.

+  **Through Codex, Sol solves 80 of the 81 rows at its default effort and
   restates the 81st**, `algebras-subalgebras-sub-trans-iso`
   (`Setoid.Subalgebras.Properties.≤-trans-≅`), a row Sonnet 5.5 and
   Sonnet 5 restate too, and Opus 5.5 with its refused calls not counted.
   Every final file of every arm checks with its statement kept, no row lost
   a gate, and every session ended on its own: no cap was reached (21 turns
   and 155 s at most, against 60 and 1,800 on the hard tier).
+  **It takes the fewest turns and calls of any arm on every tier**: 266,
   95, and 116 turns against 270 to 347, 109 to 206, and 118 to 145 for
   the Claude 5 and 5.5 models.  Its library rows read as write and check:
   about one Read, one Edit, and one `check_file` a row, `type_of` 15 and
   `definition_of` 14 calls, and `fill_hole` twice (Opus 5 called it 35
   times, Sonnet 5.5 13).  On the composition and hard tiers `definition_of`
   is the agda tool it calls most (18 and 22 calls).
+  **Astra matches Sol on the hard tier at five times the price**: 14 of 14
   in 117 turns against 116, USD 5.76 against 1.09, and 43 points of the
   five-hour window against 9.  Its cost pair restated
   `algebras-homs-mon-to-hom`, the row Opus 5.5 restates and both hinted
   Opus 5 seeds did.
+  **`high` effort bought nothing measurable on the hard tier**: the same 14
   rows in 26 % more turns (146 against 116), with 32 % more output tokens,
   15 % more cost, and more reading (36 Reads against 21, 10 `get_goal`
   against 5).  The tier is at every model's ceiling, so this says what the
   effort costs, not what it is worth.
+  **Read a Codex row as Codex CLI with the model**.  Beside the model, the
   comparison with the Claude columns varies the harness (Codex presents
   agda-mcp's descriptions whole, where Claude Code cuts them at 2,048
   characters, [#191]; its base instructions are its own) and the effort
   (`low` here, `high` for the Claude 5 and Sonnet 5.5 sessions, `medium`
   for Opus 5.5's).  The tool counts do map: an agda call is the same tool
   under the same name, Read is the confined read server's, and an Edit is
   one `apply_patch`, however many hunks it has.

What the numbers mean beside the other instruments is the guide's § 4.9
([`docs/reading-the-results.md`](../../docs/reading-the-results.md)).

## Reading a transcript

A transcript is JSON Lines.  The `system`/`init` record lists the tools the
client presented and the server's status; each `assistant` record carries the
model's text and its `tool_use` blocks (name and arguments); each `user`
record carries the matching `tool_result` (the MCP tools' bodies are JSON
inside the text); the `result` record carries the turn count, the wall, the
cost, and the token usage.  `outcome.json` beside it is the harness's reading
of the same file.

## Reproducing a run

From the repository root, inside `nix develop .#backend`, with a logged-in
`claude` on `PATH` and both corpora under `data/corpora/` (the standard
library's is `make corpus-stdlib-nix`; agda-algebras' is the
`agda-algebras-corpus-v0.1` release asset), the following are the commands
that produced the arms above.

```sh
make agent-bench AGENT_BENCH_MODEL=claude-sonnet-5 AGENT_BENCH_PARALLELISM=3 AGENT_BENCH_RUN_ID=agent-sonnet5-1
make agent-bench AGENT_BENCH_MODEL=claude-opus-5   AGENT_BENCH_PARALLELISM=3 AGENT_BENCH_RUN_ID=agent-opus5-1
make agent-bench-archive AGENT_BENCH_RUN_ID=agent-sonnet5-1
```

`AGENT_BENCH_ARM` chooses the instrument, and produced the 2026-09-21 arms; a
run id is one arm, so each needs its own.

```sh
make agent-bench AGENT_BENCH_ARM=shell AGENT_BENCH_MODEL=claude-sonnet-5 AGENT_BENCH_PARALLELISM=3 AGENT_BENCH_RUN_ID=arm162-shell-1
make agent-bench AGENT_BENCH_ARM=mcp   AGENT_BENCH_MODEL=claude-sonnet-5 AGENT_BENCH_PARALLELISM=3 AGENT_BENCH_RUN_ID=arm162-mcp-1
make agent-bench AGENT_BENCH_ARM=both  AGENT_BENCH_MODEL=claude-sonnet-5 AGENT_BENCH_PARALLELISM=3 AGENT_BENCH_RUN_ID=arm162-both-1
```

Since the hard and composition tiers joined the index, it has 81 rows, and
the 55-row arms name their rows rather than taking `--all` (the header-free
arms of 2026-09-29 were run so, from a frozen server, extractor, and class
snapshot, one arm at a time):

```sh
IDS=$(jq -r 'select(.tags | index("stratum:novel") or index("stratum:composition") | not) | .id' \
  data/benchmarks/benchmark-index.jsonl | paste -sd,)
make agent-bench AGENT_BENCH_ARM=mcp AGENT_BENCH_MODEL=claude-sonnet-5 AGENT_BENCH_PARALLELISM=3 \
  AGENT_BENCH_RUN_ID=suite219-sonnet5-mcp-1 "AGENT_BENCH_IDS=--ids $IDS"
```

The arms of [#236] took each tier's rows from the archived run they are
compared with and that run's caps, one arm at a time from a detached driver
over one frozen server, extractor, and snapshot of the driver's classes; as
the Make target would issue one of them:

```sh
IDS=$(jq -r '.outcomes[].benchmarkId' reports/agent-bench/comp-sonnet5-mcp-1/report.json | paste -sd,)
make agent-bench AGENT_BENCH_ARM=mcp AGENT_BENCH_MODEL=claude-sonnet-5-5 AGENT_BENCH_PARALLELISM=2 \
  AGENT_BENCH_MAX_TURNS=60 AGENT_BENCH_WALL_CAP=1800 AGENT_BENCH_MAX_BUDGET_USD=6.00 \
  AGENT_BENCH_RUN_ID=comp236-sonnet55-mcp-1 "AGENT_BENCH_IDS=--ids $IDS"
```

A re-judge does not need `AGENT_BENCH_ARM`: each subject's `subject.json`
names the arm it ran under and the roots it was given, so the audit is the
run's own (verified on a copy of `arm162-shell-1`, re-judged with the flag at
its `mcp` default: 50 solved, 0 restated, four isolation and one preservation
gate, and all 55 rows identical including the `via` columns).  The report
keeps the run's own arm in its `config` too; until [#188] a re-judge stamped
the operator's there, which relabeled a shell arm `mcp` though no row changed.
An archive made before that record existed is the `mcp` arm confined to the
work directory its server config names, which is what those runs were; a copy
of `agent-sonnet5-1` re-judges to 46 solved, 8 restated, 0 anomalies, 327
turns and 272 tool calls, every per-row verdict as archived.

`make agent-bench-rejudge AGENT_BENCH_RUN_ID=<run-id>` judges an archived run
again from its final files and its own archived prompts without a model call
(the server and the extractor are still consulted), so a judge change never
costs a sweep; a copy of an archive re-judges as the original, the isolation
audit taking the work directory from the subject's own server config.  A run id is one protocol: `--resume on` keeps an archived
subject only when the run's `protocol.json` is the current protocol, field
for field, digests included, so a corpus or an index regenerated in place
refuses the run id rather than mixing two environments in one report (the
archived arms predate the record and cannot be resumed).  A re-judge takes
the same `AGENT_BENCH_IDS` as the run it re-judges: a run made over a subset
must be re-judged over that subset, or the rows it never ran are counted
missing.  A model's answers are not deterministic: a
second seed of the frontier arm is recorded above for that reason, and any
new run gets a new run id.

[#154]: https://github.com/formalverification/agda-native-air/issues/154
[#161]: https://github.com/formalverification/agda-native-air/pull/161
[#162]: https://github.com/formalverification/agda-native-air/issues/162
[#184]: https://github.com/formalverification/agda-native-air/issues/184
[#188]: https://github.com/formalverification/agda-native-air/issues/188
[#190]: https://github.com/formalverification/agda-native-air/pull/190
[#160]: https://github.com/formalverification/agda-native-air/issues/160
[#189]: https://github.com/formalverification/agda-native-air/issues/189
[#191]: https://github.com/formalverification/agda-native-air/issues/191
[#193]: https://github.com/formalverification/agda-native-air/pull/193
[#205]: https://github.com/formalverification/agda-native-air/issues/205
[#197]: https://github.com/formalverification/agda-native-air/pull/197
[#219]: https://github.com/formalverification/agda-native-air/issues/219
[#220]: https://github.com/formalverification/agda-native-air/pull/220
[#221]: https://github.com/formalverification/agda-native-air/pull/221
[#200]: https://github.com/formalverification/agda-native-air/pull/200
[#185]: https://github.com/formalverification/agda-native-air/issues/185
[#201]: https://github.com/formalverification/agda-native-air/issues/201
[#228]: https://github.com/formalverification/agda-native-air/pull/228
[#229]: https://github.com/formalverification/agda-native-air/pull/229
[#202]: https://github.com/formalverification/agda-native-air/issues/202
[#203]: https://github.com/formalverification/agda-native-air/issues/203
[#231]: https://github.com/formalverification/agda-native-air/pull/231
[#232]: https://github.com/formalverification/agda-native-air/pull/232
[#236]: https://github.com/formalverification/agda-native-air/issues/236
[#237]: https://github.com/formalverification/agda-native-air/issues/237
[#238]: https://github.com/formalverification/agda-native-air/issues/238
[#239]: https://github.com/formalverification/agda-native-air/issues/239
[#240]: https://github.com/formalverification/agda-native-air/issues/240
[#234]: https://github.com/formalverification/agda-native-air/issues/234
[#246]: https://github.com/formalverification/agda-native-air/pull/246
[#257]: https://github.com/formalverification/agda-native-air/pull/257
[#266]: https://github.com/formalverification/agda-native-air/issues/266
[#230]: https://github.com/formalverification/agda-native-air/pull/230
[#245]: https://github.com/formalverification/agda-native-air/pull/245
