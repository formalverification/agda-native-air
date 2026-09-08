# The agda-mcp interaction lane

File: `agda-native-air/docs/agda-mcp-interaction-lane.md`

Purpose: the design record for issue #75 — the second lane of the agda-mcp server, a persistent `agda --interaction-json` child per resolved project root, serving live scope, type, and definition queries as structured data.  This document states the two-lane policy, the wire protocol *as observed* under the pinned Agda 2.8.0 (probed 2026-08-19/20 inside `nix develop .#backend`; every exchange quoted below was captured from a live process, not transcribed from Agda's source), the process lifecycle, and what each existing module becomes.  It is written before the Haskell, and the implementation is expected to cite it rather than restate it.

## 1.  The two-lane policy

This is policy, not suggestion; tool descriptions and reviews should hold changes to it.

+  **Batch lane — verdicts.**  `check_file`, `check_project`, and `fill_hole`'s `status` keep their issue-#72 contract unchanged: the verdict is read from batch `agda`'s exit code, never from the interaction lane.  Interaction mode is tolerant by design — `Cmd_load` on a file with open holes *succeeds* and reports interaction points (§ 3.2 below), where batch `agda` exits 42 — which is precisely why the interaction lane must never decide a verdict.  The new tools' descriptions say this boundary out loud: they inform, and never decide a build verdict.
+  **Interaction lane — knowledge.**  A persistent `agda --interaction-json` child per resolved project root, speaking IOTCM commands, serving read-only queries: what is this expression's type, what does this name resolve to and why, where is it defined, what does this module export, what does this hole want.  None of these questions has an exit code, and none requires editing the file first — the "check a term without committing to it" property that § 3.3 of the feedback document names as what makes them worth a call.
+  **Lexical layer — demoted, not deleted.**  `AgdaMCP.Holes` remains the splicing engine (a pre-Agda source edit structurally needs a source view: `fill_hole` and the injection path must find a hole's span in the bytes they are about to rewrite) and the fallback for files Agda refuses to load.  It is never again the authority for anything Agda can answer; the parity tests keep it honest against the lane's `InteractionPoints`.

## 2.  The wire protocol, as observed

### 2.1  Framing

The child is spawned as `agda --interaction-json` and spoken to over stdin/stdout.  One IOTCM line per command on stdin; newline-delimited JSON objects on stdout, with two non-JSON line shapes interleaved:

+  `JSON> ` prompt markers.  Agda's reader thread prints one each time it consumes an input line, while a separate executor works through the queued commands — so the marker floats: it can stand alone, or prefix a response line (`JSON> {"kind":…}`), and it says nothing about command completion.  The reader strips a leading `JSON> ` (repeatedly) and ignores what remains if empty.
+  `cannot read: <line>` — the reply to an IOTCM line that did not parse.  Plain text, not JSON.  The process survives it and continues with the next command.

Everything else is a JSON object with a top-level `kind`.  The reader is keyed on `kind` and never on line position.  Kinds observed in the probes: `DisplayInfo` (with `info.kind` one of `Error`, `AllGoalsWarnings`, `GoalSpecific`, `InferredType`, `NormalForm`, `WhyInScope`, `ModuleContents`, `Version`), `InteractionPoints`, `HighlightingInfo`, `Status`, `RunningInfo`, `ClearRunningInfo`, `ClearHighlighting`, `JumpToError`.

Commands execute strictly in order: the reader enqueues, a single executor answers, so response streams never interleave across commands.  That yields the **sentinel discipline** the lane runner is built on: after every real command the lane sends `Cmd_show_version`, whose response —

    {"info":{"kind":"Version","version":"2.8.0"},"kind":"DisplayInfo"}

— is unmistakable and state-free; every response collected before it belongs to the real command.  No per-command-kind completion heuristics, no timeouts standing in for framing.

### 2.2  Startup noise

The child emits output before the first command when its startup configuration is inconsistent — observed with the flake's `agda` wrapper, whose `--library-file` names a registry without `agda-dojang` while `$AGDA_DIR/defaults` asks for it:

    {"info":{"error":{"message":"error: [LibraryError]\nLibrary 'agda-dojang' not found.\n…"},"kind":"Error","warnings":[]},"kind":"DisplayInfo"}
    {"direct":false,"filepath":"/tmp/…/agda2-mode…-0","kind":"HighlightingInfo"}
    {"kind":"Status","status":{"checked":false,…}}

This is once per process, not per load (verified against an empty stdin).  The lane flushes it by running one sentinel immediately after spawn, before accepting requests, so no command's response collection can misread startup noise as its own failure.

### 2.3  The IOTCM line and its escaping

    IOTCM "<absolute-file>" None Direct (<Command> …)

+  The second field is the highlighting level.  `None` suppresses the per-token `HighlightingInfo` payloads that otherwise dominate the stream (a `Cmd_load` of the 25-line `TwoHoles.agda` produced ten of them at `NonInteractive`); error highlighting and the startup trio still appear, and the reader ignores the kind either way.
+  Every embedded string — file paths, expressions, names — is a *Haskell string literal*: `show` is the escaper.  Probed: `"\x -> suc x"` is rejected whole (`cannot read: …`, because `\x` is not a Haskell escape) while `"\\x -> suc x"` works; `"\955 (x : Nat) \8594 x"` — `show`'s decimal escapes for `λ` and `→` — infers `(x : Nat) → Nat`; a newline ships as `\n`.  The lane builds every IOTCM with `show` and never with string concatenation around raw text.

### 2.4  `Cmd_load` — the state-establishing command

    IOTCM "<abs>" None Direct (Cmd_load "<abs>" ["-i", "<dir>", "--library-file=<registry>", "-l", "<lib>", …])

+  **The second argument is the per-load argv, and it must carry the resolved project flags.**  `Cmd_load "<file>" []` does not inherit a useful context: probed, it produced a `LibraryError` naming the wrapper's nix-store registry and checked the file against whatever remained.  The lane passes the same flag list the batch lane would run `agda` with — the server's flags plus `AgdaMCP.Project.projectExtraFlags` plus `fileDirIncludeFlags` — so a foreign-project query resolves against the same tree, by construction, as a batch check of the same file (issues #76/#103).
+  **A successful load ends with `InteractionPoints`**, preceded by `AllGoalsWarnings` carrying every visible goal's type — captured on `TwoHoles.agda`:

        {"info":{"errors":[],"invisibleGoals":[],"kind":"AllGoalsWarnings","visibleGoals":[{"constraintObj":{"id":0,"range":[{"end":{"col":9,"line":22,"pos":816},"start":{"col":5,"line":22,"pos":812}}]},"kind":"OfType","type":"Nat"},{"constraintObj":{"id":1,…},"kind":"OfType","type":"Nat"}],"warnings":[]},"kind":"DisplayInfo"}
        {"interactionPoints":[{"id":0,"range":[{"end":{"col":9,"line":22,"pos":816},"start":{"col":5,"line":22,"pos":812}}]},{"id":1,…}],"kind":"InteractionPoints"}

    The ranges are 1-based (line, col) plus a character offset `pos`, in the coordinates of the file as written — literate coordinates for literate files (verified on `LiterateMd.lagda.md`: its `{! zero !}` hole reports `start 22.5`, exactly where `Holes.findHoles` puts it).  A load *succeeding on a file with open holes* is the tolerance § 1 banishes from verdicts.
+  **A failed load ends with `DisplayInfo`/`Error` plus `JumpToError`, and no `InteractionPoints`** — captured on a type error:

        {"info":{"error":{"message":"/…/TypeErr.agda:4.7-10: error: [UnequalTerms]\nSet !=< Nat\nwhen checking that the expression Nat has type Nat"},"kind":"Error","warnings":[]},"kind":"DisplayInfo"}
        {"filepath":"/…/TypeErr.agda","kind":"JumpToError","position":67}

    A parse error has the same shape.  The process survives and accepts further commands.
+  **Nothing rewrites the file.**  `HoleVariants.agda` (holes in all four syntaxes, `?` included) and `LiterateMd.lagda.md` hash identically before and after a load; `?` holes are not expanded on disk.
+  `RunningInfo` lines carry Agda's `Checking M (path).` progress, indented by import depth — the same lines `AgdaMCP.Agda.progressModules` already parses from batch output, and the lane's evidence for "this call re-checked the file from source".  That evidence is only as good as the channel: a per-load argv carrying an effective `--trace-imports=0` emits no `RunningInfo` at all (probed — the load went straight to `AllGoalsWarnings`), so `AgdaMCP.Interaction.loadCheckedFromSource` reads a line naming the file as a re-check and answers "unknown" whenever the evidence could not arrive: the argv it was handed muted the channel (issue #114; the grammar and its measurements are in `docs/agda-mcp-ask-agda-audit.md` § 4), or the load failed before Agda announced this file — a header that does not match its file name, a parse error — which establishes no interface reuse either.  Only a load that *succeeded* in silence over an open channel reads as reuse, which is the batch signal's own reading of silent success.

### 2.5  The query commands

All verified live; each answer arrives as one `DisplayInfo` whose `info.kind` names it.  Toplevel variants answer in the scope of the loaded file's top-level module; goal variants take an interaction-point id and answer in the scope at that goal, locals included.

+  `Cmd_infer_toplevel Normalised "<expr>"` → `InferredType`.  The inferred type is in the `expr` field (so named on the wire); `commandState` echoes the current file and its load mtime:

        {"info":{"commandState":{"currentFile":["/…/TwoHoles.agda","2026-08-20T02:57:51.892054865Z"],"interactionPoints":[0,1]},"expr":"Nat","kind":"InferredType","time":null},"kind":"DisplayInfo"}

    The expression need not appear in the file — the § 4 moment — and an ill-typed expression answers with `DisplayInfo`/`Error` whose positions are in the *expression's own* coordinates (`1.1-4: error: [CannotApply] …`), not the file's.
+  `Cmd_infer Normalised <goalId> noRange "<expr>"` → `GoalSpecific` wrapping `goalInfo:{"expr":"Nat","kind":"InferredType"}` — same answer, goal scope.
+  `Cmd_compute_toplevel DefaultCompute "<expr>"` → `NormalForm` (`"expr":"2"` for `implicitOnly {suc 1}`); `Cmd_compute DefaultCompute <goalId> noRange "<expr>"` is the goal variant.
+  `Cmd_why_in_scope_toplevel "<name>"` / `Cmd_why_in_scope <goalId> noRange "<name>"` → `WhyInScope` with `thing` (the name as asked) and `message`, the provenance prose:

        g is in scope as
          * a defined name TwoHoles.g brought into scope by
            - its definition at /…/TwoHoles.agda:21.1-2

    One `*` bullet per candidate — an ambiguous name lists them all, each with its own chain (captured on the two-`open` fixture: `AmbigHole.Source1.amb` via `the opening of Source1 at …:9.6-13` then `its definition at …:4.3-6`, and likewise for `Source2.amb`).  A re-export chains through every hop — captured on the barrel fixture:

        originalName is in scope as
          * a defined name ReexportOrigin.originalName brought into scope by
            - the opening of ReexportBarrel at
            - the opening of ReexportOrigin at
            - its definition at /…/ReexportOrigin.agda:14.1-13

    Chain steps can carry an empty location (the blank `at` above — those openings live in other modules' scope info).  A local variable answers `a variable bound at <file>:<L>.<C>-<C'>`, only at a goal.  An unknown name answers the same kind with `message` `"<name> is not in scope."` — not an error.  The `filepath` field in this response is the current file's *directory*, not an answer; the message is the answer.
+  `Cmd_show_module_contents_toplevel Simplified "<module>"` / `Cmd_show_module_contents Simplified <goalId> noRange "<module>"` → `ModuleContents`:

        {"info":{"contents":[{"name":"_+_","term":"Nat → Nat → Nat"},…],"kind":"ModuleContents","names":["Nat"],"telescope":[]},"kind":"DisplayInfo"}

    The module must be *in scope in the loaded file* — `Agda.Builtin.Nat` answers in a file that imports it and `NotInScope` in one that does not, and the loaded file's own top-level module name is itself `NotInScope`.  The empty string names the file's own top-level module and lists its definitions (`g`, `h`, `implicitOnly` for `TwoHoles`).
+  `Cmd_goal_type_context Normalised <goalId> noRange ""` → `GoalSpecific` with the goal's type and its context as data — no source mutation, no injected macro:

        {"info":{"goalInfo":{"boundary":[],"entries":[{"binding":"Nat","inScope":true,"originalName":"x","reifiedName":"x"},{"binding":"Nat","inScope":true,"originalName":"y","reifiedName":"y"}],"kind":"GoalType","outputForms":[],"rewrite":"Normalised","type":"Nat","typeAux":{"kind":"GoalOnly"}},"interactionPoint":{"id":0,…},"kind":"GoalSpecific"},"kind":"DisplayInfo"}

+  `Cmd_show_version` → `Version` — the sentinel (§ 2.1).

### 2.6  Scope model gotchas, probed

+  **A hole-free file's toplevel scope loses file-local `open`s.**  After loading a file whose last-value declarations sit under `open Source1` / `open Source2` and which has *no* interaction points, `Cmd_why_in_scope_toplevel "amb"` answers `not in scope` — while the identical file plus one trailing hole answers with both candidates and full chains, and so does the goal variant.  Qualified names (`Source1.amb`) resolve either way, as do names opened from *imports* (`zero` via `open import Agda.Builtin.Nat`, its opening location degraded to blank).  The same degradation shows in *rendering*: a type the source-checked scope printed as `Nat` prints fully qualified (`Agda.Builtin.Nat.Nat`) once the file is re-loaded from its interface, so two queries can render one type differently depending on load provenance.  Consequence: `resolve_name` prefers a goal-scoped query when the file has any interaction point, and the `ScopeAmbiguous.agda` fixture carries a hole on purpose.
+  **The ambiguity error is itself an answer.**  `Cmd_infer` on an ambiguous unqualified name fails with the field session's exact shape — `[AmbiguousName] Ambiguous name amb. It could refer to any one of Source1.amb bound at <loc> Source2.amb bound at <loc>` — and on a near-miss with `[NotInScope] … (did you mean 'Source1.amb' or 'Source2.amb'?)`.  `resolve_name` composes these: `why_in_scope` first; when that says not-in-scope, an `infer` of the bare name recovers the candidate list, and each suggested qualified spelling can be `why_in_scope`d for its chain.
+  **No auto-reload on change; auto-load on switch.**  A query after an on-disk edit answers against the *old* state (probed: a definition appended to the file is `not in scope` until an explicit `Cmd_load`).  Conversely, a toplevel query naming a file that is not current triggers a load of it — with an argv the lane did not choose — so the lane always issues its own explicit `Cmd_load` first and never leans on the implicit one.  A query issued while the current file's last load *failed* replays the failure rather than answering stale (probed on a parse-error file), but the lane still gates queries on its own load bookkeeping so the failure surfaces once, structurally.
+  **A re-load re-checks.**  A file with open holes writes no interface, so `Cmd_load` of even an *unchanged* such file re-typechecks it (probed: two identical loads, two `Checking` lines), and switching files A → B → A re-checks A on return.  Re-loading only on evidence of change is therefore load-bearing for the economics, not a nicety.

### 2.7  Economics, measured

Probed on this session's hardware, disk-warm `.agdai` interfaces throughout (the honest comparison: the batch lane is disk-warm too).  The subject file imports `AgdaDojang.Debug` and `Data.Nat`.

+  Batch lane: `agda <flags> <file>` = 2.78 s, then 2.60 s on the repeat — paid *per call*, so five scope questions cost ~13 s.
+  Interaction lane: process start + `Cmd_load` = 2.59 s once; the same five knowledge queries after the load added less than measurement noise (2.580 s total for load *plus* all five, versus 2.589 s for load alone — each query is on the order of a millisecond).
+  Micro-fixture floor: a nine-command batch against `TwoHoles.agda`, load included, completes in 0.04 s of wall clock.
+  The #83 field test's shell baseline was a 10.0 s median per check.  The asymptotic claim for the tool descriptions, scoped to what a one-current-file lane can honestly promise: the first question about a file costs one load, and every further consecutive question about it is effectively free until the file changes or the lane's current file switches away — alternating between two files under one root pays the switched-to file's load each time (measured warm on the fixture pair: tens of milliseconds; a full re-typecheck for a holed file, which writes no interface).

## 3.  Process lifecycle

`AgdaMCP.Interaction` owns a registry of lanes, one per resolved project root.

+  **Key.**  The lane key is the `pcRoot` of the `AgdaMCP.Project.resolveProject` answer for the queried file — the same resolution, run per call, that the batch tools use, including its `ProjectMismatch` refusal.  Since #103/PR 104 a server is routinely asked about foreign checkouts, so multiple simultaneous roots are the design case, not an edge case: the registry is a map, not a slot.
+  **Spawn.**  `agdaBin cfg` with the single argument `--interaction-json`, inheriting the *server's* working directory exactly as the batch lane's one-shot `agda` does — the server's `--agda-flags` may name paths relative to that directory (the shipped `--library-file=agda/libraries` is exactly that), and the two lanes must resolve one file against one tree.  Project flags ride each `Cmd_load`, not the process argv, so one child serves every file under its root; the root keys the registry, it is not a chdir.  After spawn the lane flushes startup noise with a sentinel (§ 2.2) before its first real command.
+  **Requests.**  Serialized per lane under an `MVar`; each request is (ensure loaded → command → sentinel → collect by `kind`).  `ensure loaded` sends `Cmd_load` with the resolved argv iff the lane's current file differs from the request's, the file's stamp — mtime, size, and a content fingerprint, so a same-size rewrite under a preserved mtime still counts — changed since the lane last loaded it, the last load of it failed, or the client passed `reload: true` (the escape hatch for a changed *dependency*, which no stamp on the queried file can see).  The registry is safe for concurrent callers on distinct roots, but the stdio server loop that drives it is itself serial, so at most one request is ever in flight — capability, not yet behavior.
+  **Timeouts.**  Every request runs under one deadline (the server's `--timeout`, as in the batch lane), and every phase shares its remaining budget — the spawn's startup flush, the load, the query, and the pipe *writes* as well as the reads, since a child that stopped consuming stdin would otherwise block a large write forever.  On expiry the lane kills the child's whole process group by the issue-#77 ladder — SIGINT, then SIGTERM, then SIGKILL, each rung taken while the group still has members — reaps it, surfaces a structured timeout naming the bound, and marks the lane dead; the next request respawns it.  Killing rather than in-band cancellation is deliberate v1 simplicity: `Cmd_abort` exists but its interleaving with a queued reader is its own protocol study, noted as follow-on work.
+  **Crash and shutdown.**  A child that exits or closes its pipes mid-request surfaces as a structured failure naming the lane, the event, and the child's stderr tail — never as a bare `-32603`, the #101 lesson.  The lane is removed and respawned on next use.  A child found dead *between* requests (it crashed while idle) is replaced silently, its pipe handles closed but its ladder deliberately skipped: the ladder probes and signals the raw pgid, and a long-dead child's pgid may have been recycled by an unrelated process group.  Server shutdown latches the registry closed under its own lock — a later request is refused structurally (`event: "shutdown"`) rather than spawning a child nothing would stop, and a slot an in-flight request still holds is *waited for*, not skipped, so its lane cannot be restored into a registry nobody will drain again.  From `createProcess` to the registry, a spawning call owns its child under `mask`/`onException`, so a cancellation mid-spawn stops the child rather than leaking it.  An idle lane (no request for the configured idle bound) is shut down by closing its stdin, which Agda answers by exiting cleanly (probed: rc 0 on EOF).  Server exit closes every lane the same way.
+  **Echo.**  Every response carries the #72-style echo, in this lane's vocabulary: the `project` block (the same `ProjectContext` serialization the batch tools emit), the `command` block naming the child (`binary`, `args = ["--interaction-json"]`, `cwd` = the server's working directory the child inherits), and a `lane` block — root, child pid, whether this call spawned the child, whether and why it (re)loaded the file (`reused`, `first`, `switch`, `changed`, or `retry`), the load's own elapsed milliseconds beside the call's total, the child's reported Agda version, and the exact IOTCM lines this call sent, sentinel included, so a call can be replayed by hand.  Beside the `lane` block the response carries `checkedFromSource`, the batch tools' cache signal in this lane's vocabulary: `false` for a reused load, since no `Cmd_load` ran and nothing was checked, and *absent* when the answer's evidence could not arrive — a per-load argv that muted the progress channel, or a load that failed before Agda announced the file (§ 2.4, issue #114).  The one thing it never carries is a verdict: the tools' descriptions and their responses both say these calls inform and never decide a build verdict.

## 4.  What each existing module becomes

+  `AgdaMCP.Agda` — unchanged: the batch subprocess layer, the verdict source, the kill ladder generalized by #77/#78.  The lane borrows its ladder constants and its `Checking`-line parser, not its process model (one-shot vs persistent).
+  `AgdaMCP.Project` — unchanged in behavior, promoted in role: its per-call resolution now also keys the lane registry, so the "which tree" answer and the "which process" answer cannot diverge.
+  `AgdaMCP.Holes` — the splicing engine and the pre-Agda source view (`codeOnly`, `findHoles` for edits and for files Agda refuses), no longer the authority for anything Agda can answer; parity tests hold it to the lane's `InteractionPoints` across the fixture matrix.
+  `AgdaMCP.Tools.ProofState` — its `get_goal` now answers from the lane first (issue #108): `Cmd_goal_type_context` returns Agda's own goal display as data — probed byte-identical to the macro's goal strings on the fixture matrix — with no file mutation, and the response says `source: "interaction-lane"` with the lane echo in place of a verdict.  The injection path remains as the fallback (`source: "injected-macro"`) for a lane that crashed, could not start, a file that does not load there, or a shutting-down registry — and it is the one path that reports binder visibility, which Agda's goal display does not carry.  A lane timeout surfaces as the structured lane failure rather than silently running the fallback behind it, which would double the bound.  The batch verdict tools also gained a free enrichment: `check_file` and `get_diagnostics` fill their hole listings' `goal` fields from a warm lane's stored `AllGoalsWarnings` when — and only when — the lane's recorded load matches the file's current bytes (a peek, never a lane call), keeping the `"?"` placeholder otherwise.  The same peek reads the same response's *invisible* goals (issue #115): each unsolved meta's name, printed type, and range lands in the `[UnsolvedMetaVariables]` and `[UnsolvedConstraints]` diagnostics' `involved.metas`.  That is the one § 5 payload batch prose cannot carry at all, since Agda prints its unsolved metas' locations and never their types; `involved.metaTypes` stays exactly what the prose said, so a cold or stale lane leaves the response byte-identical, and the batch exit code remains the only verdict on a class this lane tolerates.
+  `AgdaMCP.Interaction` (new) — the lane runner of § 3.
+  `AgdaMCP.Tools.LiveQueries` (new) — the tool handlers over the lane: `type_of`, `normalize`, `resolve_name`, `definition_of`, `exports_of`.
+  `AgdaMCP.Server` — registers the five new tools and their descriptions; dispatch unchanged otherwise.

## 5.  The tools, mapped to the protocol

All five take `filePath` (absolute; resolved and refused exactly as the batch tools do, per #101) and answer with the echo of § 3.

+  `type_of(filePath, expr, line?, column?)` → `Cmd_infer` at the goal whose range contains the position when one does, else `Cmd_infer_toplevel`; `Normalised` rewrite.  Answers for expressions not present in the file.  The optional column decides between two goals sharing a line, whose scopes can differ (probed: `(\ m -> {!!}) {!!}` binds `m` in the first hole only); a line alone selects the earliest goal on it.
+  `normalize(filePath, expr, line?, column?)` → `Cmd_compute` / `Cmd_compute_toplevel`, `DefaultCompute`.
+  `resolve_name(filePath, name, line?, column?)` → `Cmd_why_in_scope` (goal-scoped when the position addresses a goal, else toplevel), parsed into candidates `{name, qualified?, kind?, provenance chain with file/line/col steps, definition site}`; on a not-in-scope answer the ambiguity recovery of § 2.6 runs before the tool reports an empty candidate list.
+  `definition_of(filePath, name, line?, column?)` → the `resolve_name` machinery, projected to each candidate's `its definition at` step: qualified name, file, line, column.
+  `exports_of(filePath, module)` → `Cmd_show_module_contents_toplevel Simplified`; `module` must be in scope in `filePath`, and `""` names the file's own top-level module.

`scope_at(filePath, line)` — the sixth proposed tool — is **not protocol-backed**: no interaction command enumerates the names in scope (the module-contents command lists one module's members, not the environment; the goal commands answer point questions).  Per the issue's own bar (§ 2.2 of the feedback document: ship only where the server beats the shell), it is omitted rather than approximated with grep, and the finding is recorded on issue #75.
