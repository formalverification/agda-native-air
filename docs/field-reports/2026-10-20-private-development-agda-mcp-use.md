<!-- File: docs/field-reports/2026-10-20-private-development-agda-mcp-use.md -->

# 2026-10-20, a private repository: agda-mcp across the seventeen sessions that wrote one formal development

+  **Date**: 2026-10-20.
+  **Harness**: Claude Code 2.1.282 (14 sessions), Codex CLI 0.162.1 and
   0.163.0 (one session each), Kimi Code CLI 2.1.1 (one session).
+  **Model**: Claude Opus 5.5 (Anthropic) wrote this report; the sessions it
   measures used Claude Opus 5.5 and Claude Fable 5.1 (Anthropic),
   GPT-6-Astra (OpenAI), and Kimi K3 (Moonshot AI).
+  **Effort**: per session, as each harness recorded it: xhigh or max in
   Claude Code, max and high in Codex CLI, max in Kimi Code CLI.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 217, type_of 24, normalize 12, search_by_name
   7, get_goal 7, exports_of 6, resolve_name 4, fill_hole 4, check_project 2;
   283 calls in all, over 17 sessions.

This report measures how the agda-mcp server was used by every session that
wrote one formal development, now kept in a private repository: 64 literate
Agda modules, 20,118 lines of source of which 12,261 lie inside Agda code
blocks, written from 7 to 17 October 2026 (UTC-6) by 17 sessions in three
harnesses and four models.  It is a measurement, not a session's own
account.  Every count below comes from the harnesses' own records (Claude
Code transcripts with their subagents, Codex CLI rollouts, a Kimi Code CLI
wire log), counted by one script under one set of rules; the per-session
reports that most of the sessions filed serve as a cross-check only.  One
further session wrote one small module of the development (321 lines) and
spent 48 of its 50 agda-mcp calls on modules outside it; it is left out of
every total.  Six more sessions of the same work wrote no Agda (planning,
writing, repository maintenance, and a tool in another language); the
server was connected in each, none called it, and they are left out as
well.

The sessions, labeled by the date they started and a letter where several
started that day.  Wall time runs from a session's first record to its
last; active time is the sum of the harness's own turn durations, and the
difference is time spent waiting on the person directing the work.  Under
"Outcomes", green and red are the verdicts of `check_file`, `fill_hole` and
`check_project`; "answered" and "Agda errors" are the replies of the query
tools, an Agda error being the in-band negative (a file that does not load,
an expression that does not elaborate); a call error is a call the server
refused before Agda ran.  The command-line columns count Agda runs made
through the shell: one or a few modules, the library's `make check`, and
measurements (profiles, timed or repeated checks).

