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
| `report.json` | the run: `config` (model, caps, every client flag, the prompts' digests, the client version), `corpora` (paths and digests), `totals`, `perTier`, `perStratum` (each with `solved`, `restated`, and `solvedOriginalInView`, which is `null` on a slice with no original), `perTool`, and one `outcomes[]` entry per obligation (`solved`, `restated`, `gate`, `restatementEvidence`, `original`, `addedImports`, `terminal`, `turns`, `toolCalls`, `wallMs`, `costUsd`, `tokens`, `isolation`, `agdaExit`) |
| `results.jsonl` | one `eval-proof-completion.v0` attempt row per `fill_hole` the subject probed |
| `fixtures.jsonl` | one `eval-proof-completion.v0` fixture row per obligation, plus `restated`, `gate`, and `terminal` |
| `prompts/` | the system prompt and the user-prompt template, verbatim |
| `subjects/<id>/transcript.jsonl` | the client's `stream-json` output: every tool call with its result, the model's text, the init and result records |
| `subjects/<id>/final/<Stem>.agda` | the file as the subject left it, which is what was judged |
| `subjects/<id>/outcome.json` | the judge's verdict and the transcript audit for that row, with its `original` block: the restated lemma's file, whether its proof was in view before the last edit (`inView`, `how`, `at`, the call's index from 0), and the successful and refused calls that named the file (`reads`, `refusedReads`); `null` on a row with no original |
| `subjects/<id>/subject.json` | the arm the subject ran under and the roots its tools and commands were allowed, which is what a re-judge audits against |
| `subjects/<id>/mcp.json`, `prompt.txt`, `system-prompt.txt`, `run.json` | the subject's server configuration (an arm with the server), its two rendered prompts, and how its process ended |
| `subjects/<id>/stderr.log` | the client's standard error, archived when it is not empty; this is what an anomaly message means by "see stderr.log" |

A subject that ended early has only what it wrote: the archive copies each of
these when it exists, so a run with anomalous rows archives like any other.

The work copies, the staging server's log, and Agda's interface files stay
behind under `data/benchmarks/reports/agent-bench/<run-id>/` (gitignored).

## The runs

| run id | arm | model | date | obligations | solved | restated | original in view (of agda-algebras solves) | anomalies | turns | tool calls | cost (USD, list) | quoted in |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `smoke-haiku-1` | `mcp` | `claude-haiku-4-5-20251001` | 2026-09-15 | 1 | 1 | 0 | not re-judged | 0 | 4 | 3 | 0.04 | the isolation verification on [#154] |
| `cost-sonnet-1` | `mcp` | `claude-sonnet-5` | 2026-09-15 | 2 | 1 | 1 | not re-judged | 0 | 10 | 8 | 0.28 | the cost estimate on [#154] |
| `cost-opus-1` | `mcp` | `claude-opus-5` | 2026-09-15 | 2 | 2 | 0 | not re-judged | 0 | 12 | 10 | 0.47 | the cost estimate on [#154] |
| `agent-sonnet5-1` | `mcp` | `claude-sonnet-5` | 2026-09-15 | 55 | 46 | 8 | 0 of 13 | 0 | 327 | 272 | 4.62 | ADR 0001 § 9, README, [#154] |
| `agent-opus5-1` | `mcp` | `claude-opus-5` | 2026-09-15 | 55 | 54 | 1 | 0 of 20 | 0 | 325 | 270 | 9.14 | ADR 0001 § 9, README, [#154] |
| `agent-opus5-2` | `mcp` | `claude-opus-5` (second seed) | 2026-09-15 | 55 | 54 | 1 | 0 of 20 | 0 | 338 | 283 | 9.46 | ADR 0001 § 9, [#154] |
| `arm162-shell-1` | `shell` | `claude-sonnet-5` | 2026-09-21 | 55 | 50 | 0 | 15 of 18 | 0 | 308 | 253 | 2.88 | ADR 0001 § 9, ADR 0002 § 12, [#162] |
| `arm162-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-21 | 55 | 47 | 6 | 4 of 14 | 0 | 342 | 287 | 5.28 | ADR 0001 § 9, ADR 0002 § 12, [#162] |
| `arm162-both-1` | `both` | `claude-sonnet-5` | 2026-09-21 | 55 | 51 | 2 | 16 of 19 | 0 | 327 | 272 | 4.25 | ADR 0001 § 9, ADR 0002 § 12, [#162] |
| `iso184-1` | `mcp` | `claude-sonnet-5` | 2026-09-25 | 1 | 1 | 0 | not re-judged | 0 | 4 | 3 | 0.11 | the isolation check for client 2.1.282 on [#184] |
| `cost184-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-25 | 2 | 1 | 1 | not re-judged | 0 | 10 | 8 | 0.12 | the cost pair on [#184] |
| `cost184-both-1` | `both` | `claude-sonnet-5` | 2026-09-25 | 2 | 1 | 1 | not re-judged | 0 | 15 | 13 | 0.27 | the cost pair on [#184] |
| `arm184-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-25 | 55 | 46 | 8 | 3 of 12 | 0 | 359 | 304 | 4.63 | [#184], PR [#190] |
| `arm184-both-1` | `both` | `claude-sonnet-5` | 2026-09-25 | 55 | 49 | 2 | 14 of 18 | 0 | 318 | 263 | 4.00 | [#184], PR [#190] |
| `cost-surface-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-26 | 2 | 0 | 1 | 0 of 0 | 0 | 11 | 9 | 0.15 | the cost pairs on [#191] |
| `cost-surface-both-1` | `both` | `claude-sonnet-5` | 2026-09-26 | 2 | 1 | 1 | 0 of 0 | 0 | 14 | 12 | 0.23 | the cost pairs on [#191] |
| `cost-verdict-mcp-1` | `mcp`, four tools exposed | `claude-sonnet-5` | 2026-09-26 | 2 | 0 | 1 | 0 of 0 | 0 | 17 | 15 | 0.16 | the cost pairs on [#191] |
| `arm-surface-mcp-1` | `mcp` | `claude-sonnet-5` | 2026-09-26 | 55 | 48 | 7 | 6 of 14 | 0 | 345 | 290 | 3.83 | [#191], PR [#193] |
| `arm-surface-both-1` | `both` | `claude-sonnet-5` | 2026-09-26 | 55 | 46 | 4 | 8 of 14 | 0 | 318 | 263 | 3.55 | [#191], PR [#193] |
| `arm-verdict-mcp-1` | `mcp`, four tools exposed | `claude-sonnet-5` | 2026-09-26 | 55 | 52 | 1 | 9 of 20 | 0 | 458 | 403 | 3.78 | [#191], PR [#193] |
| `arm-verdict-mcp-2` | `mcp`, four tools exposed (second seed) | `claude-sonnet-5` | 2026-09-26 | 55 | 53 | 2 | 6 of 19 | 0 | 461 | 406 | 3.84 | [#191], PR [#193] |
| `arm-surface-mcp-2` | `mcp` (second seed) | `claude-sonnet-5` | 2026-09-26 | 55 | 45 | 8 | 2 of 13 | 0 | 349 | 294 | 3.74 | [#191], PR [#193] |

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
instructions (1,973 in the PR's final build, after two review fixes scoped
their exit-code rule to the file tools that return a verdict; the arms ran
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
[#191]: https://github.com/formalverification/agda-native-air/issues/191
[#193]: https://github.com/formalverification/agda-native-air/pull/193
