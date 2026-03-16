<!-- File: agda-native-air/agda-dojang/README.md -->

# AgdaDojang

This is the interactive execution and experimentation layer of the **agda-native-air** project.

> *Dojang (도장) literally means "place of the way" or "training hall" in Korean martial arts, like Taekwondo, Hapkido, and Tang Soo Do.*

AgdaDojang provides a small, carefully designed vocabulary of *safe proof actions* inside Agda, together with external tooling that allows AI agents (and humans) to **interact with Agda's typechecker**, propose proof steps, and observe precise semantic feedback.

AgdaDojang is where learned policies are *executed*, *validated*, and *debugged*.

---

## Role in the Overall System

Within the agda-native-air architecture, AgdaDojang serves as

+  the **action space** for AI agents,
+  a bridge between statistical models and Agda's typechecker,
+  a sandbox for experimenting with interactive proof search.

While other parts of the project involve *learning from existing mathematics*, AgdaDojang focuses on **doing mathematics** — one proof step at a time — under Agda's supervision.

---

## Design Principles

AgdaDojang is guided by a few core principles.

+  **Soundness first**: every action is checked by Agda.
+  **Small action vocabulary**: prefer a few well-understood primitives over a large tactic language.
+  **Transparency**: surface goals, contexts, and failures explicitly.
+  **Research-oriented**: optimize for inspectability and extensibility, not raw automation.

AgdaDojang is not intended to compete with mature tactic languages; it is intended to be *learnable* by machines.

---

## Agda-side Components

### TC Monad Macros

At the core of AgdaDojang is a collection of macros implemented in Agda's **TC monad**.

These macros operate *inside* Agda's type theory and can

+  inspect the current goal,
+  query the local context,
+  attempt to construct or apply terms,
+  report subgoals in a structured way.

Key macros include:

+  `refine⟨_⟩` — insert a candidate term into the goal,
+  `apply⟨_⟩` — apply a function or lemma and generate subgoals,
+  `applyWith⟨_,_⟩` — apply with explicit arguments,
+  `applyReport⟨_⟩` / `applySolveReport⟨_⟩` — apply while emitting structured goal reports,
+  `reportGoalCtx` — emit a stable `(goal, context)` request block for external tools,
+  `intro` — introduce a lambda when the goal is a function type.

Each macro is designed to be *deterministic*, *locally scoped*, and *easy to reason about in isolation*.

---

### AgdaDojang Layout

```
agda-dojang
├── agda
│   └── AgdaDojang
│       ├── Apply.agda         -- tactics for applying functions to goals
│       ├── ApplyDemo.agda     -- demo the `apply` macro
│       ├── Debug.agda         -- macros to print goal, its type, normalisation, whnf
│       ├── Everything.agda
│       ├── Examples.agda
│       ├── Prelude.agda
│       └── Refine.agda        -- macros for attempting to fill a hole with candidate term
└── python
    ├── tests
    │   ├── test_agent_bridge.py                -- tests for agent bridge utils in agent_bridge.py.
    │   ├── test_eval_fixture_policy_request.py -- tests policy request in eval_fixtures.py has right shape/content
    │   ├── test_policy_contract.py             -- tests policy contract in policy_contract.py
    │   ├── test_policy_fixture.py              -- tests policy fixture in policy_fixture.py adheres to contract
    │   ├── test_rendering.py                   -- tests for the rendering.py utilities
    │   └── test_report_parser.py               -- tests log parser that reads AgdaDojang's reporting macros output
    ├── tools
    │   ├── agent_bridge.py    -- tiny deterministic "report → policy → patch → check" loop
    │   ├── eval_fixtures.py   -- deterministic Agda-check evaluator + fixtures scoreboard
    │   ├── dojang_extract.py  -- AgdaDojang trace extractor
    │   ├── dojang_try.py      -- AgdaDojang probe & tactics runner
    │   ├── policy_contract.py -- canonical, versioned request/response contract for policy backends
    │   ├── policy_fixture.py  -- simple deterministic policy backend for tests and demos
    │   ├── prompt_baseline.py -- turn list of tasks into list of (context, goal, completion) attempts
    │   ├── report_parser.py   -- parsing of Agda subgoal reports from stderr
    │   └── search.py          -- AgdaDojang search loop (BFS/beam)
    └── utils
        ├── command_runner.py  -- functional command execution utilities
        ├── file_ops.py        -- functional wrappers for file system operations
        ├── rendering.py       -- pure rendering helpers for building scratch modules
        ├── result.py          -- tiny Result type
        ├── run_unittests.py   -- pretty-ish unittest runner (stdlib only)
        └── types.py           -- data classes for config, command results, errors, reports
```

