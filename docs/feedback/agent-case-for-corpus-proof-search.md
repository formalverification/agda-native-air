<!-- File: agda-native-air/docs/feedback/agent-case-for-corpus-proof-search.md -->
<!--
  Provenance: written by a Claude Code session (model: Claude Fable 5) working
  in ualib/agda-algebras, at William's request, immediately after the RP-3
  session that produced agda-algebras PR #561.  It is the consumer-side
  counterpoint to flrp-agda-mcp-improvements.md in this directory: that
  document reconstructed why an earlier session never called agda-mcp; this
  one reports what changed once sessions did, and argues from that experience
  for corpus-level proof search.  Per the request, the author did not
  re-investigate this repository's current state before writing (it noticed,
  and deliberately did not read, the merged proof-search-loop PR #126), so
  everything here is calibrated against the agda-algebras experience, not
  against what this repository may already have built.
-->

# An agent's case for agda-mcp and corpus proof search

The question asked: could this project (the agda-mcp, proof search over a corpus) eventually become very useful to an agent working on a project like `ualib/agda-algebras`?  The short answer is yes, and more pointedly: based on how sessions actually spend their time, scope-aware retrieval plus bounded term search over that corpus is the single highest-leverage addition available for agent-driven Agda development there.  The rest of this document is the evidence and the design consequences, graded by how directly each claim was observed.

## 0.  Provenance and calibration