| Session | Harness | Model (effort) | Wall h (active h) | Tool calls | agda-mcp calls | Share | Outcomes | CLI module / gate / measure | Server |
|---|---|---|---|---|---|---|---|---|---|
| 2026-10-07 | Claude Code 2.1.282 | Opus 5.5 (xhigh) | 16.6 (0.7) | 161 | 15: type_of 13, check_file 2 | 9.3% | 0 green, 2 red; 6 answered, 7 Agda errors | 10 / 3 / 3 | 0.2.0, an earlier build |
| 2026-10-11 a | Kimi Code CLI 2.1.1 | Kimi K3 (max) | 11.3 (4.6) | 239 | 70: check_file 70 | 29.3% | 8 green, 62 red | 0 / 0 / 0 | 0.2.0, `3de85b40` (inferred) |
| 2026-10-11 b | Claude Code 2.1.282 | Opus 5.5 (xhigh) | 2.1 (0.8) | 124 | 15: check_file 8, normalize 7 | 12.1% | 5 green, 3 red; 5 answered, 2 Agda errors | 8 / 2 / 2 | 0.2.0, `3de85b40` |
| 2026-10-11 c | Claude Code 2.1.282 | Opus 5.5 (xhigh) | 0.5 (0.4) | 138 | 8: check_file 7, type_of 1 | 5.8% | 7 green, 0 red; 1 answered | 8 / 0 / 4 | 0.2.0, `3de85b40` |
| 2026-10-11 d | Claude Code 2.1.282 | Opus 5.5 (xhigh) | 8.4 (1.2) | 223 | 18: check_file 13, normalize 3, type_of 1, exports_of 1 | 8.1% | 7 green, 6 red; 4 answered, 1 Agda error | 15 / 1 / 15 | 0.2.0, `3de85b40` |
| 2026-10-12 | Claude Code 2.1.282 | Fable 5.1 (xhigh, max) | 1.8 (0.8) | 202 | 0: none | 0.0% | no calls | 2 / 2 / 1 | 0.2.0, `3de85b40` |
| 2026-10-13 a | Claude Code 2.1.282 | Opus 5.5, Fable 5.1 (xhigh, max) | 10.0 (2.0) | 250 | 16: check_file 16 | 6.4% | 12 green, 4 red | 0 / 0 / 6 | 0.2.0, `3de85b40` |
| 2026-10-13 b | Claude Code 2.1.282 | Fable 5.1 (max) | 2.7 (2.2) | 139 | 15: check_file 15 | 10.8% | 7 green, 8 red | 0 / 1 / 1 | 0.2.0, `3de85b40` |
| 2026-10-13 c | Claude Code 2.1.282 | Opus 5.5 (xhigh) | 2.7 (1.1) | 186 | 5: exports_of 3, search_by_name 1, type_of 1 | 2.7% | 4 answered; 1 call error | 12 / 2 / 9 | 0.2.0, `3de85b40` |
| 2026-10-13 d | Claude Code 2.1.282 | Fable 5.1 (max) | 1.8 (1.7) | 146 | 26: check_file 23, normalize 2, type_of 1 | 17.8% | 8 green, 15 red; 2 answered, 1 Agda error | 0 / 5 / 1 | 0.2.0, `3de85b40` |
| 2026-10-14 a | Codex CLI 0.162.1 | GPT-6-Astra (max) | 0.4 (0.3) | 95 | 13: check_file 6, search_by_name 4, get_goal 3 | 13.7% | 5 green, 1 red; 5 answered; 2 call errors | 0 / 2 / 0 | 0.3.0, `9d099060` (inferred) |
| 2026-10-14 b | Claude Code 2.1.282 | Opus 5.5 (max) | 1.2 (0.9) | 258 | 7: resolve_name 4, type_of 1, exports_of 1, check_file 1 | 2.7% | 1 green, 0 red; 6 answered | 0 / 1 / 6 | 0.3.0, `9d099060` |
| 2026-10-15 a | Claude Code 2.1.282 | Opus 5.5 (max, xhigh) | 22.4 (1.5) | 486 | 15: check_file 7, type_of 4, fill_hole 2, get_goal 1, exports_of 1 | 3.1% | 3 green, 6 red; 6 answered | 1 / 5 / 3 | 0.3.0, `9d099060` |
| 2026-10-15 b | Codex CLI 0.163.0 | GPT-6-Astra (high) | 0.2 (0.2) | 83 | 7: get_goal 3, check_file 2, fill_hole 2 | 8.4% | 3 green, 1 red; 1 answered; 2 call errors | 0 / 1 / 2 | 0.3.0, `9d099060` (inferred) |
| 2026-10-16 a | Claude Code 2.1.282 | Opus 5.5 (xhigh) | 0.4 (0.4) | 163 | 18: check_file 13, type_of 2, check_project 2, search_by_name 1 | 11.0% | 12 green, 3 red; 3 answered | 0 / 0 / 4 | 0.3.0, `9d099060` |
| 2026-10-16 b | Claude Code 2.1.282 | Opus 5.5 (max, xhigh) | 16.1 (2.8) | 523 | 9: check_file 9 | 1.7% | 7 green, 2 red | 7 / 5 / 6 | 0.3.0, `9d099060` |
| 2026-10-16 c | Claude Code 2.1.282 | Opus 5.5 (xhigh) | 15.6 (1.9) | 352 | 26: check_file 25, search_by_name 1 | 7.4% | 19 green, 6 red; 1 answered | 0 / 7 / 6 | 0.3.0, `9d099060` |
| **Total** | 3 harnesses | 4 models | 114.3 (23.6) | 3,768 | 283 | 7.5% | 104 green, 119 red; 44 answered, 11 Agda errors; 5 call errors | 63 / 37 / 69 | |