The `Everything` module re-exports the full AgdaDojang action vocabulary.

---

## Python-side Tooling

AgdaDojang includes lightweight Python tools that orchestrate interaction with Agda.

### `dojang_try.py`

This script

+  generates scratch Agda modules,
+  inserts candidate terms or macro invocations,
+  runs Agda on the generated code,
+  parses emitted goals and diagnostics.

It is primarily intended for **rapid experimentation** and debugging.


### `agent_bridge.py`

This is a tiny deterministic **integration bridge**:

+  inject `reportGoalCtx` into the next `{!!}` hole to obtain `(goal, context)`,
+  call a policy backend (local process) to get top-k candidates,
+  try candidates in Agda and patch the first that typechecks.

This is the v0 deliverable for “policy ↔ AgdaDojang integration” (Issue #23).

### `eval_fixtures.py`

This is the deterministic **Agda-check evaluator + fixtures scoreboard** (Issue #85).
It produces machine-readable JSONL logs (`results.jsonl`, `fixtures.jsonl`) and a small scoreboard.


### `search.py`

This script implements simple proof-search strategies (e.g. BFS / beam search) over the AgdaDojang action space.

Its purpose is not to be state-of-the-art, but to

+  demonstrate how an agent can interact with Agda step-by-step,
+  provide baselines for learned policies,
+  generate data for interactive learning.


### `policy_fixture.py`

This is a temporary, minimal policy backend that we can use to test the
inference/serving integration and make the demo pass even before any training
exists.  It reads a request JSON containing `{goal, context}`
and returns a ranked list of candidate terms.  It's deterministic and uses only a few
safe heuristics:

+ If the goal matches a context binder's type, propose that binder name (assumption).
+ If the goal contains `≡` (equality), propose `refl` (works for `x ≡ x` fixtures).
+ If the goal is `⊤`, propose `tt`.

---

## Typical Workflow

A typical AgdaDojang session looks like this.

1.  Start from a goal (an Agda hole),
2.  Propose an action (e.g. `intro`, `apply⟨lemma⟩`),
3.  Let Agda check the result,
4.  Observe new goals or failure reports,
5.  Repeat until the proof is complete or abandoned.

Every step is validated by Agda.

---

## Running AgdaDojang

### With Nix (recommended)

From the repository root:

```bash
nix develop
cd agda-dojang
make check
```

This type-checks all AgdaDojang macros.

---

### Demo Targets

From `agda-dojang/`:

```bash
make demo1    # Simple refinement demo
make demo2    # Apply + subgoal reporting demo
```

These demos serve as executable documentation.

---

## Proof-completion evaluator (Issue #85)

AgdaDojang includes a deterministic **Agda-check evaluator** for “proof completion” fixtures.
It runs a small **propose → check** loop:

1. For each `{!!}` hole in a fixture module, inject a reporting macro (e.g. `reportGoalCtx`)
   to extract a `(goal, context)` request from Agda output.
2. Call a **policy backend** (local process) to obtain top-k candidate terms.
3. Check each candidate in Agda (Agda is the oracle).
4. Patch the fixture with the first candidate that typechecks.
5. If all holes are solved, run a strict final typecheck.


### Run it

From `agda-dojang/`:

```bash
make eval-proof-completion
```

This uses the scripted fixture policy backend (`python/tools/policy_fixture.py`) and runs
over the committed fixtures (default glob: `data/fixtures/Fixture*.agda`).


### Output artifacts

Artifacts are written under: `agda-dojang/_build/eval-proof-completion/<run-id>/`

The Make target uses `run-id = latest` and cleans it each run.

Key outputs:

+ `results.jsonl` — **one JSON object per candidate attempt** (the main “score log”)
+ `fixtures.jsonl` — **one JSON object per fixture module** (summary rows)
+ `logs/` — captured Agda output per hole/candidate
+ `solved/` — fully solved fixture modules (canonical filenames), only when strict check passes
+ `agda_version.txt` — best-effort `agda --version` capture (when available)

Directory layout:

```
_build/eval-proof-completion/latest/
  results.jsonl
  fixtures.jsonl
  agda_version.txt
  logs/
    <FixtureId>/
      hole-00/
        cand-01.txt
        cand-02.txt
        ...
      hole-01/
        ...
      final_strict.txt
  solved/
    <FixtureId>.agda
  work/                  # only if --keep-workdir is enabled
    <FixtureId>/
      shadow/
      _input_overlay/
```

+ `logs/<FixtureId>/hole-XX/cand-RR.txt` contains the merged Agda output for that candidate check.
+ `logs/<FixtureId>/final_strict.txt` contains output from the final strict check (only if all holes were filled).
+ `solved/<FixtureId>.agda` is written only when the fixture becomes hole-free and the strict final check succeeds.

---

## Result schema (v0)

Both `results.jsonl` and `fixtures.jsonl` are **append-only JSON Lines** (one JSON object per line).
Every row includes a `schemaVersion` so the format can evolve without breaking consumers.

### `results.jsonl` (per-candidate attempts)

Each row describes *one* attempt to solve *one* hole with *one* candidate term:

+  `schemaVersion` (string) — currently `eval-proof-completion.v0`
+  `fixtureId` (string) — fixture module stem, e.g. `Fixture01`
+  `module` (string) — module name (currently same as `fixtureId`)
+  `fixturePath` (string) — absolute path to the fixture file
+  `holeIndex` (int) — 0-based index of the hole in the solving sequence
+  `holeLine` (int) — 1-based line number of the hole token in the fixture source
+  `holeCol` (int) — 1-based column of the hole token in the fixture source
+  `candidateRank` (int) — 1..k rank among returned candidates (0 for synthetic error rows)
+  `candidate` (string) — candidate term (empty string for synthetic error rows)
+  `status` (string) — one of:

   +  `ok` (candidate typechecked)
   +  `type_error` (Agda rejected candidate)
   +  `timeout` (candidate check timed out)
   +  `crash` (tooling/IO failure)
   +  `policy_error` (policy invocation or parsing failed)
   +  `report_error` (could not extract `(goal, context)` markers)
+  `elapsedMs` (int) — wall-clock time for the candidate check (milliseconds)
+  `rc` (int) — process return code (best-effort; timeouts/crashes may be synthetic)
+  `logPath` (string) — path to the captured output file for this attempt

### `fixtures.jsonl` (per-fixture summaries)

Each row summarizes evaluation for one fixture module:

+  `schemaVersion` (string) — currently `eval-proof-completion.v0`
+  `fixtureId` (string)
+  `module` (string)
+  `fixturePath` (string)
+  `holesTotal` (int) — number of `{!!}` holes in the original fixture source
+  `holesSolved` (int) — number of holes successfully filled by typechecking candidates
+  `fullySolved` (bool) — `true` iff the fixture became hole-free **and** strict final check passed
+  `finalStatus` (string) — `ok` if fully solved, else `unsolved` or an error-like status
+  `elapsedMs` (int) — total time spent evaluating the fixture (milliseconds)
+  `solvedPath` (string | null) — path to the solved `.agda` file if `fullySolved`, else null

### Compatibility promise

For `schemaVersion = eval-proof-completion.v0`, consumers may rely on:

+  the presence and meaning of the keys above,
+  `results.jsonl` being per-candidate and `fixtures.jsonl` being per-fixture,
+  new fields may be added in later versions, but existing keys should not change meaning.


---


## Research Notes and Future Directions

+  Expand the action vocabulary (e.g. rewrite, structured intro).
+  Add richer goal and failure reporting for learning.
+  Integrate learned policies from `ml-pipeline`.
+  Deeper experimentation with reflective proof search.

*AgdaDojang is intentionally minimal today, but designed to grow alongside the agents that use it.*

---

## Appendix

### Tutorial: TC monad, macros and Kleisli arrows (for a category theorist)


#### What the `TC` monad *is*

Agda's reflection API runs during typechecking. The typechecker maintains (at least)

+  the **local context** Γ (bound variables, their types, visibility, modalities),
+  the **signature** (global definitions),
+  the **meta-variable store** (holes, constraints, unification problems),
+  the current **goal** / expected type,
+  and it can fail with a structured error message (`typeError`).

A *reflection computation* is therefore not a pure function; it's an effectful computation that can

+  *read* Γ (`getContext`),
+  *query* types (`inferType`),
+  *normalise* (`normalise`),
+  and *abort* with a message (`typeError`).

So Agda packages *typechecker effects* into a monad with

+  **objects**: Agda types `A : Set ℓ`
+  **morphisms**: `A → TC B` (Kleisli arrows)
+  **unit**: `returnTC : A → TC A`
+  **bind**: `bindTC` (denoted by `_>>=_`)

Categorically, `TC` is a monad on the category of Agda types/terms whose Kleisli category is "programs that can consult/modify the typechecking state and fail."


#### What these macros *do*

A **`macro`** in Agda is a compile-time program (in `TC`) that Agda runs while elaborating terms.

In AgdaDojang, the macros are **instrumentation**;

+  they compute info about the goal and context;
+  then intentionally stop compilation by throwing a `typeError` whose payload contains stable markers.

That is why the evaluator sees:

```
error: [GenericDocError]
AGDADOJANG_REQ_BEGIN
...
AGDADOJANG_REQ_END
```

We're using Agda's error channel as a "structured side-channel" to export `{goal, context}`.

### An Aside: `do` vs `>>=` (bind)

In Agda, a `do _ ← _` block is syntactic sugar for chaining `>>=`; for example,

```agda
reportGoalCtx hole = do
  goalTy  ← inferType hole
  goalNF  ← normalise goalTy
  goalStr ← formatErrorParts (termErr goalNF ∷ [])
  ...
```

desugars (morally) to

```agda
reportGoalCtx hole =
  inferType hole >>= λ goalTy →
  normalise goalTy >>= λ goalNF →
  formatErrorParts (termErr goalNF ∷ []) >>= λ goalStr →
  ...
```

So `do` is just syntax for composing Kleisli arrows using bind.

### Kleisli arrows: composition of effectful maps

A Kleisli arrow is a map `A → TC B`. Given

* `f : A → TC B`
* `g : B → TC C`

their Kleisli composite is:

```agda
(f >=> g) : A → TC C
(f >=> g) a = f a >>= g
```

That's exactly the operator we used:

```agda
(inferType >=> normalise >=> termToString) hole
```

Interpretation: "infer the type, then normalise it, then pretty print it, all inside the TC effects."

### Why `do` and Kleisli composition are *the same*

+  `do` is *notation* for sequencing binds;
+  Kleisli composition is a *categorical packaging* of the same sequencing;
+  Both express associativity/unit laws of the monad, just at different levels of abstraction.

In our code,

+  `mkCtxParts` is sequencing `normalise`, `formatErrorParts`, recursion, then `returnTC`;
+  `reportGoalCtx` is sequencing `inferType`, `normalise`, `formatErrorParts`, `getContext`, `mkCtxParts`, then `typeError`.

All of those are "paths" in the Kleisli category of `TC`.


---



## See Also

+ [Root project README][]
+ [`agda-strux/README.md`][agda-strux/README]
+ [`ml-pipeline/README.md`][ml-pipeline/README]
+ [`strux-driver/README.md`][strux-driver/README]

[Root project README]: https://github.com/formalverification/agda-native-air/blob/main/README.md
[agda-strux/README]: https://github.com/formalverification/agda-native-air/blob/main/agda-strux/README.md
[strux-driver/README]: https://github.com/formalverification/agda-native-air/blob/main/strux-driver/README.md
[ml-pipeline/README]: https://github.com/formalverification/agda-native-air/blob/main/ml-pipeline/README.md
[`agda-dojang/python/tools/policy_fixture.py`]: https://github.com/formalverification/agda-native-air/blob/main/agda-dojang/python/tools/policy_fixture.py


