<!-- File: agda-native-air/docs/feedback/flrp-agda-mcp-improvements.md -->
<!--
  Provenance: written by a Claude Code session in ualib/agda-algebras after
  formalizing RP-2 of the FLRP program (agda-algebras issue #459, PR #507)
  with agda-mcp configured but unused; imported here verbatim (only this
  header comment adjusted).  Section 7 is an addendum written in this
  repository: it re-tests each claim against the server at commit 911ae18,
  as the document's own §0 requests, and records what reproduced, what did
  not, and what new defects the re-test uncovered.
-->

# agda-mcp: deficiencies observed and improvement proposals

Feedback from a Claude Code session that formalized RP-2 of the FLRP program in `ualib/agda-algebras` (issue #459, PR #507): two new Agda modules totalling ~1200 lines of literate Agda, roughly fifteen type-check iterations, plus four full-library builds.

Intended use: hand this to a session working on `agda-native-air`, which should **verify each claim against the current server before filing an issue** — several items below are secondhand or inferred, and one is from a note five days old.

## 0.  Provenance — read this first

Be skeptical in the right places.

+  **The single most important datum: I did not call agda-mcp once during the whole session**.  The server was loaded and its four tools were listed; I used `agda src/Path/To/Module.lagda.md` from Bash instead, every time. § 2 is my honest reconstruction of why, and it is the most actionable material here.
+  **Directly observed this session**: the tool surface (four tools, § 1), the server configuration in `.mcp.json`, the six classes of Agda error an agent actually hits (§ 5), and the workflow shape (§ 2).
+  **Secondhand**, from a memory note written five days earlier during unrelated work (`FLRP.WP-7`) in this repository: the server reports `errors: 0` and `holes: []` on a module with **unsolved metavariables**, and `{!...!}` was not recognized as a hole in a `.lagda.md` file.  That note flags itself as point-in-time; both claims need re-testing.
+  **Inferred, not verified**: the explanation in § 3.1 for *why* metas are tolerated (interaction-mode semantics).  Plausible and testable, but I did not test it.

## 1.  The current surface, as the client sees it

Four tools, each keyed on `filePath`:

| Tool | Description as advertised | Parameters |
| --- | --- | --- |
| `check_file` | Load/reload an Agda file and return all diagnostics | `filePath` |
| `get_diagnostics` | Diagnostic summary: error/warning counts, open holes | `filePath` |
| `get_goal` | Inspect the goal type and local context at a hole | `filePath`, `holeIndex` |
| `fill_hole` | Substitute a candidate term into a hole and typecheck | `filePath`, `holeIndex`, `candidate` |

Server config in the `.mcp.json` file of the `ualib/agda-algebras` project:

```
command: …/agda-native-air/main/scripts/run-server.sh
args:    --agda-flags "-i agda-dojang/agda --library-file=agda/libraries
                       -l agda-dojang -l standard-library -l agda-algebras"
         --timeout 600
env:     AGDA_ALGEBRAS_ROOT=<absolute path to this worktree>
```

The shape is right.  `fill_hole` in particular — propose a term, get it typechecked in place — is exactly the primitive an agent wants.  The problems below are about trust, coverage, and fit with how an agent actually edits.

## 2.  Why the shell won, in this session

Not a complaint about polish; a description of the decision an agent makes each time.

1.  **A verdict I cannot trust costs more than no verdict**.  If `check_file` can be green while `make check` fails, I must run the real checker anyway — so the MCP call is pure overhead.  Trust is the whole product; everything else in this document is secondary to § 3.1.
2.  **My edit unit is a whole module, not a hole**.  I draft 200–900 lines of statements-with-proofs, then check.  For that loop, `agda <file>` in one Bash call is already minimal: one call in, one focused error out.  To beat it, the MCP has to give me something the compiler's stderr does not — richer context at the error, or answers to questions I would otherwise grep for (§ 4).
3.  **Everything here is literate Agda**.  Every module in this repository is `.lagda.md` (ADR-004).  If holes are unreliable in literate files, then `get_goal` and `fill_hole` — the two tools with no shell equivalent — are unavailable exactly where I work, and the remaining two duplicate `agda <file>`.
4.  **The questions I actually had were about scope, not about goals**.  Reconstructing my session: roughly a dozen `grep` calls to answer "what does this module export", "what is the type of this thing", "which `≈sym` is in scope here", "does this name still exist after the rename in the other branch".  None of those has a tool.
5.  **I could not tell what it was doing**.  Which flags?  Same library file as `make check`?  Warm process or cold start?  Does it see my just-written bytes?  With no answers, the conservative move is the tool whose semantics I know exactly.

## 3.  Deficiencies

### 3.1  `check_file` green ≠ the project's gate green  — **P0**

*Observed (secondhand)*: `errors: 0`, `holes: []` reported for a module carrying unsolved metavariables; the strict build then failed with `[UnsolvedMetaVariables]`.

*Why it matters*: this is the difference between a tool an agent leans on and a tool an agent stops calling.  It also actively misleads: an agent that trusts it will commit, push, and discover the failure minutes later in CI.  It cost a full build cycle in the earlier session, and it is the reason my kick-off prompt for the next session says "feedback loop, not the gate".

*Likely cause (inferred)*: the server drives Agda's **interaction mode**, where unsolved metas are interaction points rather than errors — correct for an editor, wrong for an agent asking "would this pass?".

*Proposal*: make the batch verdict first-class.
+  Add `strict: boolean` (default `true`) to `check_file` / `get_diagnostics`; in strict mode, report exactly what `agda --safe <file>` would report, unsolved metas and constraints included, with the same error codes.
+  Return the resolved command line and flags in every response, plus a `verdict` field with an explicit meaning: `"equivalent-to: agda --safe <file>"` versus `"interaction-mode: metas allowed"`.
+  Never report `errors: 0` when metas or constraints are outstanding; report them as errors with their positions and types.

*Acceptance*: a module with an unsolved implicit is red in strict mode, and the response text names the meta and its type.

### 3.2  Literate Agda is second-class  — **P0**

*Observed (secondhand)*: `{!...!}` not recognized as a hole in a `.lagda.md` file.

*Why it matters*: this repository is 100 % `.lagda.md`, and it is far from alone; a literate-only repo makes `get_goal`/`fill_hole` dead code.  It also means position reporting has to be right: line numbers must refer to the `.lagda.md` file as the agent sees it (I edit by matching text, so a prose/code offset error is silently corrupting).

*Proposal*:
+  Treat `.lagda.md` / `.lagda.org` / `.lagda.tex` as first-class: extract fenced ```` ```agda ```` blocks, map positions back to the literate file, and detect holes inside code blocks.
+  Add a regression test per literate flavour: a file with prose above and below a hole, asserting `get_goal` finds it and that the reported line matches the literate file.
+  State the supported flavours in the tool descriptions, so a client can tell before trying.

*Acceptance*: `get_goal` and `fill_hole` behave identically on `M.agda` and on the same code embedded in `M.lagda.md`, with positions in literate-file coordinates.

### 3.3  No scope, type, or definition queries  — **P1**

*Observed (this session)*: I used `grep` for every scope question.  Three cost me a full iteration each:

+  an **`AmbiguousName`** for `≈sym`: a `Setoid` record field brought in by one `open`, versus a canopy lemma brought in through a four-level chain of module applications.  Agda's message listed both with their provenance; a tool answering "what does this name resolve to here?" would have been a one-shot fix.
+  a **`ClashingDefinition`** for `least`: I defined a local `least` in a `where` block, not realizing that `open IsMonolithᵍ public` in an imported module had already exported a field of that name.
+  a **`NotInScope`** for `MinimalNormal.HasMonolithᵍ`, because I had not yet added the new module to its barrel — preceded by a `ModuleDoesntExport` *warning* that a summary-style response would have shown me first.

*Proposal*: add read-only query tools, which is where an MCP genuinely beats the shell (grep cannot resolve re-exports or module applications):
+  `scope_at(filePath, line)` → names in scope with their fully qualified origins.
+  `resolve_name(filePath, line, name)` → candidates with provenance chains (the `AmbiguousName` case).
+  `type_of(filePath, line, expr)` and `normalize(filePath, line, expr)` → Agda's `C-c C-d` / `C-c C-n`, on an expression that need not be in the file yet.
+  `exports_of(module)` → the public surface, so barrel omissions are caught before compiling.
+  `definition_of(name)` → file and line, which is the single most common grep an agent runs.

*Acceptance*: each answers without requiring the client to edit the file first — the "check a term without committing to it" property is what makes them worth a call.

### 3.4  Diagnostics are prose, not data  — **P1**

*Observed (this session)*: every error I handled arrived as human-readable text; one `UnsolvedConstraints` message ran ~20 lines of internal meta names (`_𝑳.fst.Interp.to_127`) before the useful part.  Parsing that costs tokens on every iteration, and it makes automated retry loops brittle.

*Proposal*: return structured diagnostics alongside the text:
```
{ severity, code: "UnsolvedMetaVariables" | "AmbiguousName" | …,
  file, range: {startLine, startCol, endLine, endCol},
  message, involved: { expected?, actual?, candidates?[], metaTypes?[] } }
```
+  Cap the payload (`maxDiagnostics`, default ~10) and report the total, so a broken import list does not return a hundred cascading errors.
+  Sort by "most likely root cause" — scope errors before type errors, since the latter are usually downstream.

*Acceptance*: a client can branch on `code` without regex over prose.

### 3.5  No whole-project mode  — **P2**

*Observed (this session)*: the acceptance gate is `make check` over a generated `Everything.agda` (~300 modules, 10–20 minutes here).  I ran it four times, each as a backgrounded Bash job, and had to defend against a trap: a wrapper ending in `echo` reports shell exit 0 even when `make` failed, so the log must be grepped for `error:`.

*Proposal*: `check_project(target?, since?)` that runs the project's own gate, streams progress, returns the first error with context and a machine-readable exit status.  This is the call that would replace my Bash usage *entirely*, including the exit-code trap.

### 3.6  Opaque environment and project-root resolution  — **P1**

*Observed (this session)*: `.mcp.json` pins the worktree with an absolute `AGDA_ALGEBRAS_ROOT` and a relative `--library-file=agda/libraries`.  This repository's workflow is one git worktree per branch, so the config is per-worktree — and if it is ever stale, the server silently typechecks against a *different branch's* tree while reporting success.  For an agent that cannot see the discrepancy, that is a wrong answer, not an error.

Also observed: a directory `agda/` containing `defaults` and `libraries` appeared in the worktree root and showed up as untracked in `git status` (the repo gitignores `/.agda/`, with a dot, not `agda/`).  I could not determine whether the MCP setup, the Nix `agda` wrapper, or my own direct invocation created it — worth pinning down, since an untracked directory in a project root is one careless `git add -A` away from being committed.

*Proposal*:
+  Resolve the project root from the requested `filePath` by walking up to the nearest `*.agda-lib`, rather than from an env var fixed at server start; fall back to the env var and say which was used.
+  Echo the resolved root, library file, and flags in every response.
+  Keep generated state out of the project tree, or document exactly what is written where so it can be gitignored.

*Acceptance*: a response makes it obvious which tree was checked; pointing the client at a file in a different worktree either works or fails loudly, never silently succeeds against the wrong one.

### 3.7  No performance story  — **P2**

*Observed*: I never knew whether the server held a warm Agda process with cached interfaces.  A per-module `agda` run is seconds when `.agdai` files are warm and much longer cold; if the MCP is reliably faster, that is a real reason to call it — but an unadvertised advantage does not influence a decision.

*Proposal*: report `elapsedMs` and cache state (`interfacesReused: n`), and document the expected speedup over a cold `agda` invocation in the tool description itself, where the client actually reads it.

### 3.8  `holeIndex` is a fragile handle  — **P2**

*Observed*: `get_goal`/`fill_hole` take a 0-based hole index.  Indices shift whenever an earlier hole is filled or any hole is added, so a multi-hole edit becomes index bookkeeping — precisely the kind of state an agent loses track of between calls.

*Proposal*: accept a position (`line`, `column`) or a stable hole id as an alternative to the index; return the updated hole list after every `fill_hole` so the client can re-anchor.

## 4.  What would have made me call it, concretely

Three moments from this session where one tool call would have replaced several shell calls.  These make good acceptance tests, because they are real.

| Moment | What I did | What would have beaten it |
| --- | --- | --- |
| `IE→cfIE (ies i)` left unsolved metas, because `IE` is a defined function so implicits under it are never inferred | Read a 20-line `UnsolvedConstraints` dump, recognized the pattern from a prior session, added `{P = …} {𝑳 = …}` | Strict `check_file` naming the unsolved metas *with their types* and the blocking constraint, in structured form |
| `≈sym` ambiguous between a `Setoid` field and a canopy lemma | Read the provenance chains in the error, renamed my local binding | `resolve_name(file, line, "≈sym")` → two candidates with qualified names |
| "Does `Structure.centralizer-of-normal` still exist with that signature on the other PR's head?" | `git show <branch>:<file> \| grep -c` | `definition_of` / `type_of` against a specified revision or worktree |

## 5.  Error corpus from one real session

Every error class an agent hit while writing ~1200 lines here, as a test suite for structured diagnostics:

| Agda code | Trigger | What the ideal response carries |
| --- | --- | --- |
| `ModuleDoesntExport` (warning) | new module not yet in its barrel | the missing names, and that it is a *warning* preceding a hard error |
| `NotInScope` | consequence of the above | nearest candidates ("did you mean"), and the module that would export it |
| `AmbiguousName` | two `open`s bringing the same name | candidates with qualified names and provenance |
| `ClashingDefinition` | local name colliding with a re-exported record field | the origin of the pre-existing definition |
| `UnequalTerms` | missing `⊥-elim` | expected and actual, normalized, plus the source range |
| `UnsolvedConstraints` + `UnsolvedMetaVariables` | implicits under a defined function | each meta with its type and the constraint blocking it |

## 6.  Suggested priority for issue filing

+  **P0 — trust**: § 3.1 (strict verdict) and § 3.2 (literate Agda).  Until both land, an agent working in a `.lagda.md` repository has no reason to call the server, which is exactly what happened here.
+  **P1 — reach beyond the shell**: § 3.3 (scope/type/definition queries), § 3.4 (structured diagnostics), § 3.6 (root resolution and transparency).  These are where an MCP is strictly better than `agda` plus `grep`, rather than equal to it.
+  **P2 — economics and ergonomics**: § 3.5 (project mode), § 3.7 (performance reporting), § 3.8 (hole handles).

One meta-suggestion for whoever files these: put the *client-visible contract* in the tool descriptions themselves — which flags, which verdict semantics, which file flavours, what is cached.  An agent chooses tools by reading those two lines and nothing else, and in this session those two lines did not say the one thing that mattered, which is whether a green result means the build passes.

## 7.  Verification addendum — written in agda-native-air, 2026-07-29

Everything above this section is the original document, imported verbatim.  This section re-tests its claims against the server at commit `911ae18` (post-#67, Agda 2.8.0 pinned by the flake), as § 0 requests.  Method: built `agda-mcp` inside `nix develop .#backend`; drove a scripted MCP stdio session (`initialize` → `tools/list` → twelve `tools/call`s) with the same `--agda-flags` shape as the shipped `.mcp.json`, over five small fixtures importing only `Agda.Builtin` modules; cross-checked each server verdict against a direct `agda` run under the pinned toolchain.  The GitHub issues filed from this addendum are indexed by the tracking issue that references this file.

### 7.1  Verdict on each claim

| § | Claim | Verdict on `911ae18` |
| --- | --- | --- |
| 3.1 | `check_file` / `get_diagnostics` report green on unsolved metas | **Not reproduced**.  A module whose body is an unsolved `_` gets `success: false` and one `[UnsolvedMetaVariables]` error from `check_file`, and `errors: 1` from `get_diagnostics`. |
| 3.1 | Inferred cause: interaction-mode semantics | **Refuted**.  The server shells out to batch `agda <file>` per call; there is no interaction mode anywhere. |
| 3.1 | The underlying trust failure (green result, red gate) | **Confirmed, different locus**.  `fill_hole` reported `status: "ok"` for a candidate that leaves an unsolved implicit meta, while `agda` on the identical content exits 42 with `[UnsolvedMetaVariables]`; see § 7.2.2. |
| 3.2 | `{!...!}` not recognized as a hole in `.lagda.md` | **Confirmed, sharper cause**.  Hole detection matches only the literal four-character token `{!!}`; `{! !}`, `{! e !}`, and `?` are invisible in *every* flavour, and literal `{!!}` tokens in comments or markdown prose are counted (and fillable) as holes; see § 7.2.5–7.2.6. |
| 3.3 | No scope / type / definition queries | **Confirmed**.  The surface is the four core tools, plus three corpus-search tools only when `--corpus` is passed (it was not in the observed config). |
| 3.4 | Diagnostics are prose, not data | **Confirmed, plus a parser bug**.  Only the bracketed header line survives (the detail block with meta locations and types is dropped), and no diagnostic carries a line number because the extractor expects Agda's old `file:10,5-15` position format while Agda 2.8.0 emits `file:9.12-13`. |
| 3.5 | No whole-project mode | **Confirmed**. |
| 3.6 | Opaque environment / root resolution | **Confirmed**.  No response echoes flags, cwd, or resolved root; starting the server through `run-server.sh` enters the Nix shell, whose hook rewrites the checkout-wide `agda/libraries` from the env vars in effect at that moment — the stale-worktree hazard is real.  The stray `agda/` directory in the agda-algebras worktree root was not reproduced here and stays open. |
| 3.7 | No performance story | **Confirmed**.  Every call is a cold `agda` subprocess (as the README states); additionally `--timeout` is parsed but never enforced, and the `FillTimeout` status is unreachable code. |
| 3.8 | `holeIndex` is fragile | **Confirmed, worse than stated**.  Phantom token matches in comments and prose also occupy indices: in one fixture the token inside the header comment is hole 0 and the real hole is hole 1. |

### 7.2  Findings from the re-test

1. **`get_goal` reports the reporting macro's unsolved type, not the hole's goal**.  On the repo's own `agda-dojang/data/fixtures/Fixture01.agda`, hole 0 (`id x = {!!}`, goal `A`) returns `"goal": "(x₁ : _3 x) → _5 x x₁"`; fixtures with concrete goal `Nat` return the same shape, in both `.agda` and `.lagda.md`.  The raw marker block shows the `reportGoalCtx` macro itself emitting the bad goal (context entries are correct), so the defect is in the agda-dojang reflection layer as driven by batch `agda` 2.8.0.  The 2026-04-03 M1-4 transcript shows the same shape at Fixture01 hole 1 — where the driving agent explained it away as "mutual dependency between holes" — so this is long-standing, not a fresh regression.  CI cannot see it: the unit tests assert `parseGoalContext` on hand-written marker text, and no test asserts an end-to-end goal value.
2. **`fill_hole` reports `ok` for candidates that leave unsolved metas**.  With `implicitOnly : {n : Nat} → Nat` in scope and two holes open, `fill_hole(hole 0, "implicitOnly")` returns `status: "ok"`, but `agda` on the identical patched content exits 42 with `[UnsolvedMetaVariables]` (plus `[UnsolvedInteractionMetas]` for the other hole).  Cause: the tolerance check that is meant to excuse *other still-open holes* is a blacklist over error tags that does not fail on `[UnsolvedMetaVariables]` or `[UnsolvedConstraints]` (`agda-mcp/src/AgdaMCP/Tools/ProofState.hs`).  This is the § 3.1 trust failure, live on HEAD, and it is exactly the FLRP "implicits under a defined function" pattern from § 4.
3. **Diagnostics carry no positions under Agda 2.8**.  Every diagnostic in the session came back with `severity` and `message` only; the line-number extractor splits on `,` where Agda 2.8.0 uses `.` between line and column.
4. **`--timeout` is inert**.  The flag parses into config that nothing reads (`TODO` in `AgdaMCP.Agda.runAgda`); the observed `.mcp.json` passes `--timeout 600` expecting an effect.
5. **The hole model is the literal token `{!!}`**.  A fixture with four Agda-visible interaction points (`{!!}`, `{! !}`, `{!zero!}`, `?`) yields `holesCount: 2` — the real `{!!}` plus the `{!!}` mentioned in the header comment.  A `.lagda.md` whose only hole is `{! zero !}` yields `holes: []` while `get_diagnostics` simultaneously reports the `[UnsolvedInteractionMetas]` error, and `get_goal` answers "Hole index 0 not found" — the § 0 memory note's `holes: []` observation, reproduced.
6. **`fill_hole` validates substitutions into markdown prose**.  In a `.lagda.md` whose closing prose mentions `{!!}` verbatim, `fill_hole` on that prose token returned `status: "ok"` (the substituted text is invisible to Agda, and the file's real hole was excused by the tolerance heuristic).  The verdict is meaningless for a non-code location, and an agent trusting it would edit documentation believing it made proof progress.

### 7.3  Reading of § 6 after verification

The P0 re-ranks as follows: trust remains the whole product, but the two P0 fixes are now (a) truthful verdicts from `fill_hole`/`get_goal` — § 7.2.1 and § 7.2.2 — and (b) a real hole model with literate awareness — § 7.2.5 and § 7.2.6 — while § 3.1's `check_file` half becomes "make the already-strict batch verdict explicit and contractual" rather than "fix a green-on-red bug".  The § 6 meta-suggestion (put the contract in the tool descriptions) is confirmed by inspection: the shipped descriptions are one-liners that state none of flags, verdict semantics, supported flavours, or caching.
