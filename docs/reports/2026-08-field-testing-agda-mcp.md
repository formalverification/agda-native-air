<!-- File: agda-native-air/docs/reports/2026-08-field-testing-agda-mcp.md -->
<!--
  Purpose: the end-to-end narrative of the agda-mcp field test — the
  zero-adoption session, the verify-before-filing pass, the #68 hardening
  wave, and (pending issue #83) the measured re-run.  Written to be citable
  independently of repository history; primary sources are permalinked.
  Status: DRAFT — § 6 awaits the #83 measurement results.
-->

# Field-testing an MCP server for Agda with a frontier agent

**Status: draft.**  Section 6 is pending the measured re-run (issue [#83]).  Everything else reports completed, verified work.

**Author:** William DeMeo, with the Claude Code sessions described in § 7.
**Period covered:** April – August 2026.  **Repository:** [`formalverification/agda-native-air`](https://github.com/formalverification/agda-native-air).

## Abstract

We built an MCP server that exposes Agda proof state to AI coding agents, demonstrated it end to end on fixtures, and then watched a frontier agent formalize ~1200 lines of real mathematics with the server loaded — and never call it once.  This report is the story of that negative result and what it took to change it: the agent's own structured post-mortem, a verification pass that re-tested every claim in it before any issue was filed (two claims did not survive; three new defects did), the twelve-issue hardening wave that followed, and a measured re-run of the same class of task against the fixed server.  Beyond the specific bugs, the arc supports three general lessons for anyone building agent-facing developer tools: a tool's verdict must be exactly as strict as the gate the agent is judged by; the tool description, not the implementation, is the adoption surface; and secondhand feedback — even from the agent itself — must be re-verified against the running system before it drives engineering.

## 1.  The system under test

`agda-mcp` is a Model Context Protocol server that wraps batch Agda (2.8.0, pinned by the repository's Nix flake) for AI coding agents.  At the time of the field test (v0.2.0, commit [`911ae18`]) it exposed four core proof-state tools — `check_file`, `get_diagnostics`, `get_goal`, `fill_hole` — plus three corpus-backed search tools when started with `--corpus`.  The two hole-oriented tools work by transiently patching the file in place (injecting a reflection macro from the repo-local `agda-dojang` library, or substituting a candidate term), running `agda`, and restoring the original bytes; this in-place design was itself the product of an earlier field-driven fix ([#66], PR [#67]), which is foreshadowing.

The server had passed its integration demo: the M1-4 milestone transcripts ([`reports/m1-4/`]) show a Claude Code session driving all four tools over benchmark fixtures in April 2026.  By the demo's standard, the tool worked.

## 2.  The field test: real mathematics, zero calls

In July 2026 a Claude Code session formalized work package RP-2 of the FLRP program in [`ualib/agda-algebras`] — two new modules totalling roughly 1200 lines of literate Agda (`.lagda.md`), across about fifteen type-check iterations and four full-library builds.  The project's `.mcp.json` loaded agda-mcp with the library on its include path, and the session's tool listing showed all four tools available.

**The agent never called the server.**  Every check went through `agda <file>` from the shell.

Asked afterwards to explain, the agent produced a structured post-mortem, now imported verbatim as [`docs/feedback/flrp-agda-mcp-improvements.md`] (PR [#80]).  Its § 2 reconstructs the per-call decision an agent makes, and is worth reading in full; compressed, the five reasons the shell won were:

+  **Trust**: a note from a prior session claimed the server could report green on a module the strict build rejects; a verdict that can disagree with the gate is worse than no verdict, because the real checker must be run anyway.
+  **Granularity**: the agent's edit unit was a whole module, not a hole, and for "check this file" the shell is already minimal.
+  **Literate blindness**: the repository is 100 % `.lagda.md`, and holes reportedly went unrecognized there — making the only two tools with no shell equivalent unavailable exactly where the work was.
+  **Wrong question**: the session's actual recurring questions were about scope ("which `≈sym` is this?", "what does this module export?") — roughly a dozen `grep` calls — and no tool answered them.
+  **Opacity**: nothing said which flags the server ran, whether its verdict matched `make check`, or what it cost; under uncertainty, the rational choice is the tool whose semantics are exactly known.

The document's own § 0 flagged which observations were firsthand, which were secondhand, and which were inferred — and asked that each be re-verified against the current server before any issue was filed.

## 3.  Verify before filing

A session in this repository did exactly that (2026-07-29, against [`911ae18`]): it drove scripted MCP stdio sessions — raw JSON-RPC into the server binary, no agent in the loop — over small fixtures, and cross-checked every verdict against bare `agda` under the pinned toolchain.  The full protocol and results are the feedback document's § 7; the scoreboard:

| Claim from the field | Verdict on `911ae18` |
| --- | --- |
| `check_file`/`get_diagnostics` report green on unsolved metas | **Not reproduced** — both were correctly red on every failing fixture |
| Cause: the server drives Agda's interaction mode | **Refuted** — it shells out to batch `agda` per call |
| The underlying green-verdict trust failure | **Confirmed, different locus** — `fill_hole` said `ok` for a candidate that leaves an unsolved implicit meta, while `agda` on identical content exits 42 with `[UnsolvedMetaVariables]` |
| `{!...!}` holes unrecognized in `.lagda.md` | **Confirmed, sharper cause** — hole detection matched only the literal token `{!!}`, in every file flavour; `{! !}`, `{! e !}`, and `?` were invisible, while `{!!}` in a *comment* or in markdown *prose* was counted — and even fillable |
| Diagnostics are prose, not data | **Confirmed, plus a bug** — no diagnostic carried a position, because the extractor expected Agda's old `file:10,5-15` format where 2.8.0 emits `file:9.12-13` |
| No scope/type/definition queries; no project mode; opaque environment; fragile hole indices | **Confirmed** |

Verification also found defects the field session never saw:

+  **`get_goal` returned the wrong goal — and always had.**  On the repository's own `Fixture01` (`id x = {!!}`, goal `A`), the reflection macro reported `(x₁ : _3 x) → _5 x x₁` — its own not-yet-elaborated type, not the hole's goal.  The April M1-4 transcript contains the same shape, where the driving agent *rationalized it* as "metavariables … due to mutual dependency between holes" and carried on.  CI never caught it because the unit tests asserted the marker parser against hand-written output; no test asserted an end-to-end goal value.
+  **`--timeout` was parsed and never enforced**; the field configuration's `--timeout 600` had no effect.
+  **Phantom holes shift indices**: in one fixture the `{!!}` inside a header comment was hole 0 and the real hole was hole 1.

Two meta-observations from this phase shaped everything after.  First, the asymmetry: the secondhand claims were partly wrong (the check tools were never green-on-red), but the *distrust* they produced was justified by adjacent defects the reporter had not seen — verification did not merely filter the feedback, it improved on it.  Second, the M1-4 rationalization is a live demonstration of why wrong answers are worse than errors for agent-facing tools: the agent did not fail loudly, it constructed a plausible story around the bad data and kept going.

## 4.  The hardening wave

The verified findings became a tracking issue ([#68]) with eleven sub-issues, prioritized by the field document's own § 6 framing — **P0 trust** (truthful `fill_hole`/`get_goal` verdicts, a real hole model, literate awareness, an explicit verdict contract), **P1 reach** (structured diagnostics, live scope/type/definition queries, environment transparency, enforced timeouts), **P2 economics** (whole-project checks, stable hole handles) — each carrying its empirical repro as acceptance criteria.

Landed at the time of writing:

+  **[#69] / PR [#81] — `fill_hole` no longer blesses unsolved metas.**  The tolerance intended to excuse *other still-open holes* was a blacklist over error tags that let `[UnsolvedMetaVariables]` ride along with the excused interaction metas.  It is now a whitelist: a non-zero exit is `ok` only when every reported error is `[UnsolvedInteractionMetas]`; unrecognized error classes fail closed.  The exact field-report pattern ("implicits under a defined function") is a regression test, and the tool description now states the contract — including the deliberate asymmetry, pinned by a test, that a `?` sub-hole is *tolerated* by the verdict but not yet *counted* by hole tracking.
+  **[#70] / PR [#82] — `get_goal` returns the hole's goal.**  Fixed in the `agda-dojang` reflection layer (the macro now follows a saturated-macro convention).  Verified end to end on current `main` ([`cf9d0ea`]): `Fixture01` holes report `A`, `⊤`, and `x ≡ x`, and a literate fixture with a concrete goal reports `Nat` — values that were meta-polluted garbage in § 3.

In flight as this draft is written: the hole-model rework with literate code-region awareness ([#71] + [#73], one branch — after which every Agda hole syntax is enumerated and comments and prose can never be holes), timeout enforcement with per-call timing ([#77]), and, once those merge, the explicit verdict echo and contract-bearing tool descriptions ([#72]).

## 5.  Interim state: what a client sees today

Probe values on `main` at [`cf9d0ea`], from the same scripted-stdio method as § 3 (each row cross-checked against bare `agda`):

| Probe | Result |
| --- | --- |
| `get_goal` on `Fixture01` holes 0/1/2 | `A` / `⊤` / `x ≡ x` ✓ |
| `get_goal` on a `.lagda.md` hole with goal `Nat` | `Nat`, correct context ✓ |
| `fill_hole` with a candidate leaving an unsolved implicit | `type_error` naming `[UnsolvedMetaVariables]` ✓ |
| `fill_hole` with a well-typed candidate, another hole open | `ok` ✓ |
| Four-syntax hole fixture (`{!!}`, `{! !}`, `{!zero!}`, `?`) | still `holesCount: 2` — awaiting #71 |
| Diagnostics positions | still absent — awaiting #74 |
| `--timeout` | still inert — awaiting #77 |

The automated suite has grown from asserting parser behavior on synthetic markers to 62 tests including end-to-end regressions for every fixed defect, run in CI against the pinned toolchain.

## 6.  The measured re-run — PENDING (#83)

*This section awaits the experiment specified in issue [#83], to run after the wave-1 fixes merge.*  The protocol, fixed in advance: a **fresh** Claude Code session, a **real** open FLRP work package in `ualib/agda-algebras`, the same `.mcp.json` shape as the baseline session, and a kick-off prompt that describes the mathematics and never mentions the MCP tools.  Recorded: per-tool MCP call counts (baseline: zero), iterations to a green strict gate, wall-clock, and verbatim transcript moments where the agent chose server versus shell.  The result will be reported here as measured, including a partial or null result — the § 3 lesson about honest verdicts applies to this report too.

<!-- TODO(#83): results table, transcript excerpts, and honest reading. -->

## 7.  A note on method

Every stage of this arc — the baseline formalization, the post-mortem, the verification pass, the issue tree, the fix PRs and their review round-trips, this draft — was executed by Claude Code sessions working under human direction in the workflow the repository's `CLAUDE.md` encodes: one concern per session and branch, empirical repro before filing, regression fixtures with every fix, and pull requests as the unit of review.  The feedback document at the center of § 2 was written by the agent *about its own refusal to use the tool*, and its § 0 skepticism discipline ("verify each claim against the current server before filing") is the reason § 3 exists.  We think this loop — agent field failure → agent post-mortem → verified issues → fixes → measured re-run — is itself a reusable pattern for hardening agent-facing tools, independent of Agda.

## 8.  What remains

The P1 reach items are where the server can become strictly better than the shell rather than equal to it: structured diagnostics with codes and ranges ([#74]), live scope/type/definition queries ([#75], the answer to the field session's dozen greps), and project-root transparency ([#76]).  P2 holds whole-project checking ([#78]) and stable hole handles ([#79]).  Their relative priority will be set by the § 6 transcript: whatever the agent still does in the shell is, by definition, the next issue.

## References

+  Field feedback with verification addendum: [`docs/feedback/flrp-agda-mcp-improvements.md`]
+  Tracking issue [#68]; sub-issues [#69]–[#79]; measurement issue [#83]
+  Fix PRs: [#81] (fill_hole verdict), [#82] (get_goal macro); prior art [#66]/[#67] (in-place checking); feedback import [#80]
+  Baseline demo transcripts: [`reports/m1-4/`]
+  Commits referenced: [`911ae18`] (verification baseline), [`cf9d0ea`] (current main)

[#66]: https://github.com/formalverification/agda-native-air/issues/66
[#67]: https://github.com/formalverification/agda-native-air/pull/67
[#68]: https://github.com/formalverification/agda-native-air/issues/68
[#69]: https://github.com/formalverification/agda-native-air/issues/69
[#70]: https://github.com/formalverification/agda-native-air/issues/70
[#71]: https://github.com/formalverification/agda-native-air/issues/71
[#72]: https://github.com/formalverification/agda-native-air/issues/72
[#73]: https://github.com/formalverification/agda-native-air/issues/73
[#74]: https://github.com/formalverification/agda-native-air/issues/74
[#75]: https://github.com/formalverification/agda-native-air/issues/75
[#76]: https://github.com/formalverification/agda-native-air/issues/76
[#77]: https://github.com/formalverification/agda-native-air/issues/77
[#78]: https://github.com/formalverification/agda-native-air/issues/78
[#79]: https://github.com/formalverification/agda-native-air/issues/79
[#80]: https://github.com/formalverification/agda-native-air/pull/80
[#81]: https://github.com/formalverification/agda-native-air/pull/81
[#82]: https://github.com/formalverification/agda-native-air/pull/82
[#83]: https://github.com/formalverification/agda-native-air/issues/83
[`911ae18`]: https://github.com/formalverification/agda-native-air/commit/911ae18eff7d846acb01013e1fbe8e2ebdac6c01
[`cf9d0ea`]: https://github.com/formalverification/agda-native-air/commit/cf9d0ea
[`docs/feedback/flrp-agda-mcp-improvements.md`]: https://github.com/formalverification/agda-native-air/blob/main/docs/feedback/flrp-agda-mcp-improvements.md
[`reports/m1-4/`]: https://github.com/formalverification/agda-native-air/tree/main/reports/m1-4
[`ualib/agda-algebras`]: https://github.com/ualib/agda-algebras
