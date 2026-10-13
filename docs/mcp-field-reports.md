# agda-mcp field reports

> **Frozen on 2026-10-12** ([#252]).  This file holds the field reports
> committed through 2026-10-11, one section each, and takes no more.  Reports
> written since, and eight sections of 2026-10-11 and 2026-10-12 that never
> reached this file, are files of their own under [`field-reports/`], each
> submitted as a pull request by the session that wrote it; that directory's
> README says how.  Nothing below this note has changed, so every link to a
> section of this file still works.

[#252]: https://github.com/formalverification/agda-native-air/issues/252
[`field-reports/`]: field-reports/README.md

Session-by-session notes on using the agda-mcp server for real work, kept per the
agda-algebras `CLAUDE.md` standing instruction.  Reports are appended, newest last,
and are meant to be evidence in both directions: where the server helped, and where
the CLI loop was simply better.

## 2026-08-21 — agda-algebras, issue #268 (M4-2 docstring pass)

**What the session did**.  Built `scripts/python/docstring_audit.py`, a
literate-and-layout-aware audit of prose coverage over the agda-algebras corpus,
and documented one exemplar module.  Almost no Agda was written; the work was
Python plus Markdown prose; so the hole-driven loop the standing instruction is
really about (`get_goal` / `fill_hole` / `refine`) never came up.  Saying so
plainly rather than manufacturing a use for it.

**Tools used**.  `exports_of` (3 calls), `check_file` (2 calls).  Nothing else.

**`exports_of` was the most valuable thing in the session**, and not for the
obvious reason.  The audit tool has to enumerate the public definitions of a
`.lagda.md` module from text alone.  This is exactly the kind of parser that gets
things slightly wrong and makes mistakes that pass under the radar.  `exports_of`
with `module: ""` returns the file's own top-level exports, which makes Agda
itself the oracle: run the tool, run `exports_of`, diff the name sets.

Three modules of deliberately different shape:

+  `Setoid.Homomorphisms.Basic`: 15 exports vs 14 reported, the only difference
   being the record constructor `mkIsHom`, which the tool deliberately attributes
   to its record.
+  `Setoid.Varieties.Closure`: 33 vs 33, exact, with 8 `private` blocks available
   to get wrong.
+  `Classical.Structures.Semigroup`: 4 top-level values plus the nested module
   `Semigroup-Op`, all matched, with the submodule's members correctly qualified
   and its `private` members correctly dropped.

That turned "the parser looks right on the files I read" into a checkable claim,
and it caught the class of bug (an empty inline `where` block silently swallowing
the rest of a module) that spot-checking would not have.

**Suggestion for the docs**: the `module: ""` convention is the key to this use
and is easy to miss in the tool description; it is currently one clause in a long
paragraph.  A worked "validate an external tool against Agda's own scope information"
example would sell the capability better than the API description does.

**`modules` vs `exports` is a genuinely good design choice**.  Having nested
modules returned in a separate array rather than mixed into `exports` is what let
the comparison distinguish "`Semigroup-Op` is a namespace" from "`Semigroup-Op` is
a value", without special-casing.

**`check_file` did exactly what was needed with no ceremony**.  Two calls to
confirm a prose-only edit left `Setoid.Algebras.Basic` type-clean.  The `verdict`
echo — the equivalent CLI command, plus the statement that success is read from
the exit code and never from message text — is worth more than it looks: it meant
the result could be quoted in a PR body as a checkable claim rather than an assertion.

**Cross-checkout resolution worked, and it mattered**.  The session ran in a git
worktree (`worktrees/268-m4-2-docstring-pass`) while the server's own cwd is the
agda-native-air checkout.  `rootSource: "nearest-agda-lib"` picked up the
worktree's `agda-algebras.agda-lib` and reported the resolved `root`,
`includePaths` and `selectedLibraries` in every response.  That is precisely the
failure mode agda-algebras' `CLAUDE.md` warns about for the `nix develop` `agda`
wrapper, which hard-codes `--library-file` for the shell's own worktree and
misresolves any other one.  The MCP server sidesteps it, and the echo makes it
verifiable rather than hoped-for.  This is a real advantage over the CLI in a
worktree-per-branch repository and is under-advertised.

**Costs, for calibration**.  First load per root ~4 s; a switch to another file
under the same root re-loads, and one heavy module (`Setoid.Varieties.Closure`)
took ~18 s.  Consecutive queries about the same file are instant.  For the access
pattern here (three files, one question each) nearly every call paid a full load,
so the wall-clock was load-dominated.  That is inherent to the pattern, not a
defect, but it is worth knowing that a "sample N modules and compare" validation
loop costs roughly N loads.  A batch form of `exports_of` taking several
files would turn this specific use case from ~25 s into one load.

**Where the CLI would have been equal or better**.  Nothing in this session, but
only because the session barely touched Agda.  For the one type-check, `agda <file>`
inside the existing `nix develop` shell would have been just as good and
marginally faster; the MCP call won on the structured `verdict` rather than on
capability.

**Verdict**.  Used narrowly, and earned its place on `exports_of` alone.  The
enumerate-and-diff-against-Agda technique generalizes to any corpus tool over an
Agda library, and has been written up as a project skill
(`writing-a-corpus-linter`) so it is not re-derived.

---

## 2026-08-22 — agda-algebras #539 (M4-2a docstrings), prose-only change

**Tools used**: `check_file` twice.  Nothing else, and that is the report.

The task was a documentation pass over nine `.lagda.md` modules: prose blocks
above existing code fences, plus nine module headers.  No Agda was written, no
hole was opened, so the hole-driven loop the server exists for had nothing to
drive.  What was needed was a build verdict, twice, and the CLI for the rest.

**What `check_file` did well**.  The two barrel modules (`Setoid.Homomorphisms`,
`Setoid.Algebras`) transitively import all nine changed files, so two calls
covered the whole change.  `project.rootSource: "nearest-agda-lib"` resolved to
the *worktree* the file lives in, not to the server's own checkout, and the echoed
`library.root` said so explicitly.  That matters here: the `agda` on `PATH` inside
`nix develop` is a wrapper that hard-codes `--library-file` for the worktree the
shell was entered from, so a session working in a different worktree from the same
shell resolves modules to the wrong tree.  Reading the resolved root back out of
the response is a real safeguard the CLI does not offer, and it is the one thing
that made the MCP call worth preferring over `agda <file>` for the first check.

`checkedFromSource` earned its keep too.  The first call reported `true` (17.8 s,
a real compile); the second reported `false` in 2.3 s, correctly telling me it had
reused the interface the first call had just written rather than pretending to a
second independent verification.  A CLI invocation gives no such signal.

**Where the CLI was genuinely better**.  For the per-file sweep.  Nine modules,
one line each, is one shell loop:

    for f in $(git diff --name-only -- 'src/*'); do agda "$f" || echo "FAIL $f"; done

Nine `check_file` calls would have been nine round-trips returning nine ~2 KB
JSON envelopes, ~95% of which is the same echoed `project` and `verdict` block.
The echo is the right default for a single authoritative check and the wrong
shape for a sweep.  Same conclusion as the previous report's "batch `exports_of`"
note, from the other direction: the missing affordance is *many files, one call*,
and it is missing on `check_file` as well.

Also CLI-only: `make check`, the whole-library gate.  Correct — that is a build,
not a query — but worth stating that the final gate of every session in this
repository is outside the server.

**Nothing was awkward.**  No timeouts, no `rootMismatch`, no surprises.  The
server was simply mostly irrelevant to a prose task, which is the honest finding
rather than a complaint.

**One suggestion with a concrete use case.**  A `filePaths: [...]` form of
`check_file` returning one verdict per file plus a single shared `project` block
would have replaced the shell loop and kept the resolved-root safeguard for all
nine files instead of two.  Verifying "every file I touched still compiles" is
the most common shape of an end-of-session check, and it is currently the one
shape the CLI does better.

## 2026-08-24 — fls M1-3 (Leios.Types, new module of records + derive-DecEq)

Server not connected: ToolSearch "+agda" returned no tools at session
start, so the whole session ran on the CLI workflow.  The task was a
new module of four record/alias types with derived DecEq instances —
no proofs, no holes worth driving.  The CLI loop was genuinely
efficient here: one `agda <file>` run typechecked the module on the
first attempt (including derive-DecEq over a `ℙ ℕ` field), and the
full-closure gate ran once in the background.  Even with the server
connected, hole-driven development would have added little for this
shape of work; where MCP tooling would have helped is instance-scope
checking (whether `DecEq Slot` reaches a telescope's `using` clause)
without a full load — that was reasoned out by reading sibling
modules instead.

## 2026-08-24 — fls M1-4 (Leios protocol parameters, wide-record extension)

Server not connected: ToolSearch "+agda" returned no tools, so the CLI
workflow carried the session.  The work was a wide, mechanical edit —
nine fields added to `PParams` and echoed in five companion positions —
plus one change of a predicate's TYPE (`paramsWellFormed` gained a
conjunct), which ripples to every pattern match on it.

The CLI loop was the right tool; holes would have added nothing to this
shape of work.  Three things paid off, none of them MCP-shaped.  (1)
Warming the full `Ledger.Dijkstra` closure in the background BEFORE the
first edit, so later runs re-checked only the 73 affected modules
instead of the whole library.  (2) Splitting the change into two
patches each of which typechecks on its own, so a failure would
localize to one of them — and so each commit is green.  (3) A
throwaway Python script asserting that each of the nine field names
appears in each of the eight places it must (record, update record, two
group predicates, `applyPParamsUpdate`, two positivity lists, prose).
That third check matters most: a field silently missing from
`modifiesSecurityGroup` typechecks perfectly, so the typechecker cannot
catch it and neither would any MCP tool — the check has to come from
outside the type system.

Where a server would have helped: a cheap "does this name resolve, and
at what type" query.  Two scope questions had to be settled by reading
sibling modules — whether `Data.Rational`'s `_<_` is reachable as
`ℚ.<` after `open import Data.Rational as ℚ using (ℚ)` (answered by
`Dijkstra/Specification/Ratify.lagda.md`, which does exactly that and
then writes `ℚ.≤?`), and whether `fromUnitInterval` is re-exported by
`Ledger.Prelude.Numeric` (answered by reading that module's `public`
re-export).  Both were right, but the evidence was circumstantial until
a 90-second full-module run confirmed them.  A `resolve_name` /
`scope_query` against a loaded module is the smallest tool that would
have earned its keep here.

## 2026-08-29 — agda-algebras, FLRP RP-3 (issue #460, PR #561)

Session shape: three new/extended literate modules (a Classical maximality record, a 200-line catalog section with a two-directional OrderIso construction, a 500-line dossier module), plus a mid-session repair of a core definition (Statement-C) with two downstream consumers.

+  **Tools used**: `check_file` throughout (about ten calls); `check_project` not needed (the Makefile gate ran in a background shell for the commit-level checks); `get_goal`/`fill_hole`/`exports_of` not used this session.
+  **What worked**: `check_file` from a server rooted in a different repo resolved this worktree via nearest-agda-lib with zero configuration, exactly as advertised, and the `project` echo made that verifiable at a glance.  Warm-cache turnaround was 7 to 35 s per call against roughly ten minutes for the full `make check`, so the loop was: write a whole block, check, read structured diagnostics, patch.  Five errors total across the session, each diagnosed from one call: an AmbiguousName with both candidates listed, two UnsolvedMetaVariables batches whose `involved.metaTypes` payload identified the implicit-endpoint disease (the session-memory "inline or forward endpoints" fix applied mechanically), one NotInScope with did-you-mean candidates, and one stray underscore whose 1-char range pinpointed an argument that vanishes under reduction (a constant meet on Fin 1).
+  **What was awkward**: the UnsolvedConstraints diagnostic duplicates the meta dump at great length (a hundred lines for six metas); the UnsolvedMetaVariables location list beside it was the useful part.  Not a blocker.
+  **Honest efficiency note**: hole-driven development (`get_goal`/`fill_hole`) was not exercised; the proofs were designed in full from reading the sources first, and batch `check_file` with structured diagnostics was efficient for that style.  The one place holes would have helped (learning the exact component order of the interval equality pairs) was resolved faster by reading `Order.Interval` than a load would have taken.  For plumbing-heavy sessions like this one, write-then-check with this tool is genuinely the right loop; the CLI would have cost the same checks with worse diagnostics.

**Addendum (2026-08-30)**: the fuller consumer-side assessment this report sketches (what the mcp already changes for an agent, the retrieval gap, and the case for corpus proof search with design requirements) is written up as `docs/feedback/agent-case-for-corpus-proof-search.md`, at William's request.

## 2026-08-30 — agda-algebras #562 (IsSimple, nonabelian-simple interface, certified A₅)

Tools used: `check_file` (about a dozen calls, the whole development loop); `ToolSearch` to load the server per the project standing order.  Not used: `get_goal`, `fill_hole`, `type_of`, `exports_of`, `resolve_name`.

What worked.  `check_file` from the mcp was strictly better than the CLI loop for per-module gating: no `nix develop` startup on every check, structured verdicts with real exit codes, and the nearest-agda-lib root resolution correctly checked this worktree even though the server's cwd is another repo entirely.  Every new module this session (six of them, including a 50 KB generated data module) went green on the first `check_file`, so the batch tool WAS the development loop.

What was awkward.  (1) `checkedFromSource:false` right after editing a file reads as "stale check" until you remember interfaces are content-hashed; a repeated call after `touch` returned an identical `elapsedMs`, which looked like a cached response rather than a re-validation.  A one-word field saying WHY the source was not re-checked (interface-hash match) would kill the doubt.  (2) No profiling lane: the session's one measurement task (brute-force `Associative?` at 60³ vs the faithful-action route: 72 s / 13.8 GB vs ~9 s / 0.9 GB) had to go through `/usr/bin/time` + CLI agda, since the mcp exposes neither `--profile` nor memory.

Honest assessment of hole-driven development: unused this session, and rightly so.  The modules were fully designed during a long reading pass (levels, record shapes, decidability routes) before the first line of Agda was written; with the design settled, whole-module drafts checked green immediately and holes would have added round trips.  Hole-driven pays when the goal types are genuinely unknown; here the type questions were answered by reading source, not by querying goals.

## 2026-08-31 — agda-algebras #564 (simple algebras: congruence-level notion + group-side equivalence)

+  **Tools used**: `check_file` only (six calls across four files).  `get_goal`/`fill_hole`/`type_of` went unused: the session designed both proof directions on paper from reading the existing modules (the round-trip lemmas of `Classical.Structures.Group.Congruences` supplied every witness), and three of the four edited files were green on the first `check_file`.  The one failure was a missing `proj₂` import, which the structured `NotInScope` diagnostic with its `involved.candidates` list identified without reading Agda prose.
+  **What worked**: `check_file` as the per-module gate beat the CLI loop decisively on latency (2–13 s per call against ~20–30 s for `nix develop --command agda` including shell startup), and the `project` echo confirmed each call resolved the *worktree's own* `.agda-lib` (this repo has a known wrapper hazard where a shell entered from one worktree miscompiles another; the echo made that a non-issue to verify).
+  **What was not exercised**: hole-driven development.  Honest assessment: for work that composes existing, well-understood machinery, reading the modules first and writing complete definitions was more efficient than driving holes; the hole tools earn their keep when the goal types are not predictable in advance, which never happened here.
+  **Friction**: none observed; no timeouts, no lane restarts.

## 2026-08-31 — fls #1299 hotfix (Milliseconds alias restoration)

ToolSearch "+agda" returned no tools (server not connected), so the CLI
workflow was used.  The edit was six mechanical lines (restore a type
alias, retype three record fields), so hole-driven development had no
role even in principle; the entire Agda cost was the final gate, a full
Ledger.Dijkstra closure check in a fresh worktree of a colleague's PR
branch.  One technique worth keeping: copying `_build` from a sibling
worktree seeded the fresh worktree's interface cache, and the
content-keyed hashes made the nominally cold 98-module gate finish in
minutes.  Nothing here argues for or against agda-mcp; it simply was
not the bottleneck.

## 2026-09-01 — agda-algebras #566 (Entry 4 no-go + ᵈ-rewire), Claude Fable 5

Worktree: `agda-algebras/worktrees/566-flrp-entry4-em-nogo`.  Tools used: `check_file`, `get_diagnostics`, `fill_hole`.

+  **Setup friction, then a clean fix**.  First `check_file` failed with `LibraryError: Library 'agda-algebras' not found` — the server's `agda/libraries` registry (this repo's checkout) had agda-dojang, stdlib, and an fls worktree, but no agda-algebras entry, so the root resolved correctly (`rootSource: nearest-agda-lib`) while the `-l agda-algebras` selection had nothing to bind to.  Appending the worktree's `.agda-lib` path to `agda/libraries` fixed it immediately.  Two observations: (a) the error surfaced the exact remedy in its own text, which is good; (b) the registration is per-worktree and will go stale when the worktree is deleted after merge — a per-repo (or glob) registration story would remove this recurring step.  The stale-entry failure mode is untested.
+  **The verdict echo earned its keep**.  `command`, `project.registeredLibraries`, and `rootSource` made the misconfiguration diagnosis a ten-second read instead of a guessing game.  This is the difference from the last session's opaque `rootMismatch` dead end.
+  **Warm checks changed the loop**.  6–8 s per `check_file`/`fill_hole` on a file whose dependencies were cached, against ~2–3 min for a cold `nix develop --command make check` round.  Three module-level check cycles (KurzweilInterval twice, Closure.Basic once as the apex consumer) were enough to land two commits whose full-library gates then passed first try.
+  **`fill_hole` diagnosed the one real bug**.  The `UnsolvedConstraints` payload (`_x_305 0F = x 0F …` blocked metas, with `metaTypes` spelled out) identified a non-pattern unification: where-bound subgroup-closure proofs passed to `mkIsSubgroup` left an implicit element meta because the local predicate unfolds under application.  The known cure (eta-expand the implicit at the call site) applied cleanly.  Structured `involved.metaTypes` beats scraping the message text.
+  **Friction worth fixing**: `fill_hole` restores the file byte-for-byte even when the candidate is accepted, so every accepted candidate has to be re-applied by hand in a second edit step; an opt-in `apply: true` (or a returned patch) would remove a whole editing round per hole.  Minor: hole goals in `get_diagnostics.holes` showed `"?"` rather than the goal type (lane had no matching load yet), so a `get_goal` per hole would have been needed had the terms not been pre-designed.
+  **Net**: genuinely faster than the CLI loop this session, and the first session where the server, once registered, was the primary development instrument rather than a bystander.

## 2026-09-01 — fls [LLF1-3] #1301: the Leios primitive types module

Task shape: a new types-only literate module (two records, a type alias, two
`derive-DecEq` incantations), four new abstract fields on `CryptoStructure`,
two downstream mirrors, registration.  No proofs; no holes arose naturally.

Tools used: `check_file` ×6 (Crypto, Foreign/Crypto/Structure, the new Types
module, a throwaway consumer probe twice, and
`formal-ledger-test/…/LedgerImplementation`), `type_of` ×2 (one fixity parse
error of my own; one answer that exposed the lifted top-level scope, below).

What worked well:

+  **Per-file project resolution.**  `check_file` resolved the right
   `.agda-lib` for BOTH subprojects with zero configuration — the main
   `formal-ledger` tree and `formal-ledger-test` (its own library, depending
   on the first).  The test library is the surface only Hydra checks in CI,
   so a pre-push local check of it is real risk reduction, and the CLI
   equivalent means hand-assembling `-i` flags.
+  **The echoed verdict and command.**  Exit-code-derived success plus the
   exact equivalent command line made green trustworthy, and showed the
   server's binary was the same nix-store agda as the shell's, so the MCP
   runs and the final CLI gates shared one interface cache; nothing was
   checked twice.
+  **Background completion.**  The 173 s LedgerImplementation check moved
   itself to the background and notified on completion; no babysitting.

What was awkward:

+  **Top-level queries sit OUTSIDE a parameterized module.**  `type_of` at
   file top level sees the lifted signatures (`Vote : (cs : CryptoStructure)
   → Type`), so "does instance search find the derived `DecEq`?" cannot be
   asked from there, and a types-only module has no natural hole to ask from
   inside.  The workaround was a throwaway consumer module (`open import
   …Types HSCryptoStructure`; probe `_≟_` on each type) plus `check_file` —
   decisive, but two extra ~30 s runs.  A mode that runs queries inside the
   module (parameters generalized, as a hole would) would answer this in
   milliseconds.
+  **First contact with a literate file costs a full load** (~28–30 s here)
   even when a batch check of the same state just ran; consecutive queries
   were then instant (90 ms).  Fine once known; it rewards batching one's
   questions per file.
+  One self-inflicted `NoParseForApplication`: `_≟_` and `_,_` are both
   level 4, so a tuple of comparisons needs parentheses; the error surfaced
   cleanly with the operator table.

Net, honestly: for THIS task the inner loop was roughly a wash with per-file
CLI agda — the module checked green on the first pass, so MCP round trips
bought little over one CLI run.  The genuine wins were the
`formal-ledger-test` resolution (no flag archaeology for the Hydra-only
surface), the fast warm-lane probe loop, and the self-backgrounding long
check.  The final gates ran via CLI per project rule and were pure
confirmation.

## 2026-09-02 — agda-algebras #522/#527 (Kurzweil surjectivity proved, KN theorem closed), Claude Fable 5

Worktree: `agda-algebras/worktrees/522-flrp-kurzweil-surjectivity` (stacked on the #566 branch).  Tools used: `check_file` only, ~15 calls.

+  **The loop this session was write-big, check-fast**.  The main deliverable was a 737-line module (`PowerCollapse`) composed in one pass from a written-out proof plan, then debugged through `check_file` at 6–12 s per round: six errors total (a record-member access shape, an operator-fixity parse, one lemma direction, one non-invertible `filter` unification, two missing imports), each localized instantly by the structured diagnostic.  No holes were used at all this time; with a complete term-level plan, hole-driven development would have added rounds, not removed them.  The honest comparison: `check_file`'s value over the CLI here was latency (6 s vs ~40 s cold `agda` on this dependency spine) and the `involved.actual/expected` fields, which made the fixity bug (`Dec` where a carrier was expected) a ten-second read.
+  **Registry hygiene**: replaced the stale 566-worktree line in `agda/libraries` with the 522 worktree before starting; the earlier session's lesson (per-worktree registration) held with no surprises.  One wrinkle: the registry had silently lost its `formal-ledger` line at some point; restored it defensively.  A per-repo glob registration would eliminate this whole class of bookkeeping.
+  **One instance of the tool catching a would-be silent hazard**: `checkedFromSource:false` on a consumer module made it visible that the file was served from cache after its dependency changed, prompting an explicit re-check of the edited spine rather than trusting staleness.
+  **Friction**: none new.  The `fill_hole` re-apply friction reported last session did not arise (no holes).
+  **Net**: the MCP served as a fast typed linter over a plan-first workflow; for a session dominated by one large novel proof, that is exactly the right division of labor, and it was faster than the CLI loop.

## 2026-09-04 — agda-algebras #572 (Parachute record, the lattice it presents, loose ends), Claude Fable 5.1

Worktree: `agda-algebras/worktrees/572-flrp-parachute-modules-improvements`.  Tools used: `check_file` only, four calls (one probe of the unchanged module to confirm the server's root, then one per edited spine: the lattice module, and `FLRP.Reductions`, which pulled the two other consumers).

+  **Root binding needed no registry surgery this time**: `rootSource: nearest-agda-lib` resolved the worktree's own `.agda-lib`, and the `project` echo made that verifiable in one call, which is exactly the check the kick-off asks for before any Agda is written.
+  **No holes, no goals**: the task was a refactor with a known target shape (a record replacing a five-parameter telescope), so the loop was edit, then `check_file`.  Every edit checked green on the first pass (the lattice module in 7 s, the consumer chain through `FLRP.Reductions` in 24 s), so the MCP's contribution was latency and a structured verdict, not diagnosis.  A per-file CLI loop would have been equally efficient; the honest statement is that `check_file` was a convenient typed `agda` with no context switch, no more.
+  **What the MCP could not do, and the CLI did**: the profiling.  The kick-off's cost constraint is answered by `agda --profile=internal`, for which there is no MCP surface, so the measurement loop (delete the `.agdai`, profile twice, compare phases) ran in Bash, and the comparison of two record shapes (a scratch copy of the module with a different header, profiled alongside) was pure CLI as well.  A `profile_file` tool returning the phase table as JSON would have made that comparison a two-call affair and kept the numbers out of log-scraping.
+  **Harness friction, not MCP friction**: the auto-mode classifier blocked `git reset --hard` on the sibling worktree, the `--force-with-lease` push, and a Python heredoc that rewrote the edited module; the Edit tool did the file edits instead, and the branch surgery is left for William.
+  **Net**: for a header-level refactor under a measured cost constraint, the MCP was a wash against the CLI on the type-checking side and absent on the profiling side.  Its one real save was the root confirmation.

## 2026-09-08 — fls PR #1308 review (starting account balance intervals), Claude Fable 5.1

Worktree: `fls/worktrees/review-1308` (detached at the PR head).  Tools used: `get_diagnostics`, one call.  Nothing was written; this was a review, so the batch gate was the only Agda run needed.

+  **The server cannot check fls at all right now**.  The one probe failed in 75 ms with `AmbiguousTopLevelModuleName`: the server's cwd is `fls/master`, its `project` echo bound the review worktree's `.agda-lib` correctly (`rootSource: nearest-agda-lib`), but Agda still saw both `master/src` and `review-1308/src` for the same module name.  Underneath that, the registered-libraries list is agda-native-air's (`agda-dojang`, `standard-library-2.3`); fls needs agda-sets, agda-stdlib-classes and agda-stdlib-meta, none registered, so a resolved root would have failed on the first import anyway.  The structured failure was clear and cheap; it just answered "not this project".
+  **The CLI loop did the verification**: `_build/` seeded from master, then `nix develop --command agda src/Ledger.lagda.md` in the background while the diff, the cardano-ledger patches and the CIP text were read.  For a review, where the question is one green-or-red verdict on the whole closure rather than a goal-by-goal loop, the CLI is the right instrument regardless of the server's state.
+  **Net**: no time lost beyond one probe; no gain either.  A per-project libraries file, or the server picking up the flake's registry for fls, is the missing piece.

## 2026-09-08 — fls PR #1313 review (SNAP moved to the end of EPOCH), Claude Fable 5.1

Worktree: `fls/worktrees/carlos/epoch-dijkstra` (the PR branch, inside the flake shell; `.mcp.json` now points the server at `${PWD}` with `agda src/Ledger.lagda.md` as the check command).  Tools used: none of the agda-mcp tools; the server was connected but never called.

+  **Why not**: a review needs one green-or-red verdict on the whole closure plus a handful of "does this alternative compile" experiments.  The verdict ran as `agda src/Ledger.lagda.md` in the background (229 modules, 19m51s, exit 0, no warnings) while the diff, the cardano-ledger patch and the sibling modules were read; the experiments ran in a scratch copy of `src/ + src-lib-exts/ + formal-ledger.agda-lib + _build/` so the PR worktree stayed byte-identical.  The server holds one root per project and binds it from cwd, so pointing it at the scratch copy would have meant a second registration; the CLI needed only `cd`.
+  **Two places the MCP would have shortened a round**.  (1) A `rewrite`-based proof of `Γ≡Γ'` failed with "rewrite did not apply" because the where-bound abbreviation `ls'₁` reduces away once the goal normalises; a `get_goal` on that clause would have shown the normalised goal in seconds instead of a 90 s batch round and a read of the error dump.  (2) "Does stdlib 2.3 have `cong₃`?" was answered by grepping the nix store; `type_of "cong₃"` in the module's scope is the right instrument and would have been one call.
+  **Not verified this session**: whether the server can actually load fls under the new `.mcp.json`.  The 2026-09-08 #1308 entry above found it could not; the configuration has since changed and nobody probed it here.  Next fls session that writes Agda should run one `check_file` first and record the answer.
+  **Net**: for this review the CLI loop was strictly more efficient; the MCP's absence cost nothing, and its presence would have saved perhaps three minutes on the two diagnostic questions.

## 2026-09-08 — fls #1274 (batch-threading UTxO invariants for LEDGER-pov), Claude Fable 5.1

Worktree: `fls/worktrees/1274-dijkstra-batch-threading-utxo-invariants` (branch cut from the top of the Dijkstra PoV stack, inside the flake shell).  Tools used: `check_file` only, nine calls; `get_goal`, `fill_hole`, `type_of` and `normalize` were not called.

+  **The server can check fls again**.  Contrary to the #1308 entry, `check_file` bound the worktree's own `.agda-lib` (`rootSource: nearest-agda-lib`, includes `src` and `src-lib-exts`) and loaded the whole Dijkstra spine off the `_build/` seeded from a same-commit sibling.  Its registered-libraries list is still agda-native-air's, and its `agda` binary is `~/.cache/fls/agda-root/bin/agda`, not the flake's; it works because fls vendors agda-sets, stdlib-classes and stdlib-meta under `src-lib-exts`, which the `.agda-lib` puts on the include path.  Interface files written by the two 2.8.0 binaries were mutually readable: the nix gate afterwards re-checked only the edited modules.
+  **Why no holes**.  The proof plan was fixed before any Agda was written (a running-UTxO invariant with the *pending* ids, so that `Unique`/`All` decompose by pattern matching), and each lemma was a few lines of set-membership plumbing whose shape was known.  Writing the complete term and reading the checker's first complaint was faster than a goal-by-goal loop; nine `check_file` rounds (10 s to 80 s each, the long ones re-checking three dependent modules) took the four modules from draft to green.  Every round localized exactly one real defect: a `⇔` used in the wrong direction, `∀ {i o}` binders whose element types the `IsSet`-overloaded `∈` could not resolve, and, three times, a UTxO implicit that cannot be inferred because it only occurs under `ˢ`/`dom` (fixed by explicit map arguments and by turning two predicates into records).
+  **What was useful in the response**: `involved.metaTypes` with exact source ranges for unsolved metas (one `sed -n` per range and the culprit was visible), and the `success` verdict tied to the exit code.  What was noise: the 300-line constraint dump listing every `DecEq` instance candidate; a summary of the *blocking* meta alone would have sufficed.
+  **What was awkward**: (1) two agda processes on one `_build/` is a race, so the background nix gate and the MCP checks had to be serialized by hand; a server-side lock, or a note in the tool description, would remove the worry.  (2) A `check_file` on the top consumer re-checks every changed dependency (75 s); expected, but with three edited modules the per-round cost was dominated by that, and there is no way to ask "check only this file against stale interfaces".  (3) The intermediate commit split (rebuilding a no-mint-only state of three files) needed its own full round; unavoidable, but it is where a `check_project` on a *set* of files would have helped.
+  **Was the CLI loop more efficient?**  Roughly a wash on latency, since the flake's `agda` on the same cache takes the same 10 s to 80 s per module.  The MCP won on ergonomics: structured ranges instead of scraping `agda`'s error text, and no `nix develop --command` prefix.  The final gates (full closure, property scan, drop-in wiring module) ran on the CLI as the kick-off requires; the MCP's verdict was treated as a fast pre-check, never as the gate.
+  **Net**: for a plan-first session of small map lemmas, `check_file` was a convenient typed `agda` and the field's main contribution is the negative result about implicit map arguments, now a memory.  The hole-driven tools would have earned their keep only if a goal's *normal form* had been in doubt; it never was.

## 2026-09-15 — fls Leios stack repair (#1304, #1305, #1307): three worktrees

Task shape: move the Leios BLS primitives from the core crypto record into a
Dijkstra-local extension record and rewire two stacked PRs on top of it, each
PR in its own git worktree of the same library.  No proofs, no holes; the work
was record fields, module threading, Foreign mirrors, and prose.

Tools used: `check_file` ×1 on a sibling worktree (failed for a structural
reason, below); after that the whole session ran on the server's pinned agda
wrapper (`~/.cache/fls/agda-root/bin/agda`) from the CLI, and at the end the
server reported a dropped connection.

What was awkward:

+  **One cwd per server, so one worktree per server.**  `check_file` on a
   file under a sibling worktree ran agda with the session worktree as cwd;
   agda read that worktree's `.agda-lib`, added its `src/` to the search path
   beside the `-i` for the sibling, and reported `AmbiguousTopLevelModuleName`
   (the module in both trees).  The `command.cwd` echo made the cause legible
   in one read, which is the tool doing its job, but the tool itself cannot
   serve the multi-worktree workflow this repo uses for stacked PRs.  A
   `cwd` (or "root from the file's nearest .agda-lib") option would fix it.
+  **Connection drop mid-session.**  After a re-login the server was reported
   as failed to connect; the CLI wrapper it had been exec'ing still worked, so
   the session lost the structured verdicts but not the checker.
+  **The pinned wrapper is a hidden asset.**  With the session shell outside
   `nix develop` (`agda` not on PATH), the server's wrapper was the fastest
   path to the project's exact Agda and libraries.  Worth documenting in the
   server's README: "the wrapper at `<agda-root>/bin/agda` is usable directly."

What worked: nothing MCP-specific this session beyond the diagnostic echo.
The CLI loop was genuinely the right instrument here, because every check
was a batch verdict on a whole module in a worktree the server did not own;
the MCP's advantage (warm interaction lane, structured diagnostics) never had
a chance to apply.  Net: for multi-worktree stacked-PR work the server needs
per-call roots before it can replace the CLI.
## 2026-09-22, fls PR #1304 review triage (no Agda written)

Session: reading the reviewers' comments on the Leios crypto
structure PR and proposing fixes; analysis only, no Agda edited.

+  Tools used: `type_of` once, to check that `IsStrictTotalOrder._<?_` exists
   (a reviewer said the `Dec-<ᵏʰ` field is derivable).
+  What happened: the call failed at load with `LibraryError`.  The server's
   libraries file was agda-native-air's own (`agda/libraries`, registering
   agda-dojang and standard-library-2.3 only), so `standard-library-classes`,
   `standard-library-meta`, `abstract-set-theory` and `iog-prelude` were
   unresolvable, and `command.cwd` was a worktree of a private repository, not the fls
   worktree the file lives in.  The echo made the diagnosis immediate, which is
   the tool doing its job; the configuration is the problem.
+  Workaround: grep the pinned stdlib source in the nix store
   (`Relation/Binary/Structures.agda`), which answered in one command.
+  Verdict: for a one-fact lookup the grep was faster than a working lane would
   have been; the lane would pay off only for the hole-driven edits that a fix
   session will do.  A per-project libraries file (or starting the server from
   the fls worktree) is the prerequisite before that session.
+  Same day, the fix session: the four edits were written from the analysis and
   gated with the devShell `agda` on PATH (Dijkstra Specification and Foreign
   umbrellas, 75 modules, 8 minutes, exit 0).  No hole was opened: the changes
   were deletions, a one-line derived instance, and prose, so the lane would
   have had nothing to add even if it had loaded.

## 2026-09-28, agda-algebras #513, PR #579 (Aschbacher's D-lattices specialized to parachutes), Claude Fable 5.1

Task shape: read three of Aschbacher's papers, work out what they say about
parachutes, and land the result as a new lattice module
(`Classical.Structures.Lattice.Disconnected`: modular elements, A- and
D-lattices, the theorem that D-lattices are A-lattices, and that parachutes
with two big canopies are D-lattices), three catalog entries in
`FLRP.Reductions`, a relocated three-element chain, and survey-note updates.
About 250 lines of new Agda, all composed as complete definitions from a
plan; no holes were opened.

Tools used: `check_file` ×8 (the new module ×3, `FLRP.Closure.Basic` ×1,
`FLRP.Reductions` ×2, `FLRP.Hunt` ×1, plus one on the module before a rename
that was abandoned).  Nothing else: no `get_goal`, `fill_hole`, `type_of`,
`resolve_name`, or `exports_of`.  The final gate was `make check` from the
shell (74 s, exit 0), because CI runs it that way.

What worked:

+  **The structured diagnostics carried the repair each time**.  Three
   failures, three fixes, each from one read of the JSON: a `NotInScope` on
   a renamed operator whose `where`-clause rename did not reach the type
   signature; an `UnsolvedConstraints` whose `involved.metaTypes` showed the
   parachute's meet reduced at an extremum (`meetᶜ … (i ≟ i)`), which is the
   documented reason the Parachute module passes endpoints explicitly, so the
   fix was mechanical; and an `UnsolvedMetaVariables` at a single
   `IE→cfIE ie` whose lattice argument cannot be inferred through the
   unfolded interval isomorphism, again visible from the printed constraint
   (`_𝑳.fst.Interp.to … = hexagonᵃ ∧ᵖ …`).  The line and column ranges pointed
   at the right token every time.
+  **Root selection was right without configuration this time**: the
   worktree's `.agda-lib` was already in the server's libraries registry
   (from the 2026-09-01 session), and every response echoed
   `rootSource: nearest-agda-lib` with this worktree as the root.  The one
   thing to remember is that this registry line is per-worktree and goes
   stale when the worktree is deleted.
+  **Turnaround**: 5–30 s per check on modules whose dependencies were
   warm, against a 74 s `make check`; for a session that edits four modules
   in a chain (Problem → Closure.Basic → Reductions → Hunt) the per-file
   verdicts were the right granularity and the CLI was only needed at the
   end.

What was awkward or missing:

+  **No profiling tool**, again (agda-native-air #134).  The new module's
   cost was never measured because the measurement loop lives in Bash.
+  **The lane's warm state is wasted by a batch-only workflow**.  Every
   `check_file` here `checkedFromSource: true`; the interaction lane, which
   would have answered `get_goal` in milliseconds, was never used because
   the definitions were written whole.  That is a choice about how to work,
   not a tool defect, but it means this session cannot say whether
   hole-driven development would have been faster.  For the two
   unsolved-meta repairs a `type_of` on the offending subterm would have
   shown the stuck meet directly; the batch diagnostic showed it too, one
   level less conveniently.
+  **Two agda processes on one tree**.  While the server had a lane open on
   the worktree, the session ran `make check` in the background from the
   shell; both write interfaces under the same `_build/`.  Nothing broke,
   but nothing guarantees it, and the server gives no way to ask "is a lane
   currently loading this root?" before starting a batch build beside it.

Verdict: the MCP loop was more efficient than the CLI for the per-module
checks (shorter turnaround, and the diagnostics were readable without
scrolling a log), and the CLI was still required for the acceptance gate.
Net positive, modest.  The larger cost centers of the session were reading
papers and running GAP, which no Agda tool touches.

Addendum, later the same day: one more `check_file` on `FLRP.Reductions` after
a prose-only edit (16 s, green), the cheap way to confirm that a documentation
change did not disturb a code fence.

Second addendum, after Copilot's round two on the same PR: two more
`check_file` calls on `FLRP.Reductions` (8 s and 17 s, both green) confirmed
the two code repairs the review asked for, an added premise on an imported
hypothesis and a finiteness-aware restatement of an entry, before the 13 s
incremental `make check`.  Same pattern as before: per-file verdicts for the
edits, the batch gate at the end.

## 2026-09-28, fls Leios reorientation and two PR reviews (Claude Fable 5.1)

Session: reorient on the Leios ledger formalization, refresh the review artifact,
review PRs #1331 (BLS keys in the pool state) and #1300 (the voting committee).

Tools used: none of the agda-mcp tools.  All Agda work went through the CLI
`agda` of the nix devShell the session was launched from.

Why not: the two review targets were not the session worktree.  #1331's tree
IS the session worktree, and its gate (Specification + Foreign umbrellas, 76
modules, exit 0) ran as two plain `agda` invocations in the background while
other reading went on; nothing in that review needed a goal, a type, or a
normal form.  #1300's head lives on a sibling branch, so it was checked out
into a detached scratch worktree seeded with a sibling's `_build/`, and the
known limit (check_file and the lane resolve a sibling worktree's modules
twice, AmbiguousTopLevelModuleName, recorded 2026-09-21) kept the MCP tools
out of it.

The one place a live query would have earned its keep: verifying that
`selectCommittee` sorts the committee in reverse.  `normalize` would have been
the natural instrument, but the definition does not compute anyway, because
stdlib's `Data.List.Sort.sort` is `abstract`; the answer came from a probe
module that sorts four concrete seats with `Data.List.Sort.MergeSort.mergeSort`
under the PR's own (private) order, exposed by appending a hidden block to the
scratch copy.  A `refl` that fails prints the computed list, so one batch run
answered the question and a second run confirmed the fix.  A normalize call in
a hole would have needed the same visibility hook and the same substitution of
the computable sort, so the CLI loop was not slower here; it was the only loop
available for a sibling tree.

What would have made agda-mcp useful this session: a per-call project root
(or a `cwd` parameter) so a sibling worktree can be served, and a way to
evaluate under `abstract` (Agda has none; this is not the server's fault).

Verdict: neutral.  The session was review and status work; the checker was
consulted as a batch oracle four times, and the structured diagnostics of
check_file would have saved nothing over reading the last lines of a log.

Addendum, later the same session (agda-algebras, second batch).  Two
more modules were written whole, an imported-theorem entry for Lucchini's
`Mₙ` dichotomy and an emitted certificate for the hexagon on six points.
Neither could be checked through the server: the libraries file the server
reads (`agda/libraries` of this repository) had meanwhile been rewritten to
register `agda-algebras` at a Nix store path rather than at the worktree,
and `check_file` refused with the root-mismatch diagnostic the tool
documents (it names both roots and the fix).  The diagnostic was right and
the refusal was the correct behavior; the fix it asks for, restarting the
server against the worktree, is not something a session can do from inside
(the harness spawns the server from `.mcp.json`), and William reported a
newly compiled server in the meantime, which likewise needs a restart of
the client to take effect.  The CLI (`agda <file>` through the worktree's
wrapper) was the gate for the rest of the session: 10 s for the new entry,
7 s for the 550-line certificate, a 4 s recheck after a prose edit.  For a
session that writes small modules whole, the CLI is a complete substitute;
what the server would have added is the structured diagnostic, and there
was one error to diagnose (a `let … where` on a signature), which the CLI
reported plainly.  Two things for the tool: the registry line for a
worktree should not be silently replaced by a flake rebuild, or the server
should read the `*_ROOT` variable the `.mcp.json` sets over the registry;
and a way to reload or restart the server from a client session would have
turned a dead tool into a live one here.

Addendum, third stretch of the same session (agda-algebras, third batch).  The Agda work was
one derived module (`AlmostSimple`, instantiating a structure theorem from
`FLRP.Parachute.Basic` at the monolith of a catalog entry, about 60 lines)
plus prose and an umbrella re-export, all checked through the CLI wrapper:
one error in two runs (a `Fin (suc m)` versus the parachute's own `Ix`, an
index mismatch seen earlier in the session; fixed by naming the module's
type), 25 s and 19 s per run, then `make check` in the background (exit 0).
The server stayed unusable for the reason of the previous addendum (the
registry root), so there is no comparison to draw from this stretch beyond
the earlier one; but the error is worth noting as the kind a `get_goal`
would have answered in one step, since the mismatch is visible only after
the checker unfolds the record's index, and the CLI reports it as
`suc m != m` at the use site with no hint of where `Ix` is defined.  A
`definition_of` call on `Ix` would have been the natural next move.
Everything else in the stretch was Python (a lattice enumerator), GAP
(three sweeps run in the background), and prose; none of it
touches the server.  Verdict for the stretch: not applicable, one small
data point for the value of `get_goal` on index mismatches.

## 2026-09-29, formal-ledger-specifications: leios-main history rewrite

Task: rebuild `leios-main` (16 commits from six merged PRs) as six commits, one
per PR with authorship kept, rebase the two stacked PR branches onto the result,
and open the PR to master.  No Agda was written or edited; the rebuilt tree is
byte-identical to the old head.

+  **agda-mcp tools used**: none.  The task had no hole to drive and no module
   to compose; the checker was needed only as a gate.
+  **What the gate was**: the two rebased stacked branches live in sibling
   worktrees, and `check_file` serves only the session worktree (a sibling
   resolves twice and fails with `AmbiguousTopLevelModuleName`, as recorded on
   2026-09-15), so each was checked by a detached CLI process in its own
   worktree and `_build/` (`agda src/Ledger.lagda.md`, then the Foreign
   modules), with a log-polling monitor for the verdicts.  Each run re-checked
   roughly 60 to 90 modules off a warm cache.
+  **What was awkward**: the gate is a whole-closure batch run per branch, so
   the two verdicts arrived twenty-odd minutes after the branches were ready,
   and nothing in the MCP surface shortens that: `check_project` runs one
   project's gate from one root, and neither it nor `check_file` accepts a
   worktree other than the registered one.  A `check_file` that took a project
   root (or a `--library-file`) as an argument would have replaced the shell
   processes and the monitor.  Verdicts: exit 0 on both (225 and 209
   modules), about 45 minutes each, because the rebase moved the branches
   onto a master that had changed the set library, which invalidated every
   cached interface; two checks ran side by side without interference.
+  **CLI versus MCP**: the CLI loop was the right tool and not slower; the MCP
   server had nothing to offer a history rewrite, which is the honest finding.

## 2026-09-30, formal-ledger-specifications, leios-main (Claude Fable 5.1)

No Agda was written or modified: the session rewrote four commit messages of
`leios-main` (trees byte-identical, so no typecheck was needed) and drafted the
Integration plan and issues from the merged modules.  agda-mcp tools used:
none.  CLI agda used: none.  Nothing to compare; the loop question did not
arise.  The modules were read with plain `cat`, which was the right tool for
orientation across many files.

## 2026-09-30, agda-algebras: moving a subtree into its own library (Claude Opus 5.5)

The session moved a subtree of agda-algebras into a new library that depends on
agda-algebras.  The Agda edits were small and mechanical: a record and its lemma
moved verbatim between two modules, one import was redirected, three modules
were renamed along with their importers, and one import that had gone through a
barrel was pointed at the module directly.

+  **agda-mcp tools used**: `check_file`, once, on the record's new home in a
   second worktree of agda-algebras.  It ran Agda and returned exit 42 with
   `AmbiguousTopLevelModuleName`: the server's registry places the library at
   the primary checkout, so the module resolved to two files.  This is the
   sibling-worktree failure recorded on 2026-09-15.  The server did not refuse
   with the `rootMismatch` its instructions describe; it ran a check that
   could only fail.
+  **What I used instead**: the CLI from each tree's own dev shell
   (`nix develop --command agda <file>`, 27 to 33 s per module with its
   dependencies), then `make check` as the gate on both libraries.  I did not
   try agda-mcp on the new library, which resolves agda-algebras from a copy
   that the server's registry knows nothing about, and I did not try
   `check_project`.
+  **What was missing**: a way to name the registry per call (a project root,
   or the libraries file the tree's dev shell writes).  With it, `check_file`
   would have served the worktree and the new library, and the one scope error
   of the session (a name reached through a barrel that no longer re-exports
   it) could have been found by a single-module check instead of a 53 s
   `make check`.
+  **CLI versus MCP**: for a mechanical move the CLI was the right loop, and
   here it was the only one that worked.  The verification was whole-library
   builds, which no MCP tool shortened.
+  **Addendum, 2026-10-01**: a later prose-only correction in the new library
   was checked with `make check` alone.  The server is not configured for that
   library, so agda-mcp was not tried; configuring it needs a libraries file
   that registers the dependency's writable copy, which is the same missing
   per-call registry noted above.

## 2026-09-30, fls issue #1336: the Leios block structure (Claude Fable 5.1)

The session added two header fields, two block fields, a record, a predicate
with its decider, one premise, the Computational case, and the Foreign mirror,
in a worktree that started with no interface cache.

+  **agda-mcp tools used**: `type_of` once, to warm the lane and confirm the
   project root, and `check_file` four times: the types, the Computational
   module, the Foreign mirror, and the prose version of the module.  Every
   check passed on the first attempt, so `get_goal` and `fill_hole` were never
   needed: the shapes were known from the consensus spec's `certChecks` and
   from the file's neighbors.
+  **What worked**: `check_file` on one module with its dependencies cached is
   a 13 to 15 s answer carrying Agda's own exit code, with no output to parse.
   The first lane load of `BlockBody` took 213 s because the worktree had no
   `_build`; seeding `_build` from master's with `rsync --ignore-existing`
   cut the next check to 13 s, since Agda verifies source hashes and rebuilds
   only what is stale.
+  **What was awkward**: two of the four `check_file` calls (204 s and 159 s)
   outran the 120 s foreground limit and went to the background, because
   checking the Computational and Foreign modules rebuilt the dependents of
   the changed module that master's interfaces no longer covered.  There is no
   progress signal from a running check other than listing `_build`.  The
   server served only the session worktree, as recorded on 2026-09-15; the
   session never pointed it at a sibling, so the ambiguous-module trap did not
   fire.
+  **CLI versus MCP**: roughly even.  The development was four batch checks,
   and the CLI would have run the same four `agda` invocations at the same
   cost; the saving was the structured verdict.  The final gate ran on the CLI
   in the background (1 min 15 s and 20 s, 21 and 3 modules from source, zero
   warnings), which the foreground limit would not have tolerated.
   Hole-driven development did not happen because the Agda was mechanical;
   the judgment was in the shape of one premise and in the prose.

## 2026-09-30, fls issue #1337: the Leios certification delay in slots (Claude Fable 5.1)

Task: four small definitions across the prelude, the epoch structure, the Leios
module, and a two-conjunct change to the Dijkstra `paramsWellFormed` and its
update predicate, in the session's own worktree with a `_build/` seeded from a
sibling.

Tools used and what each did:

+  `check_file`, four times, as the per-file gate after each edit: `Core/Foreign/Epoch.agda`
   14 s and 12 s (prelude closure), `Leios.lagda.md` 130 s (the Dijkstra spine,
   moved to the background after 120 s and the completion notification arrived),
   `PParams.lagda.md` 100 s.  All green on the first run.
+  `get_goal` on both holes in `PParams.lagda.md`: the first load of the file
   cost 114 s in the lane; the second goal answered in 38 ms.  Goal `Type`,
   context as expected.
+  `resolve_name` for `Maybe.All` and `½` (1 to 2 ms each) confirmed the names
   and their provenance through the `as ℚ` opening.
+  `type_of` on the two candidate conjuncts caught `fromUnitInterval` out of
   scope (a `using` list in the module header) before any batch run; after the
   one-line import fix the lane reloaded in 107 s and both candidates typed as
   `Type`.
+  `fill_hole` once, for the update-level clause, the one real uncertainty
   (whether `¿ paramsUpdateWellFormed u ¿` still resolves its instances through
   `Dec-×`, `Dec-MAll` and `ℚ-Dec-<`): status `ok` in 96 s with the other hole
   listed as remaining.
+  `normalize` on `Ledger.Prelude.Base`, four probes of `durationToSlots 1000 d`
   for d = 8500, 8000, 0, 1 (9, 8, 0, 1): the rounding check at the boundary,
   0.2 s to load the file and about 1 ms per probe afterward.
+  `search_in_scope` once, at the `paramsWellFormed` hole with tokens `ℚ` and
   `<`: 7 s, six results, mostly `Data.Nat.Properties` lemmas; the ranking is
   over function rows by type-token overlap, and a goal of type `Type` has no
   tokens, so it had nothing to rank by.  Not useful for this shape of goal.

What was awkward or missing:

+  `type_of` on `¿ P ¿` prints the unapplied instance argument
   (`⦃ _ : P ⁇ ⦄ → Dec P`), so it cannot say whether the instance resolves; only
   a batch run (`fill_hole` or `check_file`) answers that.  A `type_of` variant
   that runs instance resolution to completion would have saved the fill.
+  One agda process per `_build/`: the lane (persistent) and the batch tools write
   interfaces into the same tree, and the project's long gate must run outside
   the tools (45 minutes, detached), so lane queries had to wait for it.  Nothing
   in the tools serializes this; I did it by hand.
+  `check_project` was not applicable: the project's acceptance gate is the
   closure plus the test library under a custom `--library-file`, which no
   Makefile target or single command expresses.
+  The lane reload after a one-line import edit cost a full re-typecheck of
   `PParams` (107 s), the same as the first load; a 50-field record with derived
   `DecEq` and `Show` is what makes that file slow, not the tool.

The final gate ran on the CLI, detached from a script with a status file,
because one agda process at a time may touch `_build/` and the project's gate
is two libraries: the closure (`agda src/Ledger.lagda.md`) re-checked 222
modules from source in 16 min 06 s with zero warnings, the two `Foreign`
umbrellas took 16 s and 15 s (already inside the closure), and the test library
took 11 min for 50 modules against the working copy through a custom
`--library-file`, a configuration `check_project` has no way to express.

Was the CLI loop more efficient?  About even, and honestly so.  Each verdict
is a full agda run on the file either way (PParams: 100 s), and the task's
definitions were small enough that a careful first draft would have passed the
batch check anyway; the lane saved exactly one failed batch run (the missing
import), about 100 s, at the cost of a 114 s first load.  Where the MCP clearly
won was the knowledge side: `normalize` for the rounding probe and `resolve_name`
for provenance answered in milliseconds what a CLI session would have done with a
scratch module and another batch run.  The hole-driven loop's value scales with
the uncertainty of the term, and this task had little.

## 2026-10-01, fls issue #1338: the CHAIN certificate branch (Claude Fable 5.1)

Task: a new relation (`CERTIFY`) beside `CHAIN`, a new chain-state record, two
`⁇` instances and a decision procedure in two other modules, two `Computational`
instances, and the Foreign mirror, in the session's own worktree with a
`_build/` seeded from a sibling and a background whole-closure check of the
merged base (222 modules, 20 minutes) run before the first edit.

Tools used and what each did:

+  `check_file`, eleven times, as the per-module gate after each edit: 11 to
   23 s per module on the warm cache, with one outlier of 117 s for the
   `Computational` module while it still held two holes and an error (the same
   module without holes checked in 19 s).  Eight runs green; three red, each
   with a diagnosis the structured answer made immediate: `MetaCannotDependOn`
   (a product pattern over a field with an implicit binder, elaborated before
   its type was known), `UnsolvedConstraints` whose `involved.metaTypes` listed
   both instance candidates (`Dec-AllPairs` and the module's own `Dec-Unique`,
   stuck between them), and `InstanceNoCandidate` (an instance left out by a
   `using` list).  The `holes` list gave the two holes' positions exactly.
+  `get_goal`, twice, on those holes: both answered through the injected-macro
   fallback, because the file did not load (a type error in another clause of
   the same instance).  One answer was a macro-induced error, the macro inside
   a `do` block breaking the `Monad` instance resolution for `>>=`; the other
   surfaced the real error (`lhs != CertifyEnv.lastApplied Γ`: a `rewrite` on
   a record projection that also sits in a with-function's argument type),
   which was the most useful single message of the session, though not a goal.
+  No `fill_hole`, `type_of`, `normalize`, `resolve_name`, or `search_in_scope`:
   the premise types are the specification and the instance's expected terms
   followed from the constructor, so every question was "does the edit check",
   which `check_file` answers.

What was awkward or missing:

+  A file with one broken clause cannot be queried at a hole in another clause.
   Agda's own interaction mode has the same limit, but the fallback then ran
   the macro path and reported its own failure; a plain "the file does not
   load, first error here" would have been the honest answer and saved a call.
+  One agda process per `_build/`: while the 20-minute base check ran, no
   `check_file` could run on the worktree.  A scratch copy of `src`,
   `src-lib-exts`, the `.agda-lib` and `_build/` (147 MB, seconds to rsync)
   gave a second cache to check the first edit in, and later a from-source run
   of the final tree with the worktree's cache untouched.  A `buildDir`
   argument, or the server queuing behind a concurrent agda on the same
   `_build/`, would remove the workaround.

Verdict on efficiency: the batch loop was the right loop here, and `check_file`
was at least as fast as the CLI with the structured `code` and candidate
listing as a small plus over log reading.  Hole-driven development did not
contribute: the two `get_goal` calls both fell back and neither showed a goal.
Checker time in total about five minutes across twelve calls, against about
three hours of session time, most of it reading and design.

## 2026-10-03, agda-flrp, two generated modules (Claude Fable 5.1)

A session whose only Agda output was two generated literate modules
(0.6 and 0.8 MB each), type-checked once each.

+  `check_file` on the larger module: `success: true`, `exitCode: 0`, no
   diagnostics, `checkedFromSource: true`, 67 s, `project.rootSource:
   nearest-agda-lib`; the CLI `agda` on the other module took 75 s to the
   same verdict.  Nothing differs in what either reports for a passing
   file; the server's answer is the smaller one to read (a JSON object
   against a screen of `Checking …` lines).
+  Nothing else was asked of the server: the modules were generated, not
   developed, so no hole, goal or name query arose and the knowledge lane
   was never used.  The tools were loaded with `ToolSearch("+agda")` on the
   first Agda step; the registry resolved to the checkout the session ran
   in, with no `rootMismatch`.

Verdict on efficiency: for a session of this kind the CLI loop and the
server are equally efficient; the server's one advantage was the
structured verdict.

## 2026-10-03, agda-flrp, a research pass with one new module (Claude Fable 5.1)

A session whose Agda output was one new literate module of about 60 lines
of code, written whole and checked once, inside a library of some forty
modules over a dependency library registered through the dev shell's own
`.agda/libraries` in a worktree.

+  The registration resolved the worktree as the project root
   (`project.rootSource: nearest-agda-lib`) and the dependency library's
   copy under the main checkout's dependency directory, with no
   `rootMismatch`: the first `check_file` on a small existing module,
   6.9 s from source, `success: true`, and the second on the new module,
   40 s from source (its imports rebuilt from the worktree's empty
   interface cache), `success: true`, no diagnostics, first try.
+  Nothing else was asked of the server.  The module's proof was planned
   from reading two neighboring modules' source rather than by querying
   their exports or goal types, which would have been the hole-driven
   alternative: `exports_of` on the two modules could have replaced two
   `grep` and `sed` passes over them, and `get_goal` on a hole would have
   confirmed the one type the author was unsure of (a lemma's
   argument order) before the file was written; the file checked, so the
   cost of not asking was zero this time.
+  The whole-library gate was run from a shell (`make check`, which
   regenerates the aggregator and checks everything but the certificate
   census) in the background while other work went on; it took about ten
   minutes.
   `check_project` would have blocked for the same time, so the shell was
   the right tool for a gate run concurrently with unrelated work.

Verdict on efficiency: for one module written whole, the CLI loop and the
server are equally efficient and the server's structured verdict is the
small plus; the session's time went to GAP computations and reading, not
to Agda, and the one place the server could have saved effort was the
knowledge lane (`exports_of`), which was not used.

## 2026-10-04: one new lattice-theory module in a research session dominated by GAP

Context: a session that mostly ran group-theoretic computations in GAP;
the Agda work was one small new module (a
short group-theoretic lemma) and a one-line addition to the library's barrel,
in a git worktree whose dev shell registers the dependency library's copy
under the main checkout.

+  `check_file` on a small existing module at the start, as the
   connection test: `success: true`, 9.0 s, `checkedFromSource: false`
   (interfaces already built by a shell `make check` running concurrently),
   `rootSource: nearest-agda-lib`, no `rootMismatch`.
+  `type_of` on two library names from an existing module's scope
   (Dedekind's rule and the core-freeness predicate): 7.3 s for the first
   question (one lane load) and 0.5 s for the second after a lane switch
   to a neighboring file.  The printed types were fully qualified and long
   (several screens for Dedekind's rule), so the argument order was read
   from the library's source instead; `exports_of` on the complements
   module (12 members, 7.4 s, first load) gave the member names and types
   that decided which lemmas to import.
+  `check_file` on the new module: `success: true`, 8.1 s, checked from
   source, no diagnostics, first try; then `check_file` on the barrel
   module that imports every library module: `success: true`, 9.7 s.
   Neither run needed a hole: the proof was written whole from the two
   neighboring modules' source.
+  The whole-library gate (`make check`) was run from the shell in the
   background at session start, before any Agda was written, so the
   server's `check_project` was not used.

Verdict on efficiency: equal.  For a module written in one piece, the
server's structured verdicts replaced a CLI invocation and saved nothing
but the parsing; the two knowledge-lane calls (`exports_of`, `type_of`)
answered real questions in seconds, and `exports_of` was the more useful
of the two because its answer is a list rather than one long printed type.

## 2026-10-04, agda-algebras issue #577: the in-browser playground (Claude Opus 5.5)

Context: the session built an interactive Agda page for the documentation
site (Agda 2.8.0 compiled to WebAssembly, driven through its
`--interaction-json` protocol), so most of its time went to JavaScript,
Python and measurement.  The Agda written was six small files: three
exercises taken from the library (`graft` and `_✦_` of
`Overture.Terms.Interpretation`, `⊙-is-hom` of
`Setoid.Homomorphisms.Properties`) and their solutions, outside `src/`, in
`docs/playground/`.

+  `check_file` (7 calls) on the exercises and solutions: correct verdicts,
   0.1 to 0.8 s for the small ones and 4.4 s for the one that imports the
   Setoid tree, `rootSource: nearest-agda-lib` even though the files live
   outside the library's `include: src`.  An exercise with a hole came back
   `success: false`, exit 42, with the hole listed: exactly what was needed.
+  `get_goal` (2 calls): right goal and context, through the live lane.  The
   types were printed fully normalized (`𝑆 : Agda.Builtin.Sigma.Σ (Type 𝑆.𝓞)
   (λ F → F → Type 𝑆.𝓥)`, `Func (Algebra.Domain 𝑨) (Algebra.Domain 𝑩)`)
   where agda-mode's default, `Simplified`, prints `Signature 𝑆.𝓞 𝑆.𝓥` and
   `Func 𝔻[ 𝑨 ] 𝔻[ 𝑩 ]`.  For this task, where the page shows readers what
   agda-mode shows them, the server's display was the wrong one to design
   against, and the protocol had to be driven directly to see the
   `Simplified` form.  **Missing**: a `rewrite` argument on `get_goal`
   (`AsIs`, `Simplified`, `Normalised`), defaulting to `Simplified` as
   agda-mode does.
+  `fill_hole` (1 call): `trans (cong h (compatible ghom)) ?` in the
   homomorphism exercise, `status: ok` with the new hole listed, 4.4 s.
+  **Missing for this task**: the goal commands that rewrite text, case
   split above all.  The page's hints had to name the variables a case
   split introduces, and Agda names them after the constructor's own
   binders (`ℊ x`, `node f t`, not the `y` and `ts` a person would guess);
   the server could not say, so the answer came from running the protocol.
   A `make_case` tool (and `refine`, `give`) answering with Agda's text
   would have settled that in one call.

Verdict on efficiency: for checking six small files the server and the CLI
were equal, and the structured verdict was the small plus.  The real work
(the protocol's JSON shapes, the case-split names, the `Simplified` display)
needed Agda's interaction protocol itself, which the server does not expose,
so the CLI and a node driver over the WebAssembly checker did it.

## 2026-10-05, fls PR #1340: rebase onto master after #1330 merged (Claude Opus 5.5)

Task: rebase a four-commit branch onto a master that had gained one merged PR
(endorser-block validity, six files, none shared with the branch), audit the
result, and re-run the project's gate.  No Agda was written: the replay was
clean, and the audit (rebased tree byte-identical to `git merge-tree`'s
mechanical three-way merge; the same six files and 60 changed lines; messages,
authors and dates unchanged) left only the semantic question to the checker.

+  **`check_project`** ran the closure gate, the server's `--check-command`
   (`agda src/Ledger.lagda.md`), as its first real use in an fls session.
   It answered `success: true`, exit 0, `modulesChecked: 83` and zero
   diagnostics in 17 min 27 s, with `gate.source: server-config` saying which
   gate ran and a bounded output tail ending at `Checking Ledger`.  The call
   outlived the 120-second foreground limit and finished as a background task
   whose notification carried the whole result.  Its diagnostics include
   warnings, since the parser takes every `: warning:` line from the full output
   (read in `Tools/CheckProject.hs` and `Diagnostics.hs`), so the project's
   zero-warning requirement is answered by `diagnosticsTotal` without a grep.
+  **The test library** still had to run on the CLI: its gate needs a custom
   `--library-file` naming the worktree's own `.agda-lib`, and the library has
   no umbrella module, so it is one `agda` call per file in a loop.  50 files
   green and nothing re-checked from source, since the merged PR changed only
   Dijkstra modules and the test library builds on Conway; the 20 minutes were
   each call loading the ledger's interfaces.

Was the CLI more efficient?  For a gate, the two are the same agda run; the
difference is the report.  `check_project` was the better instrument for the
closure: one structured answer (verdict, module count, warnings counted, masked
failures caught) in place of a detached script, a status file and three greps,
at the same cost.  It cannot run the second half of the fls gate, a library
that depends on the worktree's own library through a custom registry; a
`--check-command` that ran both halves, or a per-call extra `--library-file`,
would make it the whole gate.

## 2026-10-05 (evening), fls: restacking four Leios PRs and two review tweaks

Session root was the merged `1337` worktree, so every branch being rebased lived in a
sibling worktree that the server cannot check (`AmbiguousTopLevelModuleName`); all
verdicts came from the CLI `agda` in each worktree, seeded by copying `_build/` from a
sibling whose tree matched (master's tree equaled the merged branch's).

+  `resolve_name` on the session worktree's copy of the module answered the two scope
   questions that decided the shape of a reviewer's suggestions in milliseconds: the
   unqualified `filter` is NOT in scope (the prelude hides the list one behind
   `Filter.filter`, and the did-you-mean list showed the set and map variants), and
   `zip` IS in scope but is `Data.Product.Base.zip`.  Both answers were right; a guess
   at either would have cost a failed batch run.  Using a sibling's copy of the file
   for scope questions works whenever the import block is the same.
+  Nothing else was usable across worktrees; `check_file` and `type_of` for the edited
   file would have been welcome, and a rebase-heavy session spends most of its time in
   siblings.  A server option to serve a second root, or to take the root from the
   file's own `.agda-lib`, would have covered this whole session.
+  The CLI was more efficient for the verdicts themselves: three whole-closure gates
   (211, 11, 211 modules) and three test-library runs ran concurrently in the
   background from one agda per `_build/`, which the single-lane server does not do.

Addendum (same session, after the switch to the indexed sum):

+  `normalize` was the right tool to test a claim about `setToList` of an aggregated map,
   and its answer was informative in a way a batch run is not: the normal form came back
   stuck on `abstract-set-theory.FiniteSetTheory.listing` and `finiteness`, which shows
   at once that fls's finite sets are abstract and that the listing cannot be computed,
   so no probe can settle the question.  A batch `refl` probe would only have reported a
   failed equation.  The answer was very long (the whole stuck term); a size cap or a
   "stuck on: <names>" summary would have been enough.
+  A small batch probe (three `refl` equations in a throwaway module) remained the
   quickest way to confirm that the new `∑ˡ` over ℚ computes like the fold it replaced;
   it ran in a sibling worktree the server could not serve.

## 2026-10-06, agda-algebras issue #586: the library under the Agda 2.9.0 nightly (Claude Opus 5.5)

Context: the session checked the whole library under an unreleased Agda
(the 2.9.0 nightly) against five standard libraries, so nearly all of its
Agda was whole-library `make check` runs through per-row wrappers, not
editing.  The only Agda written was two deletions, fixity declarations for
closed operators in `Overture.Basic` and `Overture.Relations` (pull request
587).

+  agda-mcp was not connected: ToolSearch for "+agda" found nothing, so the
   session used the CLI throughout.
+  It would not have helped much here, and the reason is worth recording:
   the server runs the flake's Agda 2.8.0, and the question was what a
   different Agda does with the library.  Every run needed its own Agda
   binary, its own libraries file and a reset `_build`, and five of them
   ran back to back with timing and module counts recorded.  A server bound
   to one Agda and one libraries file cannot serve that; an option to name
   the Agda binary and the libraries file per call would.
+  For the two deletions, the CLI was the right tool: the verdict that
   mattered was a from-source `make check` under both Agdas (344 library
   modules each), not a per-module check.

## 2026-10-06, fls PR #1339 self-review before merge (Claude Opus 5.5)

The session reviewed a finished PR and changed only module prose: two sentences
of `BlockBody.lagda.md` that described unmerged work in the present tense.

+  **agda-mcp tools used**: `check_file` three times and `normalize` twice.
   The edited module checked in 14.7 s (exit 0); its interfaces had been built
   the day before from a byte-identical tree.  To test the new premise by
   execution, `normalize` failed twice.  At the top level of a parameterized
   module every definition still takes the module's parameters
   (`CertifiedEB` "should be a sort"), and in the Foreign module that
   instantiates them the completed top-level scope omits its non-public
   imports, so the spec's names were `NotInScope`.  A throwaway probe module
   of `refl` assertions over arbitrary module parameters worked instead:
   `check_file` passed it in 22 s, and a control with one expectation flipped
   failed with exit 42, printing the actual value.
+  **What worked**: structured verdicts for the edit, the probe, and the
   control, with Agda's actual value in `involved.actual` on the failure.
+  **What was awkward**: `normalize` is unusable on a parameterized module's
   definitions without a hole in scope; the probe file is the workaround.
+  **CLI versus MCP**: even.  The two Dijkstra umbrellas ran on the CLI in the
   background as the final gate (21 s and 19 s, 6 and 2 modules from source,
   zero warnings).

## 2026-10-06, fls PR 1346 self-review: probing the CERTIFY instance (Claude Opus 5.5)

Task: a self-review of the CHAIN certificate branch, execution and a full read of
the diff, with no edits to the repository.  The probes asked what the shipped
`Computational` instance returns on its early branches under the Foreign
instantiation.

Tools used and what each did:

+  `normalize`, once, in the scope of `Foreign/Chain.agda` (lane load 31 s):
   `NotInScope` for `Computational-CERTIFY`, which that file brings in by a
   file-local `open import … Chain.Properties.Computational it DummyAbstractFunctions`.
   The top level of a hole-free file has lost its file-local opens, as the tool
   description says; the "did you mean" offered the applied-module alias
   (`.#…Computational-12409013205270436615.Computational-CERTIFY`), which no
   expression can spell.
+  Nothing else from agda-mcp.  The gate ran as a background CLI script, one agda
   per `_build/`, and the five probes ran as `refl` assertions in a scratch copy
   seeded with the worktree's interfaces: one CLI run, 30 s, all green.

What was awkward or missing: evaluation in the scope a file has after its own
imports, without adding a hole to the worktree under review; and a suggestion
list that offers only names an expression can write.

Verdict on efficiency: the CLI probe module was the right instrument.  Universally
quantified `refl` assertions answered five branch questions in one run, and
agda-mcp contributed only the confirmation of its scope limit.

## 2026-10-06, fls PR 1342 re-review: probes on a Leios committee rotation (Claude Opus 5.5)

Task: a sourced review of the committee-rotation PR, drafted for William,
with no edits to the branch.  Agda work was four probe lemmas in a scratch module
under the session worktree's `src/` (deleted afterwards) plus four CLI builds:
the head, the head merged with `master`, and the head merged with #1346 before
and after a one-line fix.

Tools used and what each did:

+  `check_file`, five calls (20 to 27 s each on a warm cache; the module imports
   the Dijkstra `Epoch` closure).  The first caught my own error (`0` elaborated
   as `ℕ` in a module without ℚ literals); one returned `NotInScope` for
   `PoolsOf` with `Snapshot.pools` among the candidates, which was the fix.
+  `get_goal`, three calls.  For `PParamsOf (applyRUpd ru eps) ≡ PParamsOf eps`
   the normalized goal showed both sides as the same `proj₁ (EnactState.pparams
   (EpochState.es eps))`, which answered the review question before any fill.
   For a goal under `opaque unfolding calculatePoolDelegatedStake` it printed a
   normal form of about 200 lines from agda-sets' list model: true, and useless.
+  `fill_hole`, three calls (`refl` twice, `res-dom` once), all `ok`, then
   written back by hand.  The match on the `EPOCH` derivation needed an edited
   left-hand side, which `fill_hole` cannot do; one `check_file` after the edit.
+  `resolve_name` found `_∣_` in agda-sets' `Axiom/Set/Map.agda` (via
   `Restrictionᵐ`); the lemma `res-dom` came from grepping that store path,
   because `search_in_scope`'s corpus is the standard library only (it probed 12
   unrelated stdlib rows for `res`).

What was awkward or missing:

+  A goal display that does not unfold opaque or list-model definitions, or a
   size cap with an elision, for goals like the restriction one.
+  A corpus covering the repository's own libraries (agda-sets,
   agda-stdlib-classes, agda-stdlib-meta); in fls most lemmas a proof needs live
   there.
+  The server serves only the session worktree, so the merged-tree builds ran on
   the CLI in scratch worktrees, and the probes had to wait for the head build to
   release `_build/`: two agda processes must not write one `_build/`.

Verdict on efficiency: mixed, honestly so.  For the probes agda-mcp was at least
as quick as a CLI loop, and the goal display was itself evidence.  For the
builds (11 min at the head, 30 min for the full gate on the `master` merge, 4
and 10 min on the #1346 merge) the background CLI was the only instrument that
reached the scratch worktrees.

## 2026-10-07, agda-algebras issue #594: switching every module to --without-K (Claude Opus 5.5)

Context: a pragma sweep over all 344 modules (`--cubical-compatible` to
`--without-K`), prose rewrites in twelve modules, and a decision record with
timing measurements (pull request 595).  No definition or proof changed, so
there was no hole-driven work; the Agda verdicts that mattered were
whole-library checks from an empty `_build`.

+  agda-mcp was connected (ToolSearch "+agda" loaded all fourteen tools) and
   ran the flake's Agda 2.8.0: its gate wrapper,
   `~/.cache/agda-algebras/agda-root/bin/agda`, execs the same
   `…-Agda-2.8.0-bin` store path as the dev shell's wrapper.
+  `check_project` was the final gate, after `rm -rf _build`: exit 0, 346
   modules, 88.3 s, 952 diagnostics and no error, with the equivalent
   `make check AGDA=…` command echoed.  It replaced a timed shell run cleanly,
   and `modulesChecked` gave the module count without grepping a log.
+  `check_file`, three calls (0.8 to 3.1 s, warm) on modules whose prose
   changed, each `success: true`; `checkedFromSource` correctly said which
   call rechecked its file.
+  The CLI did the measurement runs, and had to: ten timed `make check` runs
   alternating between two revisions of one worktree (`git switch --detach`
   between them, so interface paths stayed identical), under GNU time, with
   `+RTS -s`, `+RTS -S` and `+RTS -hT -i0.05` for a peak-memory diagnosis.
   `check_project` reports elapsed time but not peak RSS, and takes no RTS
   options; a `rtsOptions` argument and a peak-RSS field (the `ru_maxrss` of
   the gate's children) would have let it serve the timing runs too.
+  Nothing was awkward in the calls that were made.  The one hazard is
   operational: the tools must not run while a background `make check`
   writes the same `_build/`, so I held them until the runs finished.

Verdict on efficiency: for this task the CLI was the instrument and agda-mcp
the final judge.  As a gate `check_project` was as fast as the shell
(88 s against 86 to 128 s for the shell runs) and its verdict needed no log
reading.

## 2026-10-07, agda-algebras issue #589: free lattices and Whitman's procedure (Claude Opus 5.5)

Context: four new modules and an example (pull request 596), about 900 lines
of new Agda: a term type, Whitman's rules as an inductive family with a
decision procedure, transitivity by a mutual structural recursion, the free
lattice built order first with soundness, completeness and the universal
property, and a bridge to the library's equational logic.  The session was
launched from the `master/` checkout and worked in a worktree under
`worktrees/`.

+  agda-mcp was connected (ToolSearch "+agda" loaded all fourteen tools).
   Every call resolved the project root to the worktree
   (`rootSource: nearest-agda-lib`).
+  The batch tools did not work on the worktree.  `check_file` failed with
   `AmbiguousTopLevelModuleName` on the first import
   (`Classical.Operations` found in both `master/src` and the worktree's
   `src`); the echoed command ran with `cwd` set to `master/`, the launch
   directory.  `fill_hole` and `get_diagnostics` share that path, so I did
   not use them.  Running batch Agda with `cwd` at the resolved project root
   would fix it.
+  The lane did work, with the same `cwd`.  I used `type_of` with
   `reload: true` as a load oracle after each edit: seven loads that failed
   came back in-band with the right code and position (`AmbiguousName`,
   `UnequalSorts` and `MetaCannotDependOn` from generalized level variables,
   `ParseError`, `WrongHidingInLHS`, two `UnequalTerms`), each in 0.5 to
   2 s.  A batch check of one module from the CLI took 8 to 18 s, most of
   it loading dependency interfaces.
+  The lane missed two errors the batch check caught: an unsolved level
   meta (`Type (α ⊔ ρ ⊔ _)` in a type signature) and an unsolved `Fin _n`
   from opening a parameterized module at the polymorphic `_≟_`.  In both
   cases `type_of` answered with a type and no warning; batch Agda exited
   42 with `UnsolvedMetaVariables`.  A lane answer that carried the load's
   warnings (at least a count of unsolved metas) would make "it loads in the
   lane" mean what it seems to mean.
+  The lane writes `.agdai` files into the project's `_build` (mode 644,
   where the CLI writes 664), and a later CLI run reuses them without a
   "Checking" line.  I deleted the new modules' interfaces before every
   verdict run, and the final gate was `rm -rf _build && make check`.
+  No hole-driven work.  The plan was precise enough to write each module
   whole, and the transitivity proof (19 clauses, mutually recursive with an
   auxiliary) passed the termination checker at its first load.  `get_goal`
   and `fill_hole` were not needed.

Verdict on efficiency: the lane as a reload oracle was the fastest inner
loop I had, about ten times quicker than a CLI check per iteration, but it
cannot be the judge: twice it reported success on a file that does not type
check.  The CLI in the worktree's own `nix develop` was the judge, and the
batch tools were unusable from a session launched in another checkout.

## 2026-10-07, agda-algebras issue #588: a trial port to Agda 2.9.0 and agda-stdlib 3.0 (Claude Opus 5.5)

Context: the question was what a move to Agda 2.9.0 would take today, before
either Agda 2.9.0 or agda-stdlib 3.0 is released.  I answered it with a trial
in a scratch copy of master, outside every registered project: Agda master's
nightly binary and, later, Agda built from agda/agda's flake, with the
standard library at the commit Agda's `std-lib` submodule pins.  The Agda
changes were renames (two errors, 170 deprecated names in 21 modules), with
no hole-driven work.

+  agda-mcp was connected (ToolSearch "+agda" loaded all fourteen tools), and
   none of them could serve the trial.  The server's Agda is fixed at launch
   (`--agda-bin`, the flake's 2.8.0, and a registry naming only
   standard-library 2.3); no tool takes an Agda binary or a libraries file.
   One probe, `resolve_name` on a trial file with `verbose: true`, answered
   in 53 ms with an in-band `LibraryError` ("Library
   'standard-library-3.0' not found"), and the echo named the binary, the
   registry and the root it had chosen (the trial's own `.agda-lib`, found
   as `nearest-agda-lib`).  The refusal was clear and correct; the gap is
   that a toolchain trial cannot use the tools at all.
+  The CLI did all the work: seven whole-library runs (a nightly wrapper with
   a throwaway data directory, then `nix develop --command make check` in the
   candidate flake's shell) and one single-module check.  Each run stopped
   at its first error, which Agda localized well enough that a grep of the
   library for the same construct found every other instance at once.
+  What would have helped: an `agdaBin` and `librariesFile` per call (or a
   second registered toolchain), so the lane could answer `type_of` and
   `exports_of` under the new Agda.  `exports_of` on the new standard
   library's modules would have confirmed the replacement names
   (`_×?_`, `¬∀⇒∃¬`, `_≡?_`) faster than grepping its source.  Also useful: a
   warnings summary by kind and by message, once per position, since the
   port's real work was splitting 1,121 warning positions into the
   library's own 951 and the standard library's 170.
+  One finding no warning count would have caught: uses of `_≟_` opened from
   a `DecSetoid` bundle raised no deprecation warning, though agda-stdlib 3.0
   deprecates `IsDecEquivalence._≟_`.  A tool listing a module's uses of
   names that carry a `WARNING_ON_USAGE` pragma, through module applications,
   would close that hole.

Verdict on efficiency: for a toolchain trial the CLI was the only
instrument; agda-mcp neither helped nor slowed the work, because it could
not reach the toolchain under test.

## 2026-10-07, fls PR 1342 second version: one gate call (Claude Fable 5.1)

Task: re-review a force-pushed head (three files, 29 changed lines) that had
dropped the previous version's committee rotation; no Agda written.

+  `check_file` on the Dijkstra `Specification.lagda.md` umbrella, once, from
   the session worktree synced to the new head with its `_build/` seeded the day
   before: exit 0, no diagnostics, 373.5 s.  The call outlived the 120 s
   foreground limit and came back as a background task, as the agda-typecheck
   skill says it does.  Only `Epoch.lagda.md` differed from the previous head
   (`Leios.lagda.md` and `UnitInterval.lagda.md` were byte-identical), so the
   rest came from interfaces.
+  Nothing else from agda-mcp; the review's claims were about which snapshot
   and parameters a rule reads, settled by reading both repositories at pinned
   commits, and the earlier session's probes still applied to unchanged terms.

What was awkward or missing: `check_file` reports no module count, so "how
much re-checked" has to come from the CLI's `Checking` lines when it matters.

Verdict on efficiency: even.  One call, one verdict, no log to parse; the CLI
would have taken the same six minutes.

## 2026-10-10, agda-algebras #553: span-class checker, second opinions only (Kimi K3, Copilot CLI)

Task: build a checker that validates the kramdown attribute spans on inline
Agda names in agda-algebras' prose (`Algebra`{.AgdaRecord} and kin) against
Agda's own classification, fix the defects it finds, and gate it
(ualib/agda-algebras#553, PR #599).  No Agda written; the ground truth was
the `agda --html --html-highlight=code` render.

+  agda-mcp was connected and its registration rooted at the session worktree
   correctly (`nearest-agda-lib` found the worktree's own `.agda-lib`).
   `check_file` on `Overture/Signatures.lagda.md` answered the baseline in
   220 ms from warm interfaces; `resolve_name` gave the two second opinions
   the task asked for: `𝒦₀` in `Examples.Setoid.HSPCommutativeMonoid` ("a
   data type", first load 21.6 s) and `Group` in
   `Examples.Classical.Groups.SymmetricGroup3` ("a defined name", load switch
   10.2 s), both agreeing with the render and both locating the definition
   through the import chain with provenance.  Each also reported the spawned
   module as a second candidate, the same Record/Module duality the render
   shows.
+  The server could not have been the gate's oracle, and the issue's design 2
   (a resolve_name sweep) would have been the expensive route: the corpus has
   ~990 distinct (name, class) pairs across 282 live modules, so a sweep is
   one lane load per file (measured 10-22 s each here) against one 34 s
   render.  More fundamentally, `resolve_name` answers what a name resolves
   *to*, not the highlighter's per-occurrence aspect: the local/global split
   this task needed (Bound vs Argument vs Generalizable on one name at
   different sites) is exactly what a definition lookup does not carry.
+  Version skew, as CLAUDE.md warns: the server runs Agda 2.8.0
   (`--agda-bin` under ~/.cache/agda-algebras) while the library targets
   2.9.0.  Both probed files still loaded and answered correctly under
   2.8.0, and the answers matched the 2.9.0 render; but for a verdict that
   must equal CI's, the CLI (the worktree's 2.9.0 wrapper) stayed
   authoritative, and the whole-library `make check` ran on it at the end.
+  What would have helped: a per-occurrence aspect tool, "the highlighter's
   class for every token in this file" (the information `agda --html`
   emits), without going through an HTML render, would let a checker like
   this one skip the render step and stay inside the lane.

Verdict on efficiency: the CLI was the right instrument for the corpus-wide
gate (one render beats ~350 lane loads, and carries per-occurrence aspects
the lane does not expose); the server earned its place as the fast second
opinion on individual names.  Neither slowed the other.

## 2026-10-10, agda-native-air issue #243: Copilot CLI on the one-step subgroup test (GPT-6.1 Sol, Kimi K3)

The first sessions run with a harness other than Claude Code ([#243]).  They
ask, of two more harnesses, the question the first field report asked (§ 2 of
[`flrp-agda-mcp-improvements.md`]): does the model call `check_file`, or run
`agda` from a shell?  Through Copilot the answer is the server, for both
models: GPT-6.1 Sol ran every check of its module through it, and Kimi K3 its
one module check, leaving the whole-library gate to the shell as the
instruction file orders.  Through Codex (the next section) the answer is the
shell, and the reason is the harness.

A Claude Code session (Opus 5.5) set the trials up, ran them headless, read
their transcripts and ran the gates; it wrote this report, and the trial
sessions did not.  Claims are graded as the first report graded its own:
**observed** in a transcript, a harness's own listing, or its debug log of the
requests it sent; **measured** by the reporting session outside the trials;
**inferred** where neither, and marked so.  Unmarked claims are observed.

**The task**, given verbatim to every session with nothing else (no sketch, no
tool names, no mention of the server): create the literate module
`src/Classical/Structures/Group/SubgroupTest.lagda.md` holding the declaration
below, its type signature as written, with a complete proof (no holes, no
postulates); follow the project's conventions for a new module; done when the
new module and the whole library type-check; commit if you like, but do not
push or open a pull request.  The lemma is in neither the library nor the
benchmark, and a reference proof written for this report checks in ten lines
(measured).

```agda
module _ (𝑮 : Group α ρ) where
  open Setoid 𝔻[ proj₁ 𝑮 ] using ( _≈_ )
  open Group-Op 𝑮 using ( _∙_ ; ε ; _⁻¹ )

  one-step-subgroup : {B : Pred 𝕌[ proj₁ 𝑮 ] ℓ}
    →  B Respects _≈_
    →  ε ∈ B
    →  (∀ {x y} → x ∈ B → y ∈ B → x ∙ y ⁻¹ ∈ B)
    →  IsSubgroup 𝑮 B
```

**The setup**, the same for all three sessions, is as follows:

+  **One commit, one worktree per session**.  agda-algebras `ee830bea9`, the
   last master commit on Agda 2.8.0 (the next merge,
   [ualib/agda-algebras#598], moved to 2.9.0), because the registration runs
   agda-algebras' Agda 2.8.0 wrapper (`agda --version` on it: 2.8.0).
   `make check` passes there under 2.8.0 (measured: 352 modules, 4 min 47 s
   cold), and so do the four other gates below.  Each worktree got a copy of
   that run's `_build`, so no session paid for a cold library.
+  **One server**.  The registration in claude-tooling's
   `projects/agda-algebras/mcp.json` (the 2.8.0 wrapper, the agda-algebras
   v0.1 corpus, `make check` as the `check_project` gate), running agda-mcp
   built from agda-native-air `55781f9d` (main that day), selected with
   `AGDA_MCP_BIN`: thirteen tools.  The build the launcher otherwise finds in
   the main checkout dates from 2026-09-28 and lacks 23 server commits merged
   since (listed in [#249]); nothing rebuilds it when main moves.  [#242] is
   merged, so the launcher supplies `--cwd` and substitutes `${PWD}`.
+  **The same instructions and skills**.  claude-tooling [claude-tooling#27]
   is not merged, but its branch's installer ran on 2026-10-09 and linked, in
   every agda-algebras checkout, `AGENTS.md` to the agda-algebras `CLAUDE.md`
   and `.agents/skills` to the project skills, and linked
   `~/.copilot/copilot-instructions.md` and `~/.codex/AGENTS.md` to the global
   `CLAUDE.md`.  The trial worktrees got the same two per-checkout links by
   hand.  So the trials ran with that branch's links, before it merged.
+  **Headless runs**.  Copilot CLI 1.0.95 and Codex CLI 0.162.1, already
   installed (npm).  `copilot -p` ran with `COPILOT_ALLOW_ALL=true` (every
   tool allowed and the working directory trusted; its path check stays on),
   `git push` and `gh` denied, and `GIT_SSH_COMMAND=false`.  GPT-6.1 Sol ran
   at `xhigh` reasoning effort in both harnesses (the configured Codex
   default), Kimi K3 at `max`, its highest (it refuses `xhigh`).
+  **The transcripts** are each CLI's own.  Copilot keeps a session as
   `~/.copilot/session-state/<session id>/events.jsonl`, and with
   `--log-level debug` its log under `~/.copilot/logs/` holds every request
   it sent, which is where the claims below about what a model was shown come
   from.  The prompt, the launch script, the server binary, every session's
   events, the probes and the gate logs are kept outside the repository, in
   `~/git/formalverification/agda-native-air/field-test-243/` on the machine
   that ran them.
+  **The gate** is the project's own, run by the reporting session on each
   session's final state inside the checkout's `nix develop` (Agda 2.8.0):
   `make check`, `unused-imports`, `check-links`, `docstrings` and
   `corpus-stats-check`.  Two checks of the final file go with it: the stated
   declaration is present as given, and no escape hatch is used (no
   `postulate`, hole, unsafe pragma, or `OPTIONS` without `--safe`).

### GPT-6.1 Sol: every check through the server

+  **The numbers**.  8 min 39 s, 17 model turns, one premium request, and 32
   tool calls: 11 `view`, 7 `bash`, 3 `apply_patch`, 2 `skill`, 2 `glob`,
   2 `read_bash`, and 5 to the server.
+  **The server calls, in order**.  `definition_of` (15.5 s, to find the
   standard library's `⁻¹-involutive`); a first draft with the proof left as
   `?`; `get_goal` on it (1.3 s); `fill_hole` with the whole proof (17.4 s,
   `status: ok` for the first candidate); the accepted text written into the
   file; `check_file` (16.9 s, `success: true`); and `check_project`, which
   ran the library's `make check` (140 s, `success: true`).  That is the
   hole-driven loop the agda-algebras instruction file asks for, ending with
   the server's own gate.
+  **The shell** ran no `agda` on a file: one
   `nix develop --command bash -c 'command -v agda && agda --version'` to
   learn the toolchain, `make gen-links corpus-stats`, and
   `nix develop --command make unused-imports check-links docstrings
   corpus-stats-check site` for the gates the server does not run.
+  **Skills and instructions**.  Its first two calls invoked the project
   skills `scaffolding-a-module` and `typechecking-agda`, and it did what they
   say: it re-exported the module from the `Classical.Structures.Group`
   barrel and regenerated `docs/_links.md` and the corpus count.  It read the
   instruction file: it went to append its field report to agda-native-air's
   `docs/mcp-field-reports.md`, Copilot's path check refused the read, and it
   kept the report in its session files instead.
+  **What the tool answers caused**.  The session's report says of
   `get_goal`: "The goal itself was concise, but the context expanded the
   carrier and operations into lengthy interpretation terms."  Measured on
   the same hole, the context `get_goal` returned (Agda's `Normalised`
   display) is 1,326 characters against 168 in the `Simplified` display an
   editor uses, with `𝑮 : Group α ρ` unfolded into a 528-character Σ type;
   filed as [#248].
+  **The result**.  Left uncommitted (the prompt allowed either).  The gates
   pass, the statement is as given, and no escape hatch is used.

### Kimi K3: the server for the module, the shell for the library

+  **The numbers**.  19 min 27 s, 33 model turns, one premium request, and 42
   tool calls: 25 `bash`, 5 `grep`, 5 `view`, 2 `skill`, 2 `edit`,
   1 `create`, 1 `tool_search_tool`, and 1 to the server.  Most of the time
   was the model's (989 s of API time at `max`).
+  **Finding the server**.  Copilot gave K3 a deferred tool surface: its
   first request carried 22 tools, none of them the server's, and a reminder
   naming the 13 `agda` tools and telling it to search before calling one.
   K3's second call was `tool_search_tool` with the query `+agda`: the
   instruction file's Claude Code line (`run ToolSearch with query "+agda"`)
   carried out in Copilot's terms.  The next request carried 35 tools.
+  **The server call**.  After seven minutes of reading `Subgroups`, `Basic`,
   `Cosets` and `Centralizer`, it wrote the module whole and called
   `check_file` once (5.0 s, `success: true` on the first draft).  It used no
   other server tool.
+  **The shell** ran the library gate: `nix develop --command make check`,
   twice, the documentation gates, and the strict `make site`.  Between the
   two `make check` runs it saw deprecation warnings naming the base
   checkout's paths, traced them to the `_build` the reporting session had
   copied from that checkout (an interface keeps its warnings' paths),
   deleted three interfaces, and re-ran to see its module checked from its
   own path.  The diagnosis is right, and the artifact is the setup's, not
   the server's.
+  **Skills and instructions**.  It invoked `scaffolding-a-module` and
   `typechecking-agda` and did what they say, scanned its files for em-dashes
   (the house style), and committed in the form the attribution order asks
   for: author William, no co-author trailer, the body ending
   `🤖 AI-assisted development: Kimi K3 (Moonshot AI)`; the attribution hooks
   ([claude-tooling#34]) refused nothing.  It appended its field report to
   agda-native-air main's `docs/mcp-field-reports.md` with a shell `cat >>`,
   which Copilot's path check let through; the reporting session removed the
   appended text from main afterwards and kept it with the apparatus.
+  **The result**.  The gates pass, the statement is as given, and no escape
   hatch is used.

### What Copilot did on its side

+  **It waits for the server**.  Each session's first model request went out
   after the server connected, 15.5 s and 5.2 s after launch.  The launcher's
   `nix develop` is most of that (measured: the same binary run directly
   answers at once), filed as [#249].
+  **It drops a skill whose frontmatter is not strict YAML**.
   `copilot skill list` at a trial worktree loaded 29 skills and refused 17
   ("mapping values are not allowed in this context"), three of them this
   project's (`porting-base-to-setoid`, `writing-a-corpus-linter`,
   `writing-a-docstring-pass`): their descriptions hold an unquoted colon,
   which [claude-tooling#27]'s branch quotes.  The two skills this task
   needed loaded.
+  **It shows a model the server's instructions only in part, or not at
   all**.  No request to GPT-6.1 Sol carried the server's `initialize`
   instructions; Copilot sends them only for allowlisted servers, or under
   `--allow-all-mcp-server-instructions`.  K3's deferred-tools reminder
   carried their first 157 characters, cut mid-word.  Both models had the
   verdict contract from the tool descriptions, which state it per tool.
+  **Its path check is per tool**.  It refused `view` on the `.mcp.json`
   link (whose target lies outside the checkout) and on agda-native-air's
   field-report file, and passed a shell redirection to that same file.
+  **Verdict**.  Through Copilot, both models used the server for module
   checks with nothing but the instruction file to tell them to, and both
   kept the whole-library gate where the instruction file puts it (Sol through
   `check_project`, K3 through `make check`).  The task was easy: every first
   draft checked, so no session met the diagnostics a failed check returns.

## 2026-10-10, agda-native-air issue #243: Codex CLI on the one-step subgroup test (GPT-6.1 Sol)

The same task, commit, server build, instructions and gates as the Copilot
section above, in Codex CLI 0.162.1 with GPT-6.1 Sol at `xhigh`, run as
`codex exec --json`.  The answer here is the shell, and the reason is the
harness: the model looked for the server first, 8 ms before Codex had its
tools.

+  **The setup's differences**.  The registration is a hand-written
   `[mcp_servers.agda]` table in the worktree's `.codex/config.toml`: the
   agda-algebras registration with no `--cwd` and no `cwd` key, allowing 120 s
   to start and 7,200 s per call, and trusted for the run with
   `-c projects=…`.  The server's start-up banner put it at the checkout
   (`cwd: …/air243-trial-codex-sol`), which is [#242]'s acceptance check for
   Codex.  Codex's Linux sandbox does not start on this machine (every
   command fails with `bwrap: loopback: Failed RTM_NEWADDR: Operation not
   permitted`, as it did that morning in an interactive Codex session here,
   which escalated each command), so the run used
   `--dangerously-bypass-approvals-and-sandbox`, with `GIT_SSH_COMMAND=false`
   and an empty `GH_CONFIG_DIR` against a push.  The transcript is Codex's
   rollout, `~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-<time>-<id>.jsonl`,
   beside the `--json` event stream.
+  **The numbers**.  4 min 29 s; 19 code-mode `exec` steps holding 30 shell
   commands and 5 file edits; no server call; 1.26 M input tokens (1.17 M of
   them cached) and 9.7 k output (4.1 k of it reasoning).
+  **Why no server call**.  Codex 0.162.1 shows a model MCP tools only
   through its code mode's `ALL_TOOLS` array: the description the model
   reads names 14 built-in tools and none of the server's (the feature
   `tool_search_always_defer_mcp_tools` is fixed on), and the server's
   instructions are not sent (observed in a trace-level log of a probe
   session).  `codex exec` also sends its first request without waiting for
   a server.  The model looked in its first step:
   `ALL_TOOLS.filter(x=>/agda/i.test(…))` returned `[]` at 18:00:53.862, and
   Codex's log shows the server's 13 tools entering its catalog at
   18:00:53.870, 8 ms later, when Codex next resolved a step's tools (the
   server had been ready for 3.4 s).  The model wrote "No Agda MCP tools are
   exposed in this session, so I'll use the CLI loop" and did not look
   again.  Measured afterwards: with `required = true` in the table,
   `codex exec` held its first request until the server was up.
+  **The shell** did the work the first field report predicted:
   `nix develop --command agda src/Classical/Structures/Group/SubgroupTest.lagda.md`
   (green on the first draft), `make gen-links corpus-stats`, `make check`,
   the documentation gates with the strict site, and a last `agda` on the
   module and `make check`.
+  **Skills and instructions**.  Codex lists all nine project skills (with
   shortened descriptions); the model read `typechecking-agda`,
   `scaffolding-a-module` and `typechecking-agda-under-nix` with `cat` and did
   what they say (barrel, links, corpus count).  It read the instruction
   file: it looked for a ToolSearch capability, scanned for em-dashes, and
   appended a field report to agda-native-air main's
   `docs/mcp-field-reports.md` (removed afterwards and kept with the
   apparatus), which says "No agda-mcp tools were exposed in this session,
   and no ToolSearch capability was available."
+  **The commit**.  `feat: add the one-step subgroup test`, author and
   committer William, no co-author trailer, the body ending
   `🤖 AI-assisted development: GPT-6 (OpenAI)` (the model named itself
   GPT-6, not GPT-6.1 Sol).  Codex's own attribution instruction was off
   (`git_attribution: false` in its rollout), and the hooks refused nothing.
+  **The result**.  The gates pass, the statement is as given, and no escape
   hatch is used.  The proof is the same argument, nearly line for line, as
   the two Copilot sessions'.
+  **Verdict**.  The session ran the CLI loop because the server's tools
   reached its model late and only behind `ALL_TOOLS`, not because the model
   preferred the shell: it checked for them first.  Three changes would let a
   Codex session find the server: `required = true` in the generated Codex
   registration and an instruction-file line naming each harness's way to
   find a server's tools (both for [claude-tooling#27]), and a launcher that
   starts in under a second ([#249]).  Whether GPT-6.1 Sol then uses the
   server in Codex as it did in Copilot is a question for the next trial;
   the Copilot run suggests it would (inferred).

## 2026-10-11, agda-native-air issue #249: the launcher's fast path, measured (Claude Opus 5.5)

Not a proof session.  The session that gave `scripts/run-server.sh` its fast
path ([#249]) measured what the shell costs a client before the server
answers, the question the Codex section above left open.

+  **What was measured**.  Launch to ready: the wall time from spawning a
   registration's exact argv to the first stdout line that is the JSON-RPC
   response to `initialize` carrying `result.protocolVersion`, with the
   request written at once, as a client writes it.  agda-mcp's result begins
   with `capabilities`, so the driver parses each line rather than matching
   text (`scripts/python/launch_to_ready.py`; `make agda-mcp-launch-time`).
+  **The setup**.  claude-tooling's agda-algebras registration's arguments,
   with `--cwd ${PWD}` passed literally for the launcher to substitute,
   started from `~/git/ualib/agda-algebras/master` in the session's own
   environment (outside every dev shell); five runs each way; the launcher
   and the server built from the branch at 8b2f1ddc.  The `shell` rows leave
   `AGDA_MCP_BIN` unset, as every registration runs today; `fast` sets it;
   `direct` runs the binary itself, the floor.  Other sessions were building
   and testing on the same 20-core machine (load average 3.5 rising to 11).
+  **The numbers**, in seconds, are the following:

   | Path | Corpus | Launcher's tree | Min | Median | Max |
   |------|--------|-----------------|----:|-------:|----:|
   | shell | 224 MB | clean | 7.390 | 7.809 | 12.481 |
   | shell | 224 MB | one tracked file modified | 7.167 | 7.721 | 12.470 |
   | fast | 224 MB | clean | 3.942 | 4.118 | 4.496 |
   | direct | 224 MB | clean | 3.746 | 3.819 | 4.590 |
   | shell | none | clean | 4.246 | 4.624 | 5.165 |
   | fast | none | clean | 0.013 | 0.017 | 0.018 |
   | direct | none | clean | 0.018 | 0.019 | 0.022 |

   An earlier round the same evening, under a load average near 8, gave
   medians of 11.3, 12.1, 3.06 and 2.86 s for the first four rows and 3.29 s,
   13 ms and 22 ms for the last three: the shell rows move by seconds with
   the machine's load, and the fast path stays level with the bare binary.
+  **Where the shell's seconds go**.  One launch with the corpus, its stderr
   lines timestamped, took 5.45 s: Nix's own start 0.1 s; the shellHook
   2.3 s, of which the banner's `sbt` version probe was 2.05 s; `cabal
   list-bin` 0.06 s; the corpus 2.9 s.  The corpus loads as fast inside the
   shell's environment as outside it (2.8 to 3.9 s, three runs each,
   interleaved).
+  **The corpus is the ceiling**.  The issue's acceptance criterion, an
   answer within a second with the agda-algebras registration and
   `AGDA_MCP_BIN` set, holds for the launcher (17 ms without the corpus)
   and not for the registration as written, because the server loads its
   corpus before it answers `initialize`: 3 to 4 s for the 224 MB
   agda-algebras corpus, on either path.
+  **A dirty tree made no difference here**.  With one tracked file of the
   launcher's checkout modified, the shell path's median was 7.7 s against
   7.8 s clean; [#249]'s 32 s with a dirty main checkout was not reproduced,
   so the tree's state alone does not explain it (inferred).
+  **What a gate finds on each path**.  A scratch checkout whose Makefile
   prints what its recipe sees, asked through `check_project` with
   `target`: through the shell, the store's GNU Make 4.4.1, this
   repository's Agda 2.9.0 as `agda`, and the launcher's checkout's `agda/`
   as `$AGDA_DIR`; on the fast path, `/usr/bin/make`, no `agda` at all, and
   the session's `$AGDA_DIR` (`~/.config/agda`).  Neither is agda-algebras's
   own Agda, which is why the registrations name it with `AGDA=` in
   `--check-command`.
+  **Verdict**.  The launcher's side of [#249] is done: a registration that
   sets `AGDA_MCP_BIN` and passes `--agda-bin` waits for nothing but the
   server itself.  For the agda-algebras registration the server's own wait
   is the corpus load, so whether a Codex `exec` session now finds the tools
   in its first step depends on when Codex sends its first request, which
   these runs do not measure; without a corpus the 17 ms precedes any model
   request (inferred).  Two changes would close the rest: `required = true`
   in a generated Codex registration ([claude-tooling#27]), which waits
   however long the server takes, and a server that answers `initialize`
   before it loads its corpus.  On the shell path, 2 of the 2.3 s the
   shellHook took in the timestamped launch were the banner's `sbt` probe,
   which a launch does not need.  No registration
   takes the fast path until its `env` block names the server;
   claude-tooling's four have none yet.

[#242]: https://github.com/formalverification/agda-native-air/issues/242
[#243]: https://github.com/formalverification/agda-native-air/issues/243
[#248]: https://github.com/formalverification/agda-native-air/issues/248
[#249]: https://github.com/formalverification/agda-native-air/issues/249
[claude-tooling#27]: https://github.com/williamdemeo/claude-tooling/issues/27
[claude-tooling#34]: https://github.com/williamdemeo/claude-tooling/pull/34
[ualib/agda-algebras#598]: https://github.com/ualib/agda-algebras/pull/598
[`flrp-agda-mcp-improvements.md`]: feedback/flrp-agda-mcp-improvements.md
