<!-- File: docs/notes/browser-ide-proposal.md -->

# A browser workbench where people, models, and Agda build proofs together

+  **Status**: proposal, not adopted.  Nothing here is scheduled; the order of
   work at the end is a suggestion.
+  **Date**: 2026-09-23.
+  **Origin**: a design conversation after the demo page ([#85], PR [#166])
   and the site skeleton ([#169], PR [#181]) landed, prompted by the source of
   <https://plfa.isotopy.xyz/> being shared by its author, William's
   colleague at IO.
+  **What it proposes**: a web-based Agda IDE with the type-checker loaded by
   default and everything else a plugin (libraries, corpora, models, tools);
   a client-side tool surface with `agda-mcp`'s contract so a model can work
   in it; and a proof-design view that renders a development as a diagram at
   two levels, the theory and the single proof, generated from the checked
   source and edited through Agda's own interaction commands.

## Summary

Agda is a good instrument for one theorem at a time.  It is a poor one for
holding a development of many lemmas across several theories in one mind, and
its editors give a person and a model no shared surface to work on together.
This note proposes a browser workbench that does three things nothing in the
project does today: it runs Agda locally in the browser with a pluggable set of
resources; it offers a model the same verdict-first contract `agda-mcp` offers,
client-side, against those resources; and it shows a development as a diagram
that is always a rendering of the checked source, never a drawing beside it.

Two facts make this cheaper than it sounds.  A browser Agda IDE already exists,
is MIT-licensed, reproducible, and built on the same upstream this project's
wasm measurements used ([`plfa-playground`]).  And the pieces this project
built for other reasons are the pieces the workbench needs: a tool contract
whose value has now been measured ([#162]), a lane judgment whose parity with
the batch verdict has now been measured ([#163]), two corpora that carry the
dependency data a theory diagram is drawn from, and a benchmark whose fifty-five
proofs are the right size to settle how a proof diagram should look.

## What already exists

### The runtime: `plfa-playground`

[`plfa-playground`] is a complete Agda 2.8 editing environment that runs in a
browser tab with no server, MIT, pushed 2026-09-01.  What it has, read from
its source rather than its page:

+  **The compiler** is the Agda Language Server compiled to WASI with Agda's
   JSON interaction mode enabled (`als-2.8ext.wasm`, 32,996,332 bytes,
   10,188,407 gzipped), built from pinned revisions
   (`agda-web/agda-language-server` `e65419f8`, `agda-web/agda` `e2f8c694`,
   `ghc-wasm-meta` `c3f44696`, 9.10 flavour) by a script that refuses to
   build a patched Agda and records the binary's SHA-256.  It descends from
   `agda-web/als-demo` (Andy Pan), the lineage this project's own wasm
   measurements used.
+  **Two workers**: the language server under a WASI shim in one, an
   in-memory filesystem holding the bundled standard library in the other,
   joined by single-producer single-consumer buffers over a
   `SharedArrayBuffer`.  That is why the host must send
   `Cross-Origin-Opener-Policy: same-origin` and
   `Cross-Origin-Embedder-Policy: require-corp` on every route; the live site
   does, from Cloudflare, and the repository ships a service-worker fallback
   for a host that cannot.  Plain batch `agda` needs neither, measured in the
   `measuring-agda-under-wasi` procedure; only a language server's shim
   blocks on stdin through shared memory.
+  **The editor** is CodeMirror 6 with the `agda2-mode` chords and the
   Unicode input method; goals, context, infer, normalize, give, refine, and
   case-split are all there, and case-split edits the source and re-checks.
+  **The give rule**: an edit wholly inside one live goal goes through
   `Cmd_give`; a declaration, import, or multi-goal edit falls back to a full
   `Cmd_load`, "so changed code is never silently accepted from a stale
   result".  Goal edits take 20 to 60 ms; a warm declaration edit averages
   3.01 s across all 25 PLFA chapters.
+  **Libraries as archives**: any ZIP with sources under a library root and
   interfaces under `_build/2.8.0/agda/`, stored rather than deflated
   (interfaces barely compress and mount much faster stored), mounted through
   a public `mountDriveArchives()` hook; Agda's own hash check rejects a stale
   interface.  PLFA ships as 26 per-chapter deduplicated interface archives
   (9,122,863 bytes) chosen by a dependency index, so a visitor mounts only
   the closure of the chapter they open.  The standard library's sources are
   1,997,897 bytes zipped.
+  **Persistence**: sources and generated interfaces in a versioned IndexedDB
   cache; autosave; a Playwright benchmark over every chapter.

What it lacks is exactly this proposal's list: a plugin model beyond the one
hook, a model, and any view above a single file.

### The pieces this project has built

+  **A tool contract, and a measurement of what it is worth**.  `agda-mcp`
   offers fourteen tools over stdio ([ADR 0002]): the proof-state tools
   (`get_goal`, `fill_hole`, `check_file`, `get_diagnostics`,
   `check_project`), the lane queries (`type_of`, `normalize`,
   `resolve_name`, `definition_of`, `exports_of`), and the corpus tools
   (`search_by_name`, `search_by_type`, `get_dependencies`,
   `search_in_scope`).  [#162] measured the server against a shell holding
   the same `agda`, three arms of Sonnet 5 over the 55 obligations,
   2026-09-21.  Offered both instruments, the subject took **every one of its
   55 verdicts from `check_file`** and ran `agda` on the shell not once; and
   the knowledge tools collapsed beside a shell (`definition_of` 19 calls in
   the server arm, 0 with a shell; `search_by_name` 18 and 1; `exports_of` 11
   and 2; `type_of` 34 and 11) because `grep` over the library's source
   "needs no prior knowledge of where a thing is while `definition_of`
   answers where a definition is and not what it says."  The shell arm solved
   50 and restated 0 against the server arm's 47 and 6: a subject that reads
   a source constructs a proof where one that queries a name cites the lemma.
   The reading for a workbench is exact: **the verdict is what a model wants
   from the tools, and the source is what it wants from a library.**
+  **A lane judgment with measured parity**.  [#163] (PR [#174]) replayed
   80 distinct (obligation, candidate) pairs, every archived `fill_hole` a
   frontier model issued plus the golds, through `Cmd_give` on the persistent
   interaction lane and through the batch `fill_hole`, with and without
   `--safe`: **zero disagreements** on the committed candidates, two on the
   deliberate cases, both explained on the issue.  The issue's own probes put
   a give at 1.4 to 4.6 ms and the reload that puts the hole back at about
   220 ms, against 2.6 s for a batch judgment.  In a browser the lane is the
   only fast judgment there is, so this is the measurement that says a
   browser can judge a candidate in milliseconds without lying.
+  **The state model**.  [ADR 0001] § 3 defines proof search over a
   conjunctive set of obligations, one per open hole, with moves that refine a
   hole with a lemma, split it, or close it, judged by `fill_hole`.  That is
   the same state a proof diagram has (open leaves) and the same moves a
   person makes at one.
+  **Two corpora with dependency data**.  `agda-strux` exports every
   definition's elaborated type as a structural AST, its body's exact `Def`
   and `Con` references (`bodyRefs`), and its dependencies; the standard
   library corpus has 55,576 rows and agda-algebras 13,123, and each has a
   module graph from `agda --dependency-graph`.  A theory diagram is drawn
   from this without running Agda at all.
+  **A benchmark whose proofs are the right size**.  Fifty-five obligations
   with checked golds, most of them one to five lines, are where the
   elision rules of a proof diagram get settled before anyone edits in one.
   One number from [#163] to carry: for 16 of the 55, the committed gold is a
   multi-clause strategy that no single hole-filling judgment can express.
   Those sixteen are what case-split in a diagram is for.
+  **A demo page and its replay format** ([#85]): a session rendered as the
   model's words, its calls, and the server's answers in full, with the
   judge's verdict beside it.  That is already the right rendering of "what
   the model did in the workbench".
+  **An import-closure discipline** ([`docs/import-closure.md`]): what an
   import costs to ship, and the rule that a byte-budgeted consumer carries
   its own trimmed copy rather than reshaping the corpus.  A browser is that
   consumer.

## The design

### 1.  Fork the runtime

Fork [`plfa-playground`] rather than start from `als-demo` or from the plain
batch wasm.  Its license permits it, its build is reproducible, and the three
things this proposal adds are the three it lacks.  Keep its give rule, its
archive format, and its two-worker architecture; the cross-origin isolation
it needs is a hosting constraint (a host that sets response headers, which
GitHub Pages is not) and not a design one.

Keep the batch lane too.  ADR 0002's two-lane policy exists because
interaction mode is tolerant of open holes where batch Agda exits 42.  In the
browser both lanes are available, from two builds: the language server for
interaction, which is what the forked runtime ships (`als-2.8ext.wasm`, its
`compiler/build-agda-wasm.sh` builds `exe:als` and nothing else), and for
the verdict of record the plain `agda-opt.wasm` from `agda-web/agda-wasm-dist`
(release `v2.8.0-ghc9.10.3-r0`; 31,524,760 bytes, 9,732,314 gzipped; no
isolation needed; instantiated per check, about 40 ms), a second artifact
the fork has to carry beside the first and does not have today.  With
[#163]'s parity on the record (80 of 80 committed candidates; two constructed
disagreements, a `where`-shaped candidate the lane refuses and a partial fill
the two lanes read differently), the batch lane stays the authority for
commits and claims, and the lane's answer is exploratory: it steers the next
edit, and a `where`-shaped candidate or a partial fill goes to batch before
anything is claimed.

### 2.  The browser is the tool server

`agda-mcp` is a native process and cannot run in a page.  Its tools are thin,
and every one of them has a browser-side equivalent in the forked runtime:

| tool | in the browser |
|---|---|
| `get_goal` | `Cmd_goal_type_context` on the lane |
| `type_of`, `normalize` | `Cmd_infer`, `Cmd_compute` on the lane |
| `resolve_name`, `exports_of` | `Cmd_why_in_scope`, `Cmd_show_module_contents` |
| `fill_hole` | `Cmd_give` with the reload, parity per [#163]; the batch wasm (the second build, § 1) for the record |
| `check_file`, `get_diagnostics` | `Cmd_load` and its diagnostics; the batch wasm (the second build, § 1) for the exit code |
| `search_by_name`, `search_by_type` | queries over a mounted corpus JSONL |
| `search_in_scope` | the corpus query, then the file's import surface and `Cmd_infer` on the lane to type each accepted rendering in that scope, the three steps the native tool takes; the corpus alone answers neither what the file can name nor what Agda says its type is |
| `get_dependencies` | the row's `dependencies` (and the one-hop neighborhood with `expand`) over the mounted corpus JSONL, heuristic as the corpus cards say; exact body references are a separate field the published corpora do not carry (§ 4) |
| `definition_of` | `Cmd_why_in_scope`, then **the source itself**, which is mounted |
| `check_project` | **unsupported** until the multi-file item under "What is hard" lands: a project gate needs a mounted `.agda-lib` and every module's interface, and `Cmd_load` on one file is not that gate |

The last row is the one [#162] decided.  The measured gap in the native tool,
that it answers where a definition is and not what it says, closes in a
browser for free, because the library's source is on the virtual filesystem
and a full-text search over it is a few lines.  So the browser surface offers
what the shell arm had (the text) and what the server arm had (the structured
verdict) at once, which is the `both` arm, the best column in that table.

The contract is ADR 0002's, kept word for word where it matters: a verdict is
an exit code and never a reading of diagnostics text; every answer names the
tree it checked; a candidate judged on the lane says so and carries no verdict
block.  A model then works in the workbench through ordinary tool calling,
client-side, with no backend.

### 3.  The model, and the rule that does not change

+  **Default**: a frontier model through the user's own key, behind a consent
   gate that says exactly what leaves the browser and when.  The key is a
   secret inside a page that also loads plugins, so it never lives in the
   page's own JavaScript realm: a provider frame on its own origin (or, where
   a local process is acceptable, a bridge outside the browser) holds it and
   forwards requests and answers; plugins run in sandboxed frames or workers
   with no path to it; and the threat, a script on the workbench's origin
   reading or reusing the key, is stated in the gate's own words.  This is
   the one place source leaves the tab, and it is the configuration the
   agent-in-the-loop measurements were made with.
+  **Optional**: a local model in the browser, as a plugin, labeled
   unmeasured.  The evidence for the tool contract is for frontier models
   only; Milestone 4's local-model work ([#27], [#28], [#29]) is the
   measurement a local plugin would need before it is offered as more than an
   experiment.
+  **Optional**: an external agent (a Claude Code session, say) attached to
   the workbench over a local bridge, so the page is its tool server.

The rule the whole project rests on carries over unchanged: **the model's
claims are never the verdict; Agda's are.**  A suggestion is a candidate; it
goes through `Cmd_give` or the batch lane; the page shows the verdict.  A
session is rendered the way the demo page renders one, calls and answers in
full, with the judge's reading beside it.

### 4.  The proof as a diagram

This is the part of the proposal that is new, and it rests on a correspondence
rather than an analogy.  Under propositions-as-types, a natural-deduction
derivation *is* the elaborated proof term: an application is an elimination,
a lambda is an introduction, a constructor is an introduction, a case split
is the elimination of an inductive type, and an open hole is an open leaf.
`agda-json` exports the definition's type as a structural AST (`typeAst`),
the proof term only as printed text (`body`), and the names the term refers
to (`bodyRefs`); no proof-term AST and no type at each node exist today.  So
the proof view has a prerequisite: the clause bodies exported through the
encoder the type already uses, and a typing pass that records the judgment
at each node, which agda-strux can produce because it links Agda as a
library.  With that export, a Gentzen-style diagram of an Agda proof is a
rendering of the checked term with the judgment at each node, and it cannot
drift from the proof, because it is generated from it; without it, the
judgments exist only at open leaves, where the interaction protocol reports
the goal.

Two levels, one source:

+  **The theory**.  Nodes are definitions; edges are "uses", of three
   provenances the view labels: exact, from `bodyRefs` (read from internal
   terms); approximate, from the corpus `dependencies` (tokens of the printed
   type, unresolved tokens and name collisions included, the caveat every
   corpus card states); and module edges from Agda's `--dependency-graph`,
   which is a load-order graph rather than the import relation.  This is the
   view that lets one mind hold a development of many lemmas.  It needs no
   Agda to draw, but only the approximate edges are on disk today: the
   published corpora (v0, v0.1) carry `dependencies` and the module graph for
   68,699 definitions and no body-level field at all (their cards say so;
   issue [#15]).  The extractor now emits `bodyRefs`, so the exact edges
   need a corpus cut made with it, which is a prerequisite of this view and
   not a property of the corpora as released.
+  **The proof**.  One definition's term as a derivation tree, types at the
   nodes, holes as open leaves.  A reference to a lemma is a leaf that links
   back out to that lemma's node in the theory view, and, because [#162] says
   reading a lemma's body is what turns a citation into a construction, the
   leaf shows the body on demand.
+  **Editing is the interaction protocol**.  At an open leaf, applying a rule
   is `Cmd_refine` with a lemma (new leaves are new holes), `Cmd_make_case`
   (branches), or `Cmd_give` (close).  Every diagram edit is a real command
   against the real checker, and the diagram re-renders from the re-checked
   term.  This is ADR 0001's obligation set and the search loop's move
   vocabulary; a person at the diagram, a model proposing at a leaf, and the
   loop share one state.

#### One mode, two registers

A design tool wants a sketch: "this theorem will follow from these three
lemmas, none proved yet, and the second will need two of its own".  It is
tempting to give the diagram a free-drawing mode for that and a strict mode
for the checked proof.  Do not.  Two modes are two truths, and a diagram that
can show an edge Agda does not know about is a diagram that can lie, which is
the one thing this project's instruments never do.

The sketch already exists inside Agda, in two places the checker itself
distinguishes:

+  **A hole is a sketch of a term**.  A scaffold of declarations whose bodies
   are holes is a checked plan: Agda type-checks every statement and every use
   between them, and refuses an ill-typed lemma before it is proved.  A
   statement not yet known is a hole in type position, `L : {!!}`, which Agda
   accepts and reports as a goal of type `Set _`.
+  **A hole's interior is a sketch of intent**.  The text inside `{! ... !}`
   is stored and shown and checked by nothing until it is given.  "This will
   use `L1` and `L2`" written inside a hole is a tentative dependency that
   Agda holds without believing, and `Cmd_give` is the moment it is believed
   or refused.

So the diagram has one mode and two registers, both read from the file: solid
for checked structure, dashed for hole interiors.  No node or edge appears
that is not in the source.  Prose planning belongs in literate Agda, which the
runtime already renders beside the code.

#### Scale, and why the benchmark comes first

Drawing is not the hard part; scale is.  An elaborated term carries implicit
arguments, instance resolution, and unfolding, and a raw rendering of one is
unreadable.  The design questions are elision (which nodes to hide) and
folding (which subtrees collapse to a lemma leaf), and they are questions
about real proofs.  The 55 golds are the corpus to settle them on, read-only,
before any edit is made in a diagram; their terms are already exported.

Precedents to study before designing, not after: Paperproof, which renders
Lean 4 proofs as trees and is the closest thing to this; the Incredible Proof
Machine, a browser tool for constructing natural-deduction proofs
graphically and the closest interface precedent; jsCoq and this project's own
wasm measurements for in-browser checking; and Isabelle's Isar for what a
readable large proof looks like as text.

### 5.  Plugins have a shape already

A plugin is a manifest and its archives, and the runtime's PLFA manifest and
dependency index are the template:

+  **kind**: library, corpus, model, tool;
+  **pins**: the Agda version, the library commit, the digest; exactly what
   the dataset cards and the agent-bench `protocol.json` record today;
+  **what it mounts**: library ZIPs in the archive format the runtime defines,
   with a per-closure split chosen by a verified closure index (the
   per-root node set, below under "What is hard"), never by the corpus
   module graph, so a visitor fetches only what the open module needs;
+  **what it registers**: tools and search indices;
+  **what it costs**: bytes, so the consent gate can say "install
   agda-algebras: N MB, from this origin" and mean it.

The agda-algebras v0.1 corpus release plus the library's interfaces is one
plugin, buildable now.  The standard-library corpus is another.  The scaling
wall is interfaces: a whole library's set is far larger than PLFA's 9 MB, and
[`docs/import-closure.md`] is the record of what the closures cost and of the
rule that the browser carries its own trimmed copies rather than reshaping the
corpus.

## What is hard

+  **Interfaces at scale**.  Per-closure archives are the only known answer,
   and the corpus's module graph is not the index for them: it is a
   load-order graph whose edges under-count imports, so a closure traversed
   from it can miss an interface.  The index is per root: the node set
   `agda --dependency-graph` writes for that root (complete for what Agda
   loaded; the method [`docs/import-closure.md`] records), or the import
   lists the interfaces themselves carry, verified by a cold check that
   mounts only the archive.  Measure before promising: the closure of one
   benchmark obligation is 5.9 MB gzipped after the prelude fix ([#168]), and
   agda-algebras is larger by an order.
+  **Rendering a real term**.  Elision and folding are a research-grade
   interface problem.  Start read-only and small.
+  **Source leaving the tab**.  Only to the model provider, only by consent,
   never by default, and the gate has to say so in the words a person would
   read.
+  **Multi-file projects** in a virtual filesystem, with `.agda-lib` and
   library registration.  The runtime handles one library well; a general
   project model is work.
+  **Honesty about the local model**.  It is unmeasured for this task, and
   the page must say so until it is not.

## Where it lives, and the order of work

This is larger than the project site ([#180]) and larger than the live
checker planned for williamdemeo.org, and it consumes both this repository
(the corpora, the exports, the contract, the benchmark, the archives) and the
runtime.  It belongs in a repository of its own under `formalverification/`,
eventually.  Not first.  First, in order of cheapness and payoff, each step a
thing that stands on its own:

1.  **The theory view, read-only, from the corpus alone**.  The agda-algebras
    definition graph in the browser: no Agda, pure data, and a natural demo
    for the project site.
2.  **The proof-term export**, the prerequisite § 4 names: the clause bodies
    through the encoder `typeAst` already uses, and the typing pass that
    records the judgment at each node; then a corpus cut that carries
    `bodyRefs`, for the theory view's exact edges.  Nothing in the proof
    view exists before this.
3.  **The proof view of one checked gold**, from that export.  Settle the
    elision rules on the 55.
4.  **Fork the runtime and add the tool surface**, checked against the
    archived sessions the way [#163] checked the lane: replay the archived
    calls through the browser surface and compare answers.
5.  **The model behind the consent gate**, sessions rendered in the demo's
    replay format.
6.  **Editing in the diagram**, starting with `Cmd_refine` and `Cmd_give` at
    a leaf, then `Cmd_make_case`.

Two rules to write down before step 1 and never relax: the diagram renders only
from the source, solid for checked structure and dashed for hole interiors,
and never from a model's description; and every measurement the workbench
states about itself comes from an archive, the way the demo page's do.

## References

+  [`plfa-playground`]: the runtime; <https://plfa.isotopy.xyz/> is its
   deployment.
+  [ADR 0001]: proof search on agda-mcp; § 3 the state model, § 9 the
   measurements.
+  [ADR 0002]: the agda-mcp server; decision 1 the two-lane policy.
+  [`docs/import-closure.md`]: what an import closure costs here, and the
   three rules.
+  [#85] / [#166]: the demo page and its replay format.
+  [#162] / PR [#175]: the attribution arms.
+  [#163] / PR [#174]: `Cmd_give` parity on the lane.
+  [#167] / [#168]: the fixture and prelude closures.
+  [#169] / PR [#181], [#180]: the project site.
+  [#27], [#28], [#29]: the local-model work a local plugin would need.

[`plfa-playground`]: https://github.com/SeungheonOh/plfa-playground
[ADR 0001]: ../adr/0001-proof-search-on-agda-mcp.md
[ADR 0002]: ../adr/0002-agda-mcp.md
[`docs/import-closure.md`]: ../import-closure.md
[#15]: https://github.com/formalverification/agda-native-air/issues/15
[#27]: https://github.com/formalverification/agda-native-air/issues/27
[#28]: https://github.com/formalverification/agda-native-air/issues/28
[#29]: https://github.com/formalverification/agda-native-air/issues/29
[#85]: https://github.com/formalverification/agda-native-air/issues/85
[#162]: https://github.com/formalverification/agda-native-air/issues/162
[#163]: https://github.com/formalverification/agda-native-air/issues/163
[#166]: https://github.com/formalverification/agda-native-air/pull/166
[#167]: https://github.com/formalverification/agda-native-air/issues/167
[#168]: https://github.com/formalverification/agda-native-air/issues/168
[#169]: https://github.com/formalverification/agda-native-air/issues/169
[#174]: https://github.com/formalverification/agda-native-air/pull/174
[#175]: https://github.com/formalverification/agda-native-air/pull/175
[#180]: https://github.com/formalverification/agda-native-air/issues/180
[#181]: https://github.com/formalverification/agda-native-air/pull/181
