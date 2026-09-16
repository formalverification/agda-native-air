<!-- File: reports/agent-bench/README.md -->

# Agent-in-the-loop runs: the archive

This directory holds every run of the agent-in-the-loop evaluation (Issue
[#154], [M1-10]) that a document quotes: a frontier model driving `agda-mcp`
over the benchmark suite, one fresh non-interactive session per obligation,
judged by the gold verifier's own `agda` invocation.  The decision record is
[ADR 0001](../../docs/adr/0001-proof-search-on-agda-mcp.md) § 9; the
explanatory note is [`docs/proof-search/overview.md`](../../docs/proof-search/overview.md);
the harness is `struxdriver.agentbench` in `strux-driver/`, run by
`make agent-bench`.  Each run directory is written by `make agent-bench-archive`
from the harness's own output and never edited by hand.

## The protocol, fixed for every run below

+  **Subject**.  One `claude -p` session per obligation (Claude Code 2.1.261),
   with its working directory a staged copy of the one obligation file and
   nothing else; its tools are the thirteen `agda-mcp` tools (the server
   started through the committed launcher with the row's library corpus:
   the stdlib v0 corpus, digest `14e0d47e`, for `agda-stdlib` rows and the
   agda-algebras v0.1 corpus, digest `af864432`, for the others) plus Read and
   Edit on that file; no shell, no settings, no CLAUDE.md, no skills, no
   memory; the tools presented eagerly with their descriptions; the client
   confined to the work directory.  The subject's server runs with the
   judge's `--safe`, so the `check_file` verdict it sees is the judge's (the
   three archived arms ran their subjects' servers without it: no final file
   carries a safe-flag refusal, and every subject's last `check_file`
   verdict agrees with the judge's, so no verdict depends on the
   difference).  The flag set, the environment additions, and the prompts
   are recorded verbatim in each run's `report.json` and `prompts/`, and the
   protocol (every knob a subject sees and the judge applies, and every
   input the run reads by content: the index, the corpora, the server, and
   the extractor by SHA-256) in `protocol.json`, written before the first
   subject spawns.
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
   kill is a stated cap); one that used a tool beyond them or left the
   directory fails the isolation gate.

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
| `subjects/<id>/mcp.json`, `prompt.txt`, `run.json` | the subject's server configuration, its rendered prompt, and how its process ended |

The work copies, the staging server's log, and Agda's interface files stay
behind under `data/benchmarks/reports/agent-bench/<run-id>/` (gitignored).

## The runs

| run id | model | date | obligations | solved | restated | anomalies | turns | tool calls | cost (USD, list) | quoted in |
|---|---|---|---|---|---|---|---|---|---|---|
| `smoke-haiku-1` | `claude-haiku-4-5-20251001` | 2026-09-15 | 1 | 1 | 0 | 0 | 4 | 3 | 0.04 | the isolation verification on [#154] |
| `cost-sonnet-1` | `claude-sonnet-5` | 2026-09-15 | 2 | 1 | 1 | 0 | 10 | 8 | 0.28 | the cost estimate on [#154] |
| `cost-opus-1` | `claude-opus-5` | 2026-09-15 | 2 | 2 | 0 | 0 | 12 | 10 | 0.47 | the cost estimate on [#154] |
| `agent-sonnet5-1` | `claude-sonnet-5` | 2026-09-15 | 55 | 46 | 8 | 0 | 327 | 272 | 4.62 | ADR 0001 § 9, README, [#154] |
| `agent-opus5-1` | `claude-opus-5` | 2026-09-15 | 55 | 54 | 1 | 0 | 325 | 270 | 9.14 | ADR 0001 § 9, README, [#154] |
| `agent-opus5-2` | `claude-opus-5` (second seed) | 2026-09-15 | 55 | 54 | 1 | 0 | 338 | 283 | 9.46 | ADR 0001 § 9, [#154] |

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

`make agent-bench-rejudge AGENT_BENCH_RUN_ID=<run-id>` judges an archived run
again from its final files and its own archived prompts without a model call
(the server and the extractor are still consulted), so a judge change never
costs a sweep; a copy of an archive re-judges as the original, the isolation
audit taking the work directory from the subject's own server config.  A run id is one protocol: `--resume on` keeps an archived
subject only when the run's `protocol.json` is the current protocol, field
for field, digests included, so a corpus or an index regenerated in place
refuses the run id rather than mixing two environments in one report (the
archived arms predate the record and cannot be resumed).  A model's answers are not deterministic: a
second seed of the frontier arm is recorded above for that reason, and any
new run gets a new run id.

[#154]: https://github.com/formalverification/agda-native-air/issues/154