+  **How it was counted**.  A tool call is one tool-use block in Claude Code
   (deduplicated by its id, since a streamed message repeats its blocks), one
   completed item in Codex CLI (whose code-mode cells each run several), and
   one tool call in Kimi Code CLI.  A verdict is read from the result's own
   fields (`success`, `timedOut`, `status`, an in-band `error`, a
   `rootMismatch`), never from prose.  A command-line Agda run is a shell
   command that runs the Agda binary on a file, the library's `make check`, or
   `make profile`, found by parsing each command: heredoc bodies are dropped,
   quoted text is ignored except a `bash -c` script, commands run in other
   repositories (a document build, say) are excluded, and a check that is also
   timed or profiled counts as a measurement.  Two controls hold.  The script
   reproduces exactly the 15 calls by tool that one session's own report lists
   (`2026-10-15-private-new-module-mcp-loop.md`), and Claude Code's MCP
   connection log, a record the client keeps apart from the transcript, holds
   the same number of calls as the transcript for every Claude Code session
   counted.
+  **Tools used**.  `check_file` made 217 of the 283 calls, and its 217 verdicts
   were 100 green and 117 red.  Its own `elapsedMs` had a median of 3.6 s over
   all 217 and fell as the server and its Agda changed: 5.9 s on 11 October,
   when the server ran a cached older Agda (below), 3.3 s on 13 October, 2.5 s
   from 14 October on; two calls took over 30 s.  The 60 query calls (`type_of`
   24, `normalize` 12, `search_by_name` 7, `get_goal` 7, `exports_of` 6,
   `resolve_name` 4) paid one load for the first question on a file (under 5 s
   from 13 October on, 22 to 28 s on 11 October under the older Agda) and then
   answered in milliseconds: 14 of the 49 timed answers came back in under 100
   ms, and from 14 October the median was 213 ms.  `fill_hole` ran 4 times (2
   accepted, 2 type errors) and `check_project`, the project's own gate, twice
   (both green, 2.0 and 4.8 s).  The share of all tool calls that went to
   agda-mcp ran from 1.7 to 29.3 percent per session, 7.5 overall: the rest
   were reads, edits, searches, git and the shell.  Of the 280 single-module
   checks the sessions made either way, 217 (78 percent) went through the
   server.
+  **What worked**.  Five things.  First, reliability: in 283 calls none timed
   out and none ended in a process failure, and the five that were refused
   before Agda ran named their cause (one `rootMismatch` naming both roots,
   three calls whose argument names the model had guessed, one `get_goal` on a
   file with no hole).  Second, every red verdict came with at least one coded,
   positioned diagnostic (85 with one, 32 with several), and 115 of the 117
   were errors in the code being written (`UnequalTerms` 35,
   `UnsolvedConstraints` 18, `NotInScope` 16, `TerminationIssue` 7, and 23
   other codes), so the edit-and-check loop never had to leave the server to
   learn what was wrong.  Third, agreement with the command line: a session that
   checked its modules both through the server and with the library's own Agda,
   a version apart, reports that every verdict agreed.  Fourth, the goal tools
   did what the hole loop needs: both Codex sessions and one Claude Code
   session read goals and contexts with `get_goal` and tried candidates with
   `fill_hole`, and a candidate that failed was answered in
   milliseconds.  Fifth, a fresh worktree whose development shell had not yet
   run needed only one entry into that shell from the command line; no call in
   any session failed for a missing library registry.
