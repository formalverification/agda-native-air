# ADR 0002: agda-mcp

File: `agda-native-air/docs/adr/0002-agda-mcp.md`

+  **Status**: Accepted.  Every decision below is landed on `main`; follow-ups each one requires are named in its section and tracked in Milestone 5.
+  **Date**: 2026-09-07 (the day the [#68] hardening wave was closed as complete; the field record runs 2026-08-21 through 2026-09-04).
+  **Tracking**: [#148] (this record); [#68] (the wave, closed) and its children [#69]–[#79]; the fixes that followed from it, [#100], [#101], [#103], [#106], [#108], [#114], [#115]; Milestone 5 ([#134]–[#139], [#145]–[#147]) for what is open.
+  **Ancestry**: [#10] (M1-2, the four-tool server, PR [#38]); [#11] (M1-3, the corpus tools, PR [#44]); [#66] (in-place checking, PR [#67]); and [`feedback/flrp-agda-mcp-improvements.md`] (imported by PR [#80]), the field report whose § 7 verification addendum is where most of the decisions below were earned.

## Executive summary

`agda-mcp` is a small Haskell server that speaks the Model Context Protocol over stdio and gives a coding agent thirteen tools over the pinned `agda`.

+  **Proof-state tools**: `check_file`, `get_diagnostics`, `get_goal`, `fill_hole`.
+  **Whole-project gate**: `check_project`.
+  **Live queries**: `type_of`, `normalize`, `resolve_name`, `definition_of`, `exports_of`.
+  **Corpus lookups**: `search_by_name`, `search_by_type`, `get_dependencies` when started with `--corpus`.

This document is the design record: what was decided, the evidence that earned each decision, and what each one still owes.  The deep notes it distills stay where they are, under `docs/agda-mcp/`, and every decision links to its own note.

**The design in five minutes**.

The server runs Agda in two lanes and lets only one of them judge.

+  The *batch lane* spawns the real `agda` once per call and derives every verdict from that process's exit code, never from its prose.

   The verdict travels with the following:

   + the command to which it is equivalent, 
   + the resolved binary and working directory, and
   + the project to which the file resolved,

   so a client can check the claim instead of trusting it.

+  The *interaction lane* keeps one persistent `agda --interaction-json` child per project root and answers questions about a loaded file in milliseconds, such as the following:

   + what is this expression's type,
   + what does this name resolve to and why,
   + what does this module export, 
   + what does this hole want.

   Those answers inform and never decide, because interaction-mode Agda is tolerant by design: it loads a file with open holes where batch Agda exits 42.

Underneath both lanes sits one rule: when Agda can answer a question, ask Agda; anything the server derives from source text is a pre-flight approximation and a fallback, never the authority.

Why it is shaped this way comes down to one field datum and one measurement.

**The datum**.  In July 2026 a Claude Code session formalized about 1200 lines of literate Agda in `ualib/agda-algebras` with the server configured and its four tools listed, and never called it once, because nothing said whether green meant the build passed, and the two tools with no shell equivalent were unreliable on the literate files that repository is made of.

**The measurement**.  A batch judgment costs about 2.6 s of interface loading on a standard-library fixture, while a question about a file the lane has loaded costs 1–3 ms.  So verdicts are made expensive and unimpeachable, knowledge is made cheap and explicitly non-authoritative, and every response and every tool description says which of the two it is.

### Where it stands

The [#68] wave closed as complete on 2026-09-07: its eleven children ([#69]–[#79]) and the fixes that followed from them ([#100], [#101], [#103], [#106], [#108], [#114], [#115]) are all merged.

Nine field sessions between 2026-08-21 and 2026-09-04, in `agda-algebras` and in `formal-ledger-specifications`, record the server as the primary development instrument, with warm `check_file` rounds of 2–35 s against 20 s to 10 min for the shell equivalents, and with the project echo cited in nearly every report as the affordance that made a cross-worktree verdict trustworthy (§ 12 below).

### Where it goes

Milestone 5 collects the ergonomics the field record asked for (§ 13), as follows:

+ a profiling tool,
+ many-files-one-call forms,
+ an opt-in apply for `fill_hole`,
+ registry hygiene across worktrees,
+ a reason beside `checkedFromSource`,
+ queries inside a parameterized module's scope,
+ two payload fixes.

Corpus-backed retrieval *as server tools* is issue [#17] (M2-3), whose design map is a forward pointer from this record, not part of it.

---

## 1.  Context: the field test that shaped the server

The server's first shape (M1-2, PR [#38]) was four tools, each spawning a batch `agda` over a transient copy of the file, with `get_goal` reading a goal through the `AgdaDojang.Debug` reporting macro.  Issue [#66] (PR [#67]) moved checking in place, at the file's real path with the bytes restored afterwards, because a scratch copy of a hierarchically-named module fails with `ModuleDefinedInOtherFile`.  M1-3 (PR [#44]) added the three corpus tools.  That was the server the field session met.

The session (`ualib/agda-algebras` Issue [#459], PR [#507]) wrote its own post-mortem, which is [`feedback/flrp-agda-mcp-improvements.md`].  Its § 2 reconstructs the decision an agent makes at each check: a verdict it cannot trust costs more than no verdict; its edit unit is a whole module; every module is `.lagda.md`; its questions were about scope, not goals; and it could not tell what the server was doing.  Its § 0 asked that every claim be re-verified before an issue was filed, and the § 7 addendum (2026-07-29; scripted MCP sessions against `911ae18`, cross-checked with direct `agda` runs) did so, with the following result:

+  **Confirmed** (and even worse than reported).

   +  `fill_hole` answered `ok` for a candidate that left an unsolved implicit, where `agda` on identical content exits 42 ([#69]);
   +  `get_goal` reported the reporting macro's own unsolved type, `(x₁ : _3 x) → _5 x x₁`, where the fixture documents `A` ([#70], a long-standing defect that an April transcript had rationalized as "mutual dependency between holes");
   +  hole detection matched only the literal token `{!!}`, missing `{! !}`, `{! e !}`, and `?` in every flavour while counting, and filling, tokens in comments and prose ([#71], [#73]).

+  **Refuted**.  `check_file` was never green on unsolved metas: the server was batch-strict from the start, because it runs `agda <file>` per call.  What was missing was saying so, which became [#72].

+  **Found while re-testing**.  No diagnostic carried a position, because the parser expected Agda's old `file:10,5-15` format and 2.8.0 emits `file:9.12-13` ([#74]); `--timeout` was parsed and never enforced ([#77]).

The wave's plan kept the document's own priorities, as follows:

+  P0 is trust ([#69], [#70], [#71], [#73], [#72]),
+  P1 is reach beyond the shell ([#74], [#75], [#76], [#77]),
+  P2 is economics and ergonomics ([#78], [#79]).

Its acceptance metric was blunt, that the next real literate-repository session reaches for the server instead of the shell.

Three later issues came from the wave's own measurements rather than from the report, as follows:

+ [#101] from the [#83] field test (the one agent that reached for the server on its own sent a relative path, got a bare `-32603`, wrote "the MCP agda server crashed", and never called it again),
+ [#100] from a literate fixture whose prose named the module,
+ [#106] from reviewing [#100]'s fix, which spawned [#114] and [#115] by probe.

Issue [#103] made a second consumer project (fls) a client with its own toolchain, and [#108] moved `get_goal` onto the lane once [#75] had built it.

---

## 2.  The two-lane architecture

(See also [#75], [#108], and [`agda-mcp/agda-mcp-interaction-lane.md`].)

**Decision**.  Verdicts come from a batch `agda` process spawned per call; knowledge comes from a persistent `agda --interaction-json` child per resolved project root; and the boundary is policy, held by tool descriptions and reviews, not a convention.

+  **Batch lane** (verdicts): `check_file`, `get_diagnostics`, `fill_hole`, and `check_project`, plus `get_goal`'s fallback path.  Each spawns the real `agda` at the file's real path, patches in place when it must (`fill_hole`'s candidate, the reporting macro), and restores the bytes under `bracket_` on every path, timeout included.  The cost is a cold process per call, deliberately: a verdict is always batch Agda's own exit code.

+  **Interaction lane** (knowledge): `type_of`, `normalize`, `resolve_name`, `definition_of`, `exports_of`, and since [#108] `get_goal`'s primary path (`Cmd_goal_type_context` returns Agda's own goal display as data, with no file mutation; the response says `source: "interaction-lane"`, and the injected-macro path remains as `source: "injected-macro"` for a lane that cannot serve the file, and as the one path that reports binder visibility).  Interaction mode loads a file with open holes and *succeeds*, which is exactly why it may never decide a verdict; the tool descriptions say this out loud.

+  **A peek is not a call**.  The batch tools may read a warm lane's *stored* load to enrich a response, filling hole listings' `goal` fields ([#108]) and unsolved metas' names and types ([#115]), and only when the lane's recorded load matches the file's current bytes; a cold or stale lane leaves the response byte-identical, and no batch tool ever spawns, loads, or waits on a lane.

+  **The lexical layer is demoted, not deleted**.  `AgdaMCP.Holes` stays the splicing engine (a pre-Agda source edit needs a source view) and the fallback for files Agda refuses to load; it is never again the authority for anything Agda can answer, and parity tests hold it to the lane's `InteractionPoints` across the fixture matrix.

+  **`scope_at` was omitted rather than approximated**: no interaction command enumerates the names in scope, and the bar (§ 2.2 of the field report) is to ship a tool only if it helps the server beat the shell.  The finding is recorded on [#75].

+  **Corpus tools ride neither lane**; they are pure lookups on an in-memory index (§ 10).

**Evidence**.  The lane note was written from live probes of the protocol under the pinned Agda 2.8.0 before the Haskell existed, and the implementation cites it.  The economics, measured disk-warm: a batch call costs 2.78 s and 2.60 s on the repeat, paid per call; the lane's process start plus `Cmd_load` costs 2.59 s once, and five knowledge queries after it added less than measurement noise (2.580 s for the load plus five, against 2.589 s for the load alone).  Switching between two files under one root pays the switched-to file's load, tens of milliseconds warm.  The [#83] shell baseline was a 10.0 s median per check.  Three protocol facts are load-bearing and were each probed: commands execute strictly in order, so a `Cmd_show_version` sentinel after every command frames responses without heuristics or timeouts; a per-load argv must carry the resolved project flags, because `Cmd_load` with an empty list inherits no useful context; and a hole-free file's completed top-level scope loses file-local `open`s, so `resolve_name` prefers a goal-scoped query whenever the file has an interaction point.

**Lifecycle, in brief**.  One lane per root of the same per-call project resolution the batch tools use, so "which tree" and "which process" cannot diverge; requests serialized per lane; a re-load only on evidence of change (mtime, size, and a content fingerprint, or the client's `reload: true` for a changed dependency, which no stamp on the queried file can see); one deadline shared by every phase of a request; the [#77] kill ladder on expiry, then a respawn; a crash surfaced as a structured failure naming the lane, the event, and the child's stderr tail, never a bare `-32603`; idle lanes closed by EOF, which Agda answers by exiting cleanly.

**Status**.  Adopted (PRs [#107] and [#110]).  Open: queries inside a parameterized module's scope ([#139], [M5-6]); an honest payload when hole goals degrade to `?` because the lane holds no matching load ([#146], [M5-8]); many-files-one-call forms of `check_file` and `exports_of` ([#135], [M5-2]); and in-band cancellation via `Cmd_abort` instead of the kill ladder, noted as follow-on work in the lane note.

---

## 3.  The verdict discipline

(See also [#69], [#72], [#78], and [`agda-mcp/README.md`].)

**Decision**.  `success` is a function of the exit code alone, and every verdict says what ran and what green means.

+  Every proof-state response carries `verdict` (`equivalentTo`, the exact `agda` command the call is equivalent to; `meaning`, one sentence; `exitCode`, Agda's own), `command` (`binary` resolved against `PATH`, `args`, `cwd`), and `project` (§ 5).  A change in Agda's message format can empty the diagnostics list; it cannot turn a failing build green.  The suite pins this with a stand-in binary that exits non-zero while printing nothing a parser could latch onto.
+  `fill_hole` tolerates exactly one class of error on an otherwise green file: the `[UnsolvedInteractionMetas]` of the file's other open holes and of sub-holes inside the candidate.  A candidate that leaves `[UnsolvedMetaVariables]` or `[UnsolvedConstraints]` is a type error ([#69], PR [#81]); that is the FLRP "implicits under a defined function" pattern that cost the field session a build cycle.
+  There is no `strict` option, because there was never a lenient mode; the work of [#72] was contractual, not semantic, and the four tool descriptions now carry the client-visible contract, so a `tools/list` dump alone answers whether green means the build passes (the report's § 6 meta-suggestion).
+  `get_goal`'s batch path reports a non-zero `exitCode` even when the goal is right, because the injected macro leaves an interaction point behind, and its description says so; a lane-sourced answer carries no verdict at all.
+  `check_project` ([#78], PR [#98]) is the one deliberate departure, and only in the safe direction: `success` is a conjunction of exit 0, finishing inside the bound, and no failure evidence in the output, so a wrapper that ends in `echo` and reports exit 0 for a failed `make` comes back as `success: false` with `maskedFailure: true`.  The recognizers (an Agda error diagnostic, GNU make's own `*** ... Error N` line) are a list, not a theory, so `outputTail` is returned whatever the verdict; evidence can turn a green gate red, never a red gate green.  The gate is discovered in a fixed order (a named `make` target; `--check-command`, run directly with no shell; the nearest Makefile's `check`; `agda` on the `Everything` module; else a failure naming what was searched), and a check that did not happen is never reported as a pass.

**Evidence**.  The § 7 verification of the field report is the record of what an untrustworthy verdict costs, and the consumer-side document written after the RP-3 session ([`feedback/agent-case-for-corpus-proof-search.md`] § 1) names the discipline's effect: it "removes an agent's ability to talk itself into 'probably green'".  The 2026-08-21 field report used the `verdict` echo to quote a check in a PR body "as a checkable claim rather than an assertion".

**Status**.  Adopted (PRs [#81], [#95], [#98]).  No open follow-up.

---

## 4.  Ask Agda, don't re-derive

(See also [#100], [#106], and [`agda-mcp/agda-mcp-ask-agda-audit.md`].)

**Decision**.  `answer = whatAgdaSaid <|> whatWeDerived`.  When Agda can answer a question, in output a call already captures or through a lane query, Agda's answer is the authority; a local derivation from source text is a pre-flight approximation and a fallback, and a change in Agda's output degrades a field to the derived value, never to a wrong value.  The rule is written where a new tool's author will read it, in the README's architecture notes, and [#106] audited it across every derived answer in the server.

+  **The worked example ([#100], PR [#105])**.  `get_goal` scanned the file for its `module` field, so a literate file whose prose opened a line with `module` was reported under the prose's name, while Agda had already printed the true answer in the `Checking M (path).` line of the same run.  Agda's answer is also better than a correct scan's: it is the name Agda *resolved* (`AnonModule` for a `module _ where` header, `Proofs.Use` for a hierarchical module), where a scan can only repeat what the header claims, and the difference is a diagnosis.  Both paths now read Agda's name first (the lane's stored `liModule`, the batch run's `agdaModuleNameOf`), with the declared-name scan off the code-only view as the fallback.
+  **The inventory's verdicts**.  Delegated: goal type and context ([#108]), the module name ([#100], [#108]), goal-scoped hole answers ([#75]).  Subordinated rather than substituted: the batch listings' hole positions and spans, which the scan still computes on every call because the splicing engine structurally needs a source view; their warrant is the parity suite (tier 2d against batch Agda, tier 3 against the lane's interaction points), not a per-call answer, and the audit records that residue accurately.  Stays local by measurement: project resolution, because no Agda query answers "what libraries and include paths apply to this file" and the lane is a consumer of that answer, not a source.  Out of scope: the gate discovery in `AgdaMCP.Gate`, which is not Agda's question.
+  **Measurement 1 refuted the strong conjecture**.  Driving `agda --interaction-json` over the § 5 error corpus showed the protocol carries the same prose batch prints, in a JSON envelope: the envelope retires the parser's segmentation layer in principle (block splitting, banner dedup, severity classification) and none of its content extraction (codes, ranges, `involved` payloads).  So [#74]'s parser stays, transport-independent, and a lane-sourced diagnostics tool would run the same parser on the same prose.  The one class where the protocol carries more than the prose, unsolved metas with names and types as data, became [#115].
+  **Measurement 2 found a hole in the rule's own application**, and became [#114] (§ 8).

**Evidence**.  Four module-name shapes measured on [#106] (Agda's answer against the scan's); the per-class table in the audit's § 3, one fixture per § 5 error class driven three ways; and the acceptance item that asked [#75] to say it "retires" the scanner and the injection, recorded as overtaken because the scanner splices and the injection reports visibility on purpose.

**Status**.  Adopted (PRs [#105], [#110], [#116]).  No open follow-up; the rule is the review question for every new field.

---

## 5.  Project resolution and transparency

(See also [#76], [#101], [#103], and [`agda-mcp/agda-mcp-environment.md`].)

**Decision**.  The library context is resolved per call from the requested file, echoed in full, and a wrong tree is an error, not a wrong answer.

+  **Resolution**.  Walk up from the file to the nearest `*.agda-lib`, stopping at a repository boundary; read the registry `agda` will actually use (the server's `--library-file`, else `$AGDA_DIR/libraries`, else `~/.agda/libraries`) fresh on every call, because a snapshot at startup is not necessarily what the next call will read; then act on the comparison.  A registry that roots the file's library *elsewhere* is refused before `agda` is spawned, with a `rootMismatch` object naming both roots and the registry that disagrees.  A registry that agrees proceeds unchanged.  A library the registry has never heard of proceeds with its own `include:` directories added as `-i`.  No `*.agda-lib` above the file proceeds on the server-start configuration and says so, `rootSource: "server-config"`.  Two stated limits: a configured `--library-file` that does not exist leaves nothing to compare against, which the response reports as `librariesFileMissing` rather than leaving the caller to infer it; and the name comparison is exact, so the check catches stale worktrees, not stale versions.
+  **The echo**.  `project` carries `rootSource`, `root`, the file's own `library`, the `librariesFile` consulted, what it declares (`registeredLibraries`), and the effective `selectedLibraries` and `includePaths`, so `project` and `command.args` never disagree.
+  **Paths are resolved honestly and never guessed ([#101], PR [#102])**.  A relative `filePath` resolves against the server's working directory, the only directory a separate process knows; a path that resolves to nothing readable is refused with a `pathError` naming what was sent, what it resolved to, the directory, and the fix, and only regular files are ever opened.  Trying the path under each registered root and taking a unique hit would have made the [#83] call succeed, at the price of occasionally answering green about a tree nobody named, which § 3.6 of the field report calls worse than an error.  MCP's `roots/list` is the protocol-correct way to learn where a client stands and is left as follow-up work pending a bidirectional transport.
+  **A foreign toolchain is a first-class client ([#103], PR [#104])**.  `--agda-bin` names the client's own `agda` (for a Nix-pinned project, a gc-rooted wrapper realised once), and `--cwd` names its checkout root, because Agda anchors project discovery to the directory it runs in, not to the checked file; the checking `agda` then runs there and writes its interfaces where the project's own `nix develop --command agda` would.
+  **The stray directory ([#76])**.  The untracked `agda/` directory the field report saw in a client worktree was reproduced and explained, and the fix is recorded in § 11.

**Evidence**.  The 2026-08-21 report: `rootSource: "nearest-agda-lib"` picked up the worktree's own `.agda-lib` while the server's cwd was another repository, "precisely the failure mode agda-algebras' `CLAUDE.md` warns about for the `nix develop` `agda` wrapper", and "the echo makes it verifiable rather than hoped-for".  The 2026-09-01 fls report: both subprojects (`formal-ledger` and the Hydra-only `formal-ledger-test`) resolved with zero configuration, where the CLI equivalent is hand-assembled `-i` flags.  The 2026-09-01 agda-algebras report: a `LibraryError` on first contact was a ten-second read from `command`, `project.registeredLibraries`, and `rootSource`.  Eight of the nine reports name the per-call resolution or its echo as the reason a cross-worktree verdict could be trusted.

**Status**.  Adopted (PRs [#95], [#102], [#104]).  Open: the registry's one-absolute-path-per-library shape goes stale under worktree churn (three sessions in two weeks hit it), and [#137] ([M5-4]) chooses between a parent-directory registration and lazy resolution.

---

## 6.  Structured diagnostics

(See also [#74] and [`agda-mcp/README.md`].)

**Decision**.  Diagnostics are data beside the prose, in a shape a client can branch on.

+  Each carries `code` (Agda's own bracketed name, or a warning's `-W[no]Code`); `file` and a 1-based `range` in the file as written (both of Agda's position formats parse, and `line` and `col` stay as aliases of the start); the *full* message body, bounded at 24 lines and 2000 characters with the elision stated; and an `involved` payload per code: `expected` and `actual`, `candidates` (did-you-mean lists, ambiguity candidates, missing exports, a clashing definition's origin), `metaTypes` per unsolved meta or constraint, and since [#115] `metas` with each meta's name, type, and range when a warm lane holds them.
+  Ordering is most-likely-root-cause first and stable: unresolvable-file errors, the scope warnings that precede a hard error (`ModuleDoesntExport` before the `NotInScope` it causes), scope errors, type errors, unsolved metas and constraints, remaining warnings.  The list is capped by `maxDiagnostics` (default 10) with `diagnosticsTotal` reporting the pre-cap count, and the duplicates Agda prints under its "All done; warnings encountered" banner collapse to one.
+  The regression suite has one fixture per class of the field report's § 5 corpus, asserting the code, the range, and the payload § 5 asks for.

**Evidence**.  The 2026-08-29 report: five errors across the session, "each diagnosed from one call", including two `UnsolvedMetaVariables` batches whose `involved.metaTypes` identified the implicit-endpoint disease and "one stray underscore whose 1-char range pinpointed an argument that vanishes under reduction".  The 2026-09-02 report: six errors in a 737-line module, each "localized instantly", the fixity bug "a ten-second read" from `involved.actual/expected`.  The consumer-side document's § 1 names structured diagnostics as the attack on an agent's dominant failure mode, "misdiagnosis followed by thrashing".

**Status**.  Adopted (PRs [#94] and [#118]).  Open: `UnsolvedConstraints` restates the whole meta dump beside the `UnsolvedMetaVariables` list that was the useful part, "a hundred lines for six metas" ([#145], [M5-7]).

---

## 7.  The hole model

(See also [#70], [#71], [#73], [#79], and [`agda-mcp/README.md`].)

**Decision**.  A hole is what Agda would treat as an interaction point, addressed by position, and every answer re-anchors the client.

+  `AgdaMCP.Holes` ports Agda 2.8.0's literate preprocessor and a model of its lexer (PR [#88]): every hole syntax (`{!!}`, `{! ... !}` with nesting, a lexically separate `?`); no hole inside comments, pragmas, string or character literals, or literate prose; every literate flavour Agda supports masked to its code regions; and all positions in the coordinates of the file as written.  The same scan yields the *code-only view* that the reporting-macro injection and the module-name fallback read, so there is one answer to "is this line code?" rather than one per caller ([#100]).
+  `get_goal` reports the hole's goal, not the reporting macro's own unsolved type; the defect was in the agda-dojang reflection layer as driven by batch Agda 2.8.0, and CI could not see it because no test asserted an end-to-end goal value ([#70], PR [#82]).
+  Holes are addressed by `(line, column)`, with `holeIndex` kept for compatibility and documented as source-order and shift-prone ([#79], PR [#99]).  A position inside no hole is an error listing the file's nearest holes, never a guess; a request carrying both spellings, or half a position, is rejected.  `check_file` and `fill_hole` return the full hole list, and `fill_hole`'s list describes the file *as that candidate leaves it*, so a multi-hole edit needs no index bookkeeping between calls.

**Evidence**.  Verification's fixture with four Agda-visible holes reported two, one of them in a header comment, so "the first hole" addressed a comment ([#71]); `fill_hole` on a prose token in a `.lagda.md` returned `ok` ([#73]).  Parity tests pin the scan to batch Agda and to the lane's interaction points across the fixture matrix.  ADR 0001's state model adopts `fill_hole`'s re-anchored list wholesale, so client-side hole arithmetic can never drift from Agda's.

**Status**.  Adopted (PRs [#82], [#88], [#99]).  Open: `fill_hole` restores the file even when the candidate is accepted, so every accepted candidate is re-applied by hand, and [#136] ([M5-3]) chooses between an opt-in `apply` and a returned patch.

---

## 8.  Evidence-channel honesty

(See also [#114], [#115].)

**Decision**.  Before inferring anything from what Agda did *not* say, check that the channel it would have said it on was open; an absent field means unknown, never a guess.

+  `checkedFromSource` ([#77]) reads Agda's `Checking M (path).` progress lines, and its warm branch is an inference from silence, since a warm `agda` exits 0 printing nothing.  `--trace-imports=0` manufactures that silence, so under it a cold check wore the warm signature in both lanes ([#114], PR [#117]).  Detection is complete because the flag's arrival path is single (an `OPTIONS` pragma and an `.agda-lib` `flags:` field are both rejected with `[OptionError]`, so only the argv the server assembles can carry it) and its grammar is closed (`=N` is the only level-carrying spelling, bare means 2, a space-separated level is not one, the last occurrence wins; every spelling measured).  Both lanes read the effective level out of the argv they built and withhold every answer that would rest on a silence the server caused: the boolean in each lane, and `check_project`'s `modulesChecked`, which counts the same lines.  A progress line that did arrive still outranks the muting.
+  **Degrade was chosen over restore**.  Appending `--trace-imports=1` when the effective level is 0 would keep the field truthful, but `--agda-bin` may name a foreign toolchain ([#103]), and a flag an older `agda` rejects would break every call; restoring needs a version gate that degrading does not.
+  **Unsolved metas as data ([#115], PR [#118])**.  Agda prints its unsolved metas' locations and never their types, so the § 5 corpus's last ask was unanswerable from a batch run; the lane's `AllGoalsWarnings` lists every meta with a name, a type, and a range.  `check_file` and `get_diagnostics` attach them as `involved.metas` from the same warm-lane peek that fills hole goals, never a lane call and never a verdict input; `metaTypes` is untouched because it is what Agda's prose said.

**Evidence**.  The misreading reproduced through the real server on a clean module with caches scrubbed before each run (`true` with default flags, `false` with the flag appended, for the same source re-check); the lane's cold `Cmd_load` under the flag emitting no `RunningInfo` at all; the level-semantics table in the audit's § 4.  Field: the 2026-08-22 report read `checkedFromSource: true` at 17.8 s and then `false` at 2.3 s as the interface reuse it was; the 2026-09-02 report caught a consumer module served from cache after its dependency changed and re-checked the spine.

**Status**.  Adopted (PRs [#117] and [#118]).  Open: `checkedFromSource: false` right after an edit reads as "stale" until one remembers interfaces are content-hashed, and [#138] ([M5-5]) adds a reason beside the boolean.

---

## 9.  Enforced timeouts, timing, and cache visibility

(See also [#77].)

**Decision**.  Every call is bounded, the bound is enforced by killing the process, and every response says how long it took and whether Agda re-checked from source.

+  `agda` is spawned into its own process group, its stdout and stderr drained on dedicated threads so neither can fill a pipe and deadlock the other, and raced against a timer; on expiry the group gets SIGINT, then SIGTERM, then SIGKILL, and is reaped.  Wrapping `readProcessWithExitCode` in `System.Timeout.timeout` could not do this: it kills the waiting Haskell thread and leaks a running `agda` every time it fires.  A timeout is returned as a value, never thrown, which is what lets the in-place tools' `bracket_` restore run on the timeout path exactly as after a clean check.
+  The default bound was raised from 30 s to 300 s so cold interface builds are not aborted, and the shipped registrations pass 600 s; sizing the bound too small is not a graceful degradation, since it aborts exactly the call that would have built the interfaces.  `check_project` has its own `--check-timeout` (default 1800 s), because a whole-project gate legitimately runs for tens of minutes.  The lane shares one deadline across a request's phases, pipe writes included, and kills its child by the same ladder.
+  Every response carries `elapsedMs` and the tri-state `checkedFromSource` of § 8, so a client can tell a slow cold call from a slow warm one, which § 3.7 of the field report says is the only way an advantage influences a decision.

**One correction to the record**.  The 2026-09-01 fls report praises a 173 s check that "moved itself to the background and notified on completion".  That is the client harness backgrounding a long tool call; the server's contribution is the bound that makes a long call safe to wait on.  The behavior is real and worth having, but it is not a server decision, and this record does not claim it as one.

**Evidence**.  [#77]'s finding that `FillTimeout` was unreachable code; the suite's pinning of the restore on the timeout path; the per-call timings across the field record (§ 12).

**Status**.  Adopted (PR [#89]; the lane's deadline in PR [#107]).  Open: there is no profiling lane, so the 2026-08-30 and 2026-09-04 sessions measured with `/usr/bin/time` and `agda --profile=internal` from the shell, and [#134] ([M5-1]) proposes `profile_file`.

---

## 10.  Corpus tools

(See also [#11] (M1-3) and [`agda-mcp/README.md`].)

**Decision**.  Three pure lookups over an in-memory index of an `agda-strux` JSONL corpus, registered only when the server starts with `--corpus`, and never invoking Agda: `search_by_name` (case-insensitive substring over names), `search_by_type` (substring over printed types), and `get_dependencies` (a definition's dependency list, optionally expanded one hop).

**Evidence**.  At library scale (the published agda-algebras v0 corpus, `docs/corpora/`), 11,666 rows and 185 MB of JSONL load in about 1.4 s to a 308 MB resident footprint, because the index keeps only the fields the tools serve and drops `typeAst` and proof bodies; `hasBody` tells an agent a term exists to go and read.  Two consequences are documented for query writers: dependency tokens are fully qualified, and 655 `prettyQname` keys are shared by more than one row.  `make corpus-mcp-smoke` drives all three tools over the transport.

**Status**.  Adopted (PR [#44]), unchanged by the [#68] wave.  The forward pointer is [#17] ([M2-3]): corpus-backed retrieval *as server tools*, scope-aware and returning checked terms, whose design map is in that issue's comments and is argued from the consumer-side document's four requirements (checked terms only; scope-awareness through the checker; honest negatives with stated bounds; latency that beats grep-plus-read).  That design is not part of this record.

---

## 11.  Environment and registration

(See also [#76], [#103], [#133], and [`agda-mcp/agda-mcp-environment.md`].)

**Decision**.  The server is a separate process with its own toolchain and working directory, and the client registration says so explicitly rather than relying on anything the operator's shell provides.

+  **The shell wrapper is not the server's `agda`**.  Inside `nix develop`, the `agda` on `PATH` is a wrapper that supplies a `--library-file` into the Nix store, and the shell *function* the hook defines (which adds `--no-default-libraries` and the `--library` flags) is invisible to any subprocess.  So a client registration passes `--library-file` and `-l` explicitly, and `command.binary` in every response says which `agda` ran.
+  **`agda/libraries` is shared, mutable, process-global state**.  The hook exports `AGDA_DIR` unconditionally and rewrites `$AGDA_DIR/libraries` on every shell entry from whatever `*_ROOT` variables are then in effect, which is why the server reads the registry fresh per call (§ 5) rather than at startup.  The server writes nothing of its own; the only durable writes are Agda's `.agdai` interfaces beside each checked source.
+  **The stray directory, explained ([#76])**.  The flake's shellHook derived its root from the *client's* checkout when an MCP client spawned the server there, wrote a broken registry into `<client>/agda/`, and sbt's version probe wrote `target/` beside it.  `scripts/run-server.sh` now anchors the shell with `AGDA_NATIVE_AIR_ROOT` and enters this repository first, and the hook validates its root against a marker only this repository carries, warning loudly instead of writing elsewhere.
+  **Two registration shapes, both anchored per worktree**.  A project checked with *this* repository's toolchain (agda-algebras) registers through `env.AGDA_ALGEBRAS_ROOT`, which the hook turns into a registry line; a project with its own pinned toolchain (fls) registers with `--agda-bin` and `--cwd` ([#103]).  In the claude-tooling registrations both anchor to `${PWD}`, which Claude Code expands in `args` at spawn, so each session binds to the checkout it was launched from through one shared registration file ([#133], verified end to end on 2026-09-01).  The in-repo templates under `agda-mcp/examples/` carry absolute placeholders for clients that do not expand variables.

**Evidence**.  The reproduction in the environment note (a foreign `git init` directory acquiring `agda/libraries`, `agda/defaults`, and `target/` on shell entry, with a registry line pointing at a path that does not exist) and its after-fix table; [#133]'s diagnosis, in which every fls checkout's `.mcp.json` was a dangling symlink and the tooling copy was a byte-for-byte agda-algebras registration.

**Status**.  Adopted (PRs [#95] and [#104]; the registrations live in claude-tooling).  Open: [#137] ([M5-4]), as in § 5.

---

## 12.  Where it stands: the field record

`docs/mcp-field-reports.md` holds twelve session reports appended by agents working in `ualib/agda-algebras` and `formal-ledger-specifications`; three ran without the server connected and say so.  The nine with the server, condensed:

| date | project, task | tools | what was measured |
|---|---|---|---|
| 2026-08-21 | agda-algebras, docstring audit | `exports_of` ×3, `check_file` ×2 | `exports_of` with `module: ""` validated a corpus linter against Agda's own scope (15 vs 14, 33 vs 33, 4 plus a nested module); first load ~4 s, a heavy module ~18 s |
| 2026-08-22 | agda-algebras, prose-only pass | `check_file` ×2 | `checkedFromSource` true at 17.8 s, false at 2.3 s; a nine-file sweep was better as a shell loop |
| 2026-08-29 | agda-algebras, FLRP RP-3 (~1200 lines) | `check_file` ~10 | warm 7–35 s per call against ~10 min `make check`; five errors, each diagnosed from one call |
| 2026-08-30 | agda-algebras, IsSimple and a certified A₅ | `check_file` ~12 | six new modules green on first check; no profiling lane |
| 2026-08-31 | agda-algebras, simple algebras | `check_file` ×6 | 2–13 s per call against 20–30 s for `nix develop --command agda` |
| 2026-09-01 | agda-algebras, Entry 4 no-go | `check_file`, `get_diagnostics`, `fill_hole` | 6–8 s warm against 2–3 min cold `make check`; `fill_hole`'s `UnsolvedConstraints` payload found the one real bug; the first session with the server as the primary instrument |
| 2026-09-01 | fls, Leios primitive types | `check_file` ×6, `type_of` ×2 | both subprojects resolved with zero configuration; first literate load ~28–30 s, then 90 ms; top-level `type_of` sits outside a parameterized module |
| 2026-09-02 | agda-algebras, Kurzweil surjectivity | `check_file` ~15 | 6–12 s per round against ~40 s cold `agda`; six errors in a 737-line module, each localized instantly |
| 2026-09-04 | agda-algebras, the Parachute record | `check_file` ×4 | every edit green on the first pass (7 s, 24 s); profiling ran in the shell; the one save was the root confirmation |

Two honest patterns run through the record.  Hole-driven development was mostly unused, and the reports say that was the right call: when an agent can read the sources into context and design the proof whole, write-then-check wins, and holes pay when goal types are genuinely unknown.  And the server's value in these sessions was latency, structured diagnostics, and the project echo, not capability the shell lacks; the shell stayed better for per-file sweeps and for the final whole-library gate.  Both patterns are inputs to Milestone 5 and to [#17].

---

## 13.  Where it goes

+  **Milestone 5, AgdaMCP as a daily research instrument**, filed from the field record: `profile_file` ([#134], [M5-1]); many-files-one-call forms of `check_file` and `exports_of` ([#135], [M5-2]); `fill_hole` opt-in apply or a returned patch ([#136], [M5-3]); registry hygiene across worktrees ([#137], [M5-4]); a reason beside `checkedFromSource` ([#138], [M5-5]); `type_of` inside a parameterized module's scope ([#139], [M5-6]); the `UnsolvedConstraints` restatement ([#145], [M5-7]); honest degraded hole goals ([#146], [M5-8]); and a worked validation-oracle example for `exports_of` ([#147], [M5-9]).
+  **Retrieval as server tools** ([#17], [M2-3]), whose design map is the forward pointer from § 10.
+  **The wave's measurement and publication companions**: the remaining [#83] arms ([M1-7]), the demo page ([#85], [M1-8]), and the tool paper ([#14], [M1-6]), for which this record is the design summary.
+  **Recorded and deliberately not taken**: `roots/list` for client-relative paths (needs a bidirectional transport); `Cmd_abort` in place of the lane's kill ladder; streaming progress and `since`-narrowing for `check_project`; and the restore variant of [#114], until a version gate exists for foreign `--agda-bin` toolchains.
+  **Agda as a library** remains the long-term plan for the batch lane's latency; the interaction lane already delivers persistent state and millisecond warm latency for queries, and nothing in this record depends on the library plan landing.

---

## 14.  Decision log

| # | Decision | Status | Evidence |
|---|---|---|---|
| 1 | Two lanes: batch `agda` per call for verdicts, a persistent `--interaction-json` child per root for knowledge; the lane never decides a verdict | Adopted ([#75], PR [#107]) | Interaction mode loads holed files where batch exits 42; 2.6 s per batch call against 1–3 ms per lane query |
| 2 | `get_goal` answers from the lane first, with injection as the stated fallback and the only path reporting binder visibility | Adopted ([#108], PR [#110]) | Byte-identical goals on the fixture matrix; no file mutation on the happy path |
| 3 | A batch tool may peek at a warm lane's stored load, never call it; a cold or stale lane leaves the response byte-identical | Adopted ([#108], [#115]) | Enrichment tests pin both shapes |
| 4 | `scope_at` omitted rather than approximated with grep | Adopted ([#75]) | No protocol command enumerates a scope |
| 5 | `success` is a function of the exit code alone; every verdict carries `verdict`, `command`, `project` | Adopted ([#72], [#76], PR [#95]) | Stand-in binary test; field report § 2 and § 6 |
| 6 | `fill_hole` tolerates only other open holes' `[UnsolvedInteractionMetas]` | Adopted ([#69], PR [#81]) | Verification fixture: `ok` on content `agda` rejects with exit 42 |
| 7 | `check_project` may turn a green gate red on failure evidence, never a red gate green | Adopted ([#78], PR [#98]) | The wrapper-ending-in-`echo` trap of § 3.5 |
| 8 | `answer = whatAgdaSaid <|> whatWeDerived`; the rule lives in the README's architecture notes | Adopted ([#100], [#106]; PRs [#105], [#116]) | Four module-name shapes; the audit's inventory |
| 9 | Structured diagnostics stay parsed from prose; the protocol retires segmentation, not extraction | Adopted ([#106], Measurement 1) | Six-class table: five prose-only, one surplus ([#115]) |
| 10 | Project resolution stays local, per call, echoed; a wrong tree is a refusal before spawn | Adopted ([#76], PR [#95]) | No Agda query exists; the environment note's reproduction |
| 11 | Relative paths resolve against the server's cwd, refused by name when they miss, never guessed | Adopted ([#101], PR [#102]) | The [#83] `-32603` datum; § 3.6's "worse than an error" |
| 12 | Foreign toolchains via `--agda-bin` and `--cwd`; registrations anchored per worktree | Adopted ([#103], [#133]) | fls modules resolve and write interfaces as the project's own `agda` does |
| 13 | Diagnostics as data: code, range, bounded full message, `involved`, root-cause order, capped with the total | Adopted ([#74], PR [#94]) | One fixture per § 5 class; field reports of 2026-08-29 and 2026-09-02 |
| 14 | Holes are Agda's interaction points, in every syntax and flavour, never in prose or comments | Adopted ([#71], [#73], PR [#88]) | Parity tests against batch Agda and the lane |
| 15 | Holes addressed by position; every answer re-anchors; both spellings at once rejected | Adopted ([#79], PR [#99]) | ADR 0001 adopts the re-anchored list wholesale |
| 16 | `checkedFromSource` withheld when the server muted the channel; degrade, not restore | Adopted ([#114], PR [#117]) | Reproduced in both lanes; grammar measured; the version-gate argument |
| 17 | Timeouts enforced by killing the process group; timeouts are values; defaults 300 s and 1800 s | Adopted ([#77], PR [#89]) | `FillTimeout` was unreachable; restore pinned on the timeout path |
| 18 | Corpus tools are pure in-memory lookups, registered only with `--corpus` | Adopted ([#11], PR [#44]) | 1.4 s load, 308 MB resident at library scale |
| 19 | A hand-rolled stdio transport (`initialize`, `tools/list`, `tools/call`) rather than the `mcp-server` package | Adopted; reason revisited | The GHC-floor reason expired; kept because it is small |

---

## References

+  **Issues**:

   + [#68] the wave, with verification results and sequencing,
   + its children [#69], [#70], [#71], [#72], [#73], [#74], [#75], [#76], [#77], [#78], [#79];
   + the follow-on fixes [#100], [#101], [#103], [#106], [#108], [#114], [#115], [#133];
   + the companions [#83] (M1-7), [#85] (M1-8), [#14] (M1-6);
   + the forward pointer [#17] (M2-3);
   + Milestone 5, [#134], [#135], [#136], [#137], [#138], [#139], [#145], [#146], [#147];
   + the ancestry [#10] (M1-2), [#11] (M1-3), [#66].

+  **PRs**: [#38] (M1-2), [#44] (M1-3), [#67] ([#66]), [#80] (the field report), [#81] ([#69]), [#82] ([#70]), [#88] ([#71], [#73]), [#89] ([#77]), [#94] ([#74]), [#95] ([#72], [#76]), [#98] ([#78]), [#99] ([#79]), [#102] ([#101]), [#104] ([#103]), [#105] ([#100]), [#107] ([#75]), [#110] ([#108]), [#116] ([#106]), [#117] ([#114]), [#118] ([#115]).

+  **Docs**:

   + [`agda-mcp/agda-mcp-interaction-lane.md`] the two-lane policy, the protocol as observed, lifecycle, economics,
   + [`agda-mcp/agda-mcp-ask-agda-audit.md`] the rule, the inventory, two measurements,
   + [`agda-mcp/agda-mcp-environment.md`] what is written where, which tree is checked, the operator checklist,
   + [`agda-mcp/agda-mcp-improvements-summary.md`] the wave, fix by fix, with PR numbers,
   + [`agda-mcp/README.md`] the tool contracts and response-field tables,
   + [`feedback/flrp-agda-mcp-improvements.md`] the field report and its verification addendum,
   + [`feedback/agent-case-for-corpus-proof-search.md`] the consumer-side case,
   + [`mcp-field-reports.md`] the session record,
   + [`adr/0001-proof-search-on-agda-mcp.md`] the search built on this server.

+  **Code map** (`agda-mcp/src/AgdaMCP/`):

   + `Agda.hs`: the batch subprocess, the kill ladder, `checkedFromSourceOf`, `progressChannelMuted`,
   + `Interaction.hs`: the lane registry and runner,
   + `Project.hs`: root resolution, the registry, the mismatch refusal,
   + `Holes.hs`: the hole model and the code-only view,
   + `Diagnostics.hs`: prose to structured diagnostics,
   + `Gate.hs`: which command is the gate,
   + `Corpus.hs`: the index,
   + `Tools/ProofState.hs`, `Tools/CheckProject.hs`, `Tools/LiveQueries.hs`, `Tools/Search.hs`,
   + `Server.hs`: the transport,
   + `agda-mcp/test/Main.hs`: tests,
   + `agda-mcp/test/resources/`: fixtures.

<!-- GitHub references: one definition per issue or PR cited above; PRs resolve to /pull/, issues to /issues/. -->
[#10]: https://github.com/formalverification/agda-native-air/issues/10
[#11]: https://github.com/formalverification/agda-native-air/issues/11
[#14]: https://github.com/formalverification/agda-native-air/issues/14
[#17]: https://github.com/formalverification/agda-native-air/issues/17
[#38]: https://github.com/formalverification/agda-native-air/pull/38
[#44]: https://github.com/formalverification/agda-native-air/pull/44
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
[#85]: https://github.com/formalverification/agda-native-air/issues/85
[#88]: https://github.com/formalverification/agda-native-air/pull/88
[#89]: https://github.com/formalverification/agda-native-air/pull/89
[#94]: https://github.com/formalverification/agda-native-air/pull/94
[#95]: https://github.com/formalverification/agda-native-air/pull/95
[#98]: https://github.com/formalverification/agda-native-air/pull/98
[#99]: https://github.com/formalverification/agda-native-air/pull/99
[#100]: https://github.com/formalverification/agda-native-air/issues/100
[#101]: https://github.com/formalverification/agda-native-air/issues/101
[#102]: https://github.com/formalverification/agda-native-air/pull/102
[#103]: https://github.com/formalverification/agda-native-air/issues/103
[#104]: https://github.com/formalverification/agda-native-air/pull/104
[#105]: https://github.com/formalverification/agda-native-air/pull/105
[#106]: https://github.com/formalverification/agda-native-air/issues/106
[#107]: https://github.com/formalverification/agda-native-air/pull/107
[#108]: https://github.com/formalverification/agda-native-air/issues/108
[#110]: https://github.com/formalverification/agda-native-air/pull/110
[#114]: https://github.com/formalverification/agda-native-air/issues/114
[#115]: https://github.com/formalverification/agda-native-air/issues/115
[#116]: https://github.com/formalverification/agda-native-air/pull/116
[#117]: https://github.com/formalverification/agda-native-air/pull/117
[#118]: https://github.com/formalverification/agda-native-air/pull/118
[#133]: https://github.com/formalverification/agda-native-air/issues/133
[#134]: https://github.com/formalverification/agda-native-air/issues/134
[#135]: https://github.com/formalverification/agda-native-air/issues/135
[#136]: https://github.com/formalverification/agda-native-air/issues/136
[#137]: https://github.com/formalverification/agda-native-air/issues/137
[#138]: https://github.com/formalverification/agda-native-air/issues/138
[#139]: https://github.com/formalverification/agda-native-air/issues/139
[#145]: https://github.com/formalverification/agda-native-air/issues/145
[#146]: https://github.com/formalverification/agda-native-air/issues/146
[#147]: https://github.com/formalverification/agda-native-air/issues/147
[#148]: https://github.com/formalverification/agda-native-air/issues/148

[#459]: https://github.com/ualib/agda-algebras/issues/459
[#507]: https://github.com/ualib/agda-algebras/pull/507
[`agda-mcp/agda-mcp-ask-agda-audit.md`]: ../agda-mcp/agda-mcp-ask-agda-audit.md
[`agda-mcp/agda-mcp-environment.md`]: ../agda-mcp/agda-mcp-environment.md
[`agda-mcp/agda-mcp-improvements-summary.md`]: ../agda-mcp/agda-mcp-improvements-summary.md
[`agda-mcp/agda-mcp-interaction-lane.md`]: ../agda-mcp/agda-mcp-interaction-lane.md
[`agda-mcp/README.md`]: ../../agda-mcp/README.md
[`feedback/flrp-agda-mcp-improvements.md`]: ../feedback/flrp-agda-mcp-improvements.md
[`feedback/agent-case-for-corpus-proof-search.md`]: ../feedback/agent-case-for-corpus-proof-search.md
[`mcp-field-reports.md`]: ../mcp-field-reports.md
[`adr/0001-proof-search-on-agda-mcp.md`]: 0001-proof-search-on-agda-mcp.md