+  **Directly observed, current session pair** (agda-algebras issue #460, PR #561, 2026-08-29/30): roughly 1200 lines of new literate Agda across three new or heavily extended modules, plus an in-place repair of a core definition (`Statement-C`) with two downstream consumers; about ten `check_file` calls; four failing checks in total, each repaired after a single reading of the diagnostics; warm checks 7–9 s, cold checks 17–35 s, against full-library builds on the order of ten minutes.
+  **Directly observed, earlier sessions, via the session memory of the agda-algebras project**: `exports_of` with `module=""` used as the validation oracle for a corpus linter; the interaction lane exercised there.
+  **Context from the sibling document**: `flrp-agda-mcp-improvements.md` records an RP-2 session that had the server loaded and never called it.  Between that session and this one the calculus flipped; § 1 says why.
+  **Opinion, clearly marked as such**: everything in §§ 3–6 about proof search is extrapolation from observed failure modes, not measurement of an existing search tool.

## 1.  What the agda-mcp already changes for an agent

The headline is not speed, although the speed matters: a 7–35 s `check_file` against a ten-minute `make check` is the difference between type-checking after every block and type-checking twice a day, and the RP-3 session type-checked after every block.

The headline is that the structured diagnostics attack an agent's dominant failure mode, which is not slow typing but **misdiagnosis followed by thrashing**.  Concretely, from this session:

+  An `UnsolvedMetaVariables` report whose `involved.metaTypes` payload showed the metas were the *proof components* of an implicit record argument.  That is a known disease in this codebase (implicit interval endpoints), and the payload identified it in one read; the fix (make the subjects explicit) was mechanical.  Raw batch output would have shown the same information smeared across a hundred lines, and earlier sessions demonstrably took longer to see through it.
+  `AmbiguousName` and `NotInScope` errors carrying candidate lists, which turn a name error into a one-edit fix with no grep round.
+  A one-character error range that pinpointed an argument made uninferable by reduction (a constant meet on `Fin 1` erased the argument from the goal).  Position precision is what made that diagnosis instant.
+  The verdict discipline: `success` derived from the exit code, never from message text, with masked-failure detection.  This removes an agent's ability to talk itself into "probably green", which is a real hazard when the agent is also the one writing the summary of its own work.
+  The project echo (which root, which libraries, `rootSource`) made cross-worktree resolution verifiable at a glance; the server was rooted in a different repository and still resolved the agda-algebras worktree correctly via nearest-agda-lib, zero configuration.

One honest limit observed: the hole-driven tools (`get_goal`, `fill_hole`) went unused this session, and that was the right call rather than an adoption failure.  When the agent can read the relevant sources into context and design the proof whole, batch write-then-check wins; holes pay when the goal shape is unknown.  A large context window lets an agent substitute reading for asking to a degree a human cannot.  But that substitution has a ceiling: it stops working when the library outgrows what can be read per question, and agda-algebras (320 files, climbing) is crossing that line.  Which is exactly where § 3 begins.

## 2.  Where the time actually went: the retrieval gap

An audit of the RP-3 session's time is the core datum.  Almost none of it was inventing mathematics.  A large fraction was **discovering what already exists in the library and what it is called**, entirely by grep plus file reading.  The real queries of that one session, verbatim in spirit:

+  Is interval equality (`_≈ᵢ_`) a pair of inclusions, and in which component order?
+  What does `Subᴸ`'s order relation unfold to?  (Answer: `proj₁ B ⊆ proj₁ C`, found by reading `Setoid/Subalgebras/CompleteLattice`.)
+  What is the shape of `TopOf` / `BottomOf`, and do concrete extremum witnesses exist for the two-element chain?
+  Does the library contain a trivial group anywhere?  (It did not; one was built.)
+  Does a covers-to-order-matrix closure already exist on the Python side?  (It did, but tied to another workflow; a local one was written.)
+  What are the exact argument order and law count of `eqsToGroup`?

Each answer cost one to three tool calls plus reading, at tens of seconds to minutes each, and there were more of these than there were proof obligations.  This is the gap retrieval fills.  A scope-aware, type-directed query answered by the type checker rather than by text matching ("terms of this type constructible in scope here", "lemmas whose statement mentions both `TopOf` and `OrderIso`", "any inhabitant of `IsChain₂ ?`") would have collapsed each item to one call, and a session like this one would use such a tool tens of times.  Text search cannot do this job: the library's names are principled but not guessable (`1ˢ-maximum`, `sub-ε-closed`, `chain₂-top?`), and the thing the agent knows is the *type*, not the name.

## 3.  The case for bounded term search at holes

The second observation is about the proofs themselves.  Most obligations in the RP-3 modules were plumbing: monotonicity case splits, round-trip chains, transport along `≤-reflexive`/`≤-trans`, projection chasing.  These are compositions of depth two or three over a small ambient lemma pool, which is exactly the regime where bounded search beats token-by-token generation, and with an asymmetry that matters more for an agent than for a human:

+  **A found term type-checks by construction; a written term merely probably does.**  Every hand-written obligation costs a check round-trip (about 30 s plus tokens) with some failure probability; a search that succeeds even half the time at such holes strictly dominates on both latency and, more importantly, on *trust*: the agent's report "this hole was discharged by search" needs no further verification, while "I wrote this term" always does.
+  **Negative answers are nearly as valuable as hits.**  A trustworthy "no term of this type exists at depth ≤ k over this pool" tells the agent to write the helper lemma instead of continuing to hunt.  Several of § 2's queries were really this question, and the session resolved them by exhausting greps, which is slow and never fully convincing.

## 4.  Design requirements this consumer would defend

From the failure modes above, in priority order:

1.  **Checked terms only.**  Search must return elaborated, type-checked terms (or nothing), never plausible suggestions; otherwise it relocates the verification burden instead of removing it, and the agent is back to one check round-trip per candidate.
2.  **Scope-awareness through the checker.**  The query runs at a position (a hole, or a file's top level) with that scope's imports and locals, exactly the way `type_of`/`definition_of` already work.  A corpus-global index that ignores scope will return unusable answers in a library with per-module `open ... using` discipline.
3.  **Honest negatives with stated bounds.**  "Nothing at depth 2 over 400 lemmas" is actionable; "nothing found" is not.
4.  **Latency that beats the alternative.**  The bar is the agent's current grep-plus-read loop, tens of seconds; a retrieval call should be interactive-lane fast, and a term search should be bounded and report its budget.
5.  **Surface it as MCP tools beside `get_goal`**, so the natural agent loop becomes: open hole, `get_goal`, `search_term` at the hole, `fill_hole` with the result.  That loop would also finally make the hole-driven style the *cheapest* one for an agent, which today it is not (§ 1).

## 5.  The corpus coupling, which is specific to agda-algebras

agda-algebras is deliberately curated as a vetted corpus: one canonical form per concept, named helper lemmas over inlined rewrites, explicit signatures on every public definition, prose paired with statements.  That discipline is precisely the index shape retrieval exploits, so the two projects reinforce each other: the corpus rules make search work, and working search makes the corpus rules cheap for agents to maintain (a found lemma is a reused lemma, which is the anti-duplication rule enforced for free).  There is also a measurement opportunity: the SLR certificate tree and the FLRP modules give a large, uniform population of solved obligations against which a search tool's hit rate can be benchmarked before it is trusted in sessions.

## 6.  What it will not do, stated plainly

Search shrinks the plumbing denominator; it does not touch the insight numerator.  The genuinely mathematical steps of the RP-3 session (noticing that the unguarded statement (C) admits a degenerate canopy, the padding instantiation, the oracle-subgroup argument for why maximality data is classical) were design work, and no retrieval or bounded search would have produced them.  The right expectation is: sessions spend their tokens and attention on those steps, and nearly nothing on § 2's ledger.  On the observed session profile, that is most of the time back.

## 7.  Sequencing, if this consumer were choosing

1.  Type-directed retrieval over the already-checked corpus, scope-aware, as an MCP tool.  Highest value per unit of build effort; useful even with no synthesis at all.
2.  Bounded composition search at holes over a curated lemma pool, returning checked terms, with honest negatives.
3.  Only then, anything cleverer (premise selection, learned ranking); ranking quality matters far less than soundness and latency at this stage, because the agent can triage a handful of checked candidates itself.
