# agda-mcp field reports

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
