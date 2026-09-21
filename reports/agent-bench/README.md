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

## The protocol, fixed for every run below

+  **Subject**.  One `claude -p` session per obligation (Claude Code 2.1.261),
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
+  **The arms** ([#162]).  `--arm` is the only knob that differs between them,
   and it decides two client values and one file: the built-in tools
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
   every command runs in the directory the file is in.
+  **Read roots**, the same on every arm.  Besides its own directory, a
   subject may read every registered library's directory and source roots and
   the Agda registry directory, whose `libraries` file the judge's command
   names; the file tools reach them through `--add-dir`.  This is why the
   arms are comparable: the archived `mcp` arm refused eleven library-source
   reads for Sonnet and two for Opus as a confinement side effect, and a
   shell arm that can `cat` a module while the server arm cannot would
   confound the comparison.
+  **Caps**.  30 turns, 900 s of wall, USD 3.00 of the client's own list-price
   accounting, per subject; three subjects at a time, so wall clocks are
   indicative only.
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
   own helpers) and the original is the index row's `restates:` tag.  The
   server's interaction lane plays no part in the judge: a printed type is
   not a statement.  The arms were first judged by a textual reading and
   re-judged under these gates to the same verdict on every row; the
   archived reports and per-subject outcomes are the re-judge's.
   `JudgeSpec` and `AgentBenchIntegrationSpec` pin the rules and the live
   gates.
+  **Isolation, verified per subject**.  From each transcript: the server
   connected; the tools presented exactly Read, Edit, and the thirteen, and
   not deferred; no tool used beyond them; and no Read or Edit outside the
   work directory that succeeded (refused attempts are counted separately).
   A subject that never had that instrument (the first two, a tool presented
   beyond the fifteen included, used or not) is an anomaly, not a row, as is
   one whose process ended with no result record at all (a crash; a wall-cap
   kill is a stated cap) and one whose file left the judge without an answer
   it should have (a `check_file` that timed out or gave no usable verdict, a
   disagreement between the two batch verdicts, a file Agda checked that the
   extractor could not read).  An anomalous row is never counted a solve or a
   restatement, whatever its file earned, so the measured columns and the
   anomaly count never describe the same row.  A subject that used a tool
   beyond the fifteen or left the work directory fails the isolation gate.
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

## What a run directory holds

| path | contents |
|---|---|
| `report.json` | the run: `config` (model, caps, every client flag, the prompts' digests, the client version), `corpora` (paths and digests), `totals`, `perTier`, `perStratum`, `perTool`, and one `outcomes[]` entry per obligation (`solved`, `restated`, `gate`, `restatementEvidence`, `addedImports`, `terminal`, `turns`, `toolCalls`, `wallMs`, `costUsd`, `tokens`, `isolation`, `agdaExit`) |
| `results.jsonl` | one `eval-proof-completion.v0` attempt row per `fill_hole` the subject probed |
| `fixtures.jsonl` | one `eval-proof-completion.v0` fixture row per obligation, plus `restated`, `gate`, and `terminal` |
| `prompts/` | the system prompt and the user-prompt template, verbatim |
| `subjects/<id>/transcript.jsonl` | the client's `stream-json` output: every tool call with its result, the model's text, the init and result records |
| `subjects/<id>/final/<Stem>.agda` | the file as the subject left it, which is what was judged |
| `subjects/<id>/outcome.json` | the judge's verdict and the transcript audit for that row |
| `subjects/<id>/subject.json` | the arm the subject ran under and the roots its tools and commands were allowed, which is what a re-judge audits against |
| `subjects/<id>/mcp.json`, `prompt.txt`, `system-prompt.txt`, `run.json` | the subject's server configuration (an arm with the server), its two rendered prompts, and how its process ended |
| `subjects/<id>/stderr.log` | the client's standard error, archived when it is not empty; this is what an anomaly message means by "see stderr.log" |

A subject that ended early has only what it wrote: the archive copies each of
these when it exists, so a run with anomalous rows archives like any other.

The work copies, the staging server's log, and Agda's interface files stay
behind under `data/benchmarks/reports/agent-bench/<run-id>/` (gitignored).

## The runs

| run id | arm | model | date | obligations | solved | restated | anomalies | turns | tool calls | cost (USD, list) | quoted in |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `smoke-haiku-1` | `mcp` | `claude-haiku-4-5-20251001` | 2026-09-15 | 1 | 1 | 0 | 0 | 4 | 3 | 0.04 | the isolation verification on [#154] |
| `cost-sonnet-1` | `mcp` | `claude-sonnet-5` | 2026-09-15 | 2 | 1 | 1 | 0 | 10 | 8 | 0.28 | the cost estimate on [#154] |
| `cost-opus-1` | `mcp` | `claude-opus-5` | 2026-09-15 | 2 | 2 | 0 | 0 | 12 | 10 | 0.47 | the cost estimate on [#154] |
| `agent-sonnet5-1` | `mcp` | `claude-sonnet-5` | 2026-09-15 | 55 | 46 | 8 | 0 | 327 | 272 | 4.62 | ADR 0001 § 9, README, [#154] |
| `agent-opus5-1` | `mcp` | `claude-opus-5` | 2026-09-15 | 55 | 54 | 1 | 0 | 325 | 270 | 9.14 | ADR 0001 § 9, README, [#154] |
| `agent-opus5-2` | `mcp` | `claude-opus-5` (second seed) | 2026-09-15 | 55 | 54 | 1 | 0 | 338 | 283 | 9.46 | ADR 0001 § 9, [#154] |
| `arm162-shell-1` | `shell` | `claude-sonnet-5` | 2026-09-21 | 55 | 50 | 0 | 0 | 308 | 253 | 2.88 | ADR 0001 § 9, ADR 0002 § 12, [#162] |
| `arm162-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-21 | 55 | 47 | 6 | 0 | 342 | 287 | 5.28 | ADR 0001 § 9, ADR 0002 § 12, [#162] |
| `arm162-both-1` | `both` | `claude-sonnet-5` | 2026-09-21 | 55 | 51 | 2 | 0 | 327 | 272 | 4.25 | ADR 0001 § 9, ADR 0002 § 12, [#162] |

Per stratum, solved and restated (first arms), beside the loop's fixed space
and retrieval under exclusion on `main`:

| stratum | n | loop fixed | loop retrieval | Sonnet 5 | Opus 5 |
|---|---|---|---|---|---|
| agda-stdlib | 22 | 6 | 6 | 21 solved | 22 solved |
| agda-stdlib/haystack | 12 | 0 | 6 | 12 solved | 12 solved |
| agda-algebras/using | 11 | 2 | 2 | 9 solved, 2 restated | 11 solved |
| agda-algebras/wholesale | 10 | 0 | 0 | 4 solved, 6 restated | 9 solved, 1 restated |

The two Opus seeds solve the same 54 rows and restate the same one
(`algebras-homs-mon-to-hom`); 44 of their 55 final files are byte-identical,
31 rows took the same number of turns, and the arms differ by 13 turns and 13
tool calls in total, so on this suite the model's run-to-run variance shows in
how it gets there, not in what it solves.

The one Sonnet row that is neither solved nor restated
(`stdlib-nat-mul-comm`) appended `; trans` to an original `using` list rather
than adding an import line, which the preservation gate refuses by the
protocol; its `outcome.json` records that the file type-checks (`agdaExit` 0).

## The attribution arms (2026-09-21, [#162])

The three arms above were run fresh at one protocol version, one arm at a
time, to ask what the server is worth: `shell` gives the subject Bash and the
pinned `agda`, `mcp` gives it the server, `both` gives it both.  Zero
anomalies in all three; USD 12.41 together.

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
is, and a subject that reads the source writes the construction where one that
queries the name cites the name.

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

A re-judge does not need `AGENT_BENCH_ARM`: each subject's `subject.json`
names the arm it ran under and the roots it was given, so the audit is the
run's own (verified on a copy of `arm162-shell-1`, re-judged with the flag at
its `mcp` default: 50 solved, 0 restated, four isolation and one preservation
gate, and all 55 rows identical including the `via` columns).  An archive made
before that record existed is the `mcp` arm confined to the work directory its
server config names, which is what those runs were; a copy of
`agent-sonnet5-1` re-judges to 46 solved, 8 restated, 0 anomalies, 327 turns
and 272 tool calls, every per-row verdict as archived.

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