+  **What was awkward or missing**.  Five things sent work to the command line,
   which made 169 Agda runs.  First, a server bound to another checkout.  The
   server is anchored where the client starts, and a session cannot restart its
   own server: one session launched from the main checkout had the worktree's
   files refused (`rootMismatch`) and checked about 1,900 new lines from the
   shell (12 module checks), and a session reviewing a second worktree did the
   same once.  Second, a registry that named another checkout's library: on 7
   October both `check_file` calls failed with `AmbiguousTopLevelModuleName`,
   since every module of the worktree existed twice, and the session took its
   verdicts from the shell (10 module checks), using the query lane to load
   files and read types.  A load is not a verdict, and that session met the
   reason: a module the lane loaded failed in batch on an unsolved level
   metavariable.  Third, the server's Agda a release behind the library's: on 11
   October the registration named a cached Agda 2.8.0 while the library had
   moved to a 2.9.0 pre-release, and three sessions also checked from the shell
   with the library's Agda (31 module checks, confirming green verdicts and
   checking whole barrels); every registration in use from 13 October on names
   the checkout's own Agda wrapper.  Fourth, measurement: a `check_file` result
   carries its elapsed time and nothing more, while the library's rule for slow
   modules requires a measured per-module cost, and the sessions also tracked
   peak memory, so all 69 measurements were profiles or timed runs from the
   shell.  Fifth, the final gate: the project's instructions name `make check`
   as the gate, usually run cold after cleaning the build directory; one
   session used `check_project` (twice), and all 37 gate runs were from the
   shell.  Of the 63 single-module checks from the shell, 54 came from the
   sessions with a server bound to another checkout or running another Agda;
   the other nine were a toolchain probe (2) and one session's second looks at
   first-try passes before committing (7).
+  **Command line comparison**.  For checking one module neither loop was faster
   in general: each runs one cold batch Agda over cached interfaces.  In the six
   sessions that did both, the median check took 1.9 to 7.1 s through the
   server and 3.9 to 11.3 s through the shell (timed from call to result); the
   shell was quicker in the three sessions of 11 October, when the server ran
   the older cached Agda, and the server in the other three.  The server was the
   more efficient loop for iterating on new code, which is where the sessions
   used it: structured diagnostics, hole lists, goals, and query answers in
   milliseconds, where the command line offers an edit and a recheck.  The
   command line was the only loop for the library gate, for measurement, and
   for any session whose server was bound to another checkout or ran another
   Agda; for those sessions it was the right choice, not a preference.
+  **Server versions measured**.  The launcher resolves the server binary with
   `cabal list-bin` and builds nothing, so each session ran the last build in
   the main checkout before it started, whatever commit the checkout had moved
   to since.  The version below is the one the server reported to Claude Code,
   which the client's MCP log records; for the two Codex sessions and the Kimi
   session it is inferred from the launcher's rule, the main checkout's reflog,
   and the binaries' link times.
   +  7 October (one session): 0.2.0, a build linked over on 10 October, so its
      time is not recorded; its source is at or before `79322264`.
   +  11 to 13 October (nine sessions): 0.2.0, linked on 10 October at 14:21:58
      (UTC-6), 79 s after the main checkout moved to `3de85b40`, whose
      `agda-mcp/` is identical to the v0.2.0 release.  The checkout moved on
      seven times before the version changed, and these sessions ran none of
      it.
   +  14 to 16 October (seven sessions): 0.3.0, linked on 14 October at
      20:17:54 (UTC-6), 65 s after the main checkout moved to `9d099060`.  Its
      next move, to `0de13b25`, changed nothing under `agda-mcp/`, and no build
      since has relinked the binary.
+  **Sources**.  The per-session reports this report cites, all filed as
   private-repository reports and matched to their sessions by the slug each
   session's own transcript passed to `field_report.py new`:
   `2026-10-13-private-whole-module-checks.md`,
   `2026-10-13-whole-file-check-loop.md`,
   `2026-10-13-private-worktree-cli-checks.md`,
   `2026-10-14-hole-by-hole-structural-proofs.md`,
   `2026-10-14-private-scope-checks-in-a-review.md`,
   `2026-10-15-private-new-module-mcp-loop.md`,
   `2026-10-15-private-goal-candidates.md`,
   `2026-10-16-private-whole-file-loop-and-profiling.md`,
   `2026-10-16-private-whole-module-checks.md`, and
   `2026-10-16-private-generated-modules-whole-file-checks.md`.  One more
   session created its report's file and never submitted it.  Where a report and
   the records disagree (a model named without its variant, a count off by one,
   three effort settings that the records contradict, a harness version left
   unrecorded in two), this report uses the records.
