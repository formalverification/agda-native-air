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
