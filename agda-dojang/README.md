<!-- File: agda-native-air/agda-dojang/README.md -->

# AgdaDojang

This is the interactive execution and experimentation layer of the **agda-native-air** project.

> *Dojang (도장) literally means "place of the way" or "training hall" in Korean martial arts, like Taekwondo, Hapkido, and Tang Soo Do.*

AgdaDojang provides a small, carefully designed vocabulary of *safe proof actions* inside Agda, together with external tooling that allows AI agents (and humans) to **interact with Agda's typechecker**, propose proof steps, and observe precise semantic feedback.

This is where learned policies are *executed*, *validated*, and *debugged*.


<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Role in the Overall System](#role-in-the-overall-system)
- [Design Principles](#design-principles)
- [Agda-side Components — Action Space Reference](#agda-side-components--action-space-reference)
  - [Phase 1: Observe — `reportGoalCtx`](#phase-1-observe--reportgoalctx)
  - [Phase 2: Propose — policy request/response](#phase-2-propose--policy-requestresponse)
  - [Phase 3: Validate — fill-hole round-trip](#phase-3-validate--fill-hole-round-trip)
  - [Worked Example: full round-trip on `Fixture01`](#worked-example-full-round-trip-on-fixture01)
  - [TC Monad Macros: detailed reference](#tc-monad-macros-detailed-reference)
  - [How These Map to `agda-mcp` Tools](#how-these-map-to-agda-mcp-tools)
  - [Evaluator Output Artifacts](#evaluator-output-artifacts)
  - [AgdaDojang Layout](#agdadojang-layout)
- [Python-side Tooling](#python-side-tooling)
  - [`eval_fixtures.py`](#eval_fixturespy)
  - [`search.py`](#searchpy)
  - [`policy_fixture.py`](#policy_fixturepy)
- [Running AgdaDojang](#running-agdadojang)
  - [With Nix (recommended)](#with-nix-recommended)
  - [Demo Targets](#demo-targets)
- [Proof-completion evaluator (Issue #85)](#proof-completion-evaluator-issue-85)
  - [Run it](#run-it)
  - [Output artifacts](#output-artifacts)
- [Result schema (v0)](#result-schema-v0)
  - [`results.jsonl` (per-candidate attempts)](#resultsjsonl-per-candidate-attempts)
  - [`fixtures.jsonl` (per-fixture summaries)](#fixturesjsonl-per-fixture-summaries)
  - [Compatibility promise](#compatibility-promise)
- [Research Notes and Future Directions](#research-notes-and-future-directions)
- [Appendix](#appendix)
  - [Tutorial: TC monad, macros and Kleisli arrows (for a category theorist)](#tutorial-tc-monad-macros-and-kleisli-arrows-for-a-category-theorist)
    - [What the `TC` monad *is*](#what-the-tc-monad-is)
    - [What these macros *do*](#what-these-macros-do)
  - [An Aside: `do` vs `>>=` (bind)](#an-aside-do-vs--bind)
  - [Kleisli arrows: composition of effectful maps](#kleisli-arrows-composition-of-effectful-maps)
  - [Why `do` and Kleisli composition are *the same*](#why-do-and-kleisli-composition-are-the-same)
- [See Also](#see-also)

<!-- markdown-toc end -->



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

## Agda-side Components — Action Space Reference

AgdaDojang exposes a small, well-defined vocabulary of TC-monad macros that serve as
the **action space** for AI agents.

Each macro is designed to be *deterministic*, *locally scoped*, and *easy to reason
about in isolation*.

Every action is checked by Agda's typechecker; there is no way to produce an unsound
result.

This section documents each macro with concrete before/after examples.  It is
intended as the specification for `agda-mcp` tool schemas (Issue #10 [M1-2]).

The interaction loop has three phases:

1. **Observe** — extract the goal type and local context from a hole.
2. **Propose** — query a policy backend for candidate proof terms.
3. **Validate** — substitute a candidate into the hole and typecheck.

---

### Phase 1: Observe — `reportGoalCtx`

The primary observation action.  When injected into a hole, it causes Agda to emit a
structured `(goal, context)` block on stderr, then abort (via `typeError`).  The
evaluator parses this block and forwards it to the policy backend.

**Defined in**: `AgdaDojang.Debug`

**Agda source (before)**:

```agda
module Fixture01 where

open import Agda.Builtin.Unit
open import Agda.Builtin.Equality
open import AgdaDojang.Debug

id : {A : Set} → A → A
id x = {!!}                     -- ← hole to solve
```

**Injected source (the evaluator replaces `{!!}` with the reporting expression)**:

```agda
id x = reportGoalCtx ?          -- ← reporting macro + fresh hole
```

**Agda stderr output (abridged)**:

```
AGDADOJANG_REQ_BEGIN
AGDADOJANG_GOAL: A
AGDADOJANG_CTX_BEGIN
AGDADOJANG_CTX:0:visible:x: A
AGDADOJANG_CTX:1:hidden:A: Set₀
AGDADOJANG_REQ_END
```

**Parsed result** (what `utils/goal_report.py`'s `extract_policy_request_from_output` returns):

```json
{
  "goal": "A",
  "context": [
    {"index": 0, "visibility": "visible", "name": "x", "type": "A"},
    {"index": 1, "visibility": "hidden",  "name": "A", "type": "Set₀"}
  ]
}
```

**Implementation note**.  `reportGoalCtx` normalizes the goal type and raises
de Bruijn indices on context binder types before pretty-printing, so that `x : A`
prints as `x : A` rather than `x : x` (a subtlety when the context contains dependent
binders).

---

### Phase 2: Propose — policy request/response

The evaluator wraps the parsed observation into a versioned **policy request** and calls
the policy backend as a subprocess.

**Policy request** (`agda-native-air/policy-request@v0`):

```json
{
  "schema": "agda-native-air/policy-request@v0",
  "goal": "A",
  "context": [
    {"name": "x", "type": "A"},
    {"name": "A", "type": "Set₀"}
  ],
  "module": "Fixture01",
  "meta": {
    "fixtureId": "Fixture01",
    "holeIndex": 0
  }
}
```

**Policy response** (`agda-native-air/policy-response@v0`):

```json
{
  "schema": "agda-native-air/policy-response@v0",
  "candidates": [
    {"term": "x", "score": 1.0, "meta": {"rule": "assumption"}},
    {"term": "tt", "score": 0.3, "meta": {"rule": "tt-for-top"}}
  ],
  "meta": {
    "policy": "fixture",
    "deterministic": true
  }
}
```

The contract is defined in `policy_contract.py`.  Any backend that speaks this JSON
contract can be swapped in (scripted heuristic, LLM, fine-tuned model, MCP tool,
etc.) without changing the evaluator.

**CLI invocation**:

```sh
python3 python/tools/policy_fixture.py --in request.json --out - --k 5
```

---

### Phase 3: Validate — fill-hole round-trip

The evaluator substitutes the top candidate into the hole and runs Agda to typecheck.

**Before (hole present)**:

```agda
id : {A : Set} → A → A
id x = {!!}
```

**After (candidate `x` substituted)**:

```agda
id : {A : Set} → A → A
id x = x
```

**Agda typecheck result**: exit code 0 (success) → hole is marked solved.

If the candidate fails to typecheck, the evaluator tries the next candidate in rank
order.  If all candidates are exhausted, the hole remains unsolved.

---

### Worked Example: full round-trip on `Fixture01`

`Fixture01.agda` has three holes.

```agda
-- Hole 0: goal is A, context has x : A
id : {A : Set} → A → A
id x = {!!}

-- Hole 1: goal is ⊤
trivial : ⊤
trivial = {!!}

-- Hole 2: goal is x ≡ x
reflExample : {A : Set} (x : A) → x ≡ x
reflExample x = {!!}
```

The evaluator processes holes sequentially.

| Hole | Goal    | Key context     | Policy rule  | Candidate | Result       |
|------|---------|-----------------|--------------|-----------|--------------|
| 0    | `A`     | `x : A`         | assumption   | `x`       | ✓ typechecks |
| 1    | `⊤`     | (empty visible) | ⊤ → tt       | `tt`      | ✓ typechecks |
| 2    | `x ≡ x` | `x : A`         | `_≡_` → refl | `refl`    | ✓ typechecks |


**Final solved file** (written to `_build/eval-proof-completion/<run-id>/solved/Fixture01.agda`):

```agda
id : {A : Set} → A → A
id x = x

trivial : ⊤
trivial = tt

reflExample : {A : Set} (x : A) → x ≡ x
reflExample x = refl
```

---

### TC Monad Macros: detailed reference

#### `refine⟨_⟩` — Direct Hole Filling

**Defined in**: `AgdaDojang.Refine`

Insert a candidate term into the goal.  If the candidate typechecks against the goal
type, the hole is unified with the candidate.  Otherwise, Agda raises a type error.

```agda
-- Before:
trivial : ⊤
trivial = refine⟨ tt ⟩       -- ← candidate is tt

-- After (if tt : ⊤ checks):  hole is solved with tt
```

**Semantics**: `inferType hole >>= checkType cand >>= unify hole cand`

This is the macro that the evaluator uses internally: it substitutes the candidate term
directly in the source (no macro wrapper needed for the evaluator's validate step —
it simply replaces `{!!}` with the candidate text).

---

#### `try⟨_⟩` — Non-Committing Probe

**Defined in**: `AgdaDojang.Refine`

Check whether a candidate *would* typecheck without actually solving the hole.
Reports `AGDADOJANG_TRY:OK` or `AGDADOJANG_TRY:FAIL` via a `typeError` message.

```agda
-- In a hole:
trivial : ⊤
trivial = try⟨ tt ⟩

-- Agda stderr will contain: AGDADOJANG_TRY:OK
-- The hole is NOT solved — this is probe-only.
```

**Use case**: batch-testing multiple candidates without rewriting the source each time.

---

#### `apply⟨_⟩` — Function/Lemma Application

**Defined in**: `AgdaDojang.Apply`

Apply a named function or constructor to the current goal.  Agda infers as many
arguments as possible; remaining arguments become subgoals (unsolved metas).

```agda
-- If the goal is `Nat` and we apply `suc`:
example : Nat
example = apply⟨ suc ⟩        -- solves the goal with `suc ?`, leaving `? : Nat`
```

**Semantics**: Builds `(def f [unknown, …, unknown])` from the `Π`-shape of `f`'s type,
checks against the goal, and unifies.  Metas for unresolvable arguments remain as
subgoals.

---

#### `applyReport⟨_⟩` — Report Subgoals Without Solving

**Defined in**: `AgdaDojang.Apply`

Like `apply⟨_⟩`, but instead of solving, it reports the subgoal types that would be
generated.  Emits structured lines between `AGDADOJANG_SUBGOALS_BEGIN` / `END` markers.

```agda
example : Nat
example = applyReport⟨ _+_ ⟩
```

**Agda stderr**:

```
AGDADOJANG_SUBGOALS_BEGIN
AGDADOJANG_GOAL:0:visible: Nat
AGDADOJANG_GOAL:1:visible: Nat
AGDADOJANG_SUBGOALS_END
```

**Use case**: previewing what subgoals a tactic would generate before committing.

---

#### `applySolveReport⟨_⟩` — Apply Then Report Remaining Obligations

**Defined in**: `AgdaDojang.Apply`

Apply `f`, let Agda unify, then report the *instantiated* types of remaining unsolved
meta-arguments.

```agda
-- If goal is `3 + ?₁ ≡ 5`:
example = applySolveReport⟨ refl ⟩
-- Reports the post-unification obligations (e.g., ?₁ = 2)
```

---

#### `applyWith⟨_,_⟩` / `applyWith1⟨_,_⟩` — Apply with Explicit Arguments

**Defined in**: `AgdaDojang.Apply`

Supply explicit arguments to the first visible binders of `f`; hidden/instance
binders are left as metas.

```agda
example = applyWith1⟨ _+_ , (lit (nat 3)) ⟩   -- applies _+_ with first visible arg = 3
```

---

#### `intro` / `intro₂` / `intros⟨_⟩` — Lambda Introduction

**Defined in**: `AgdaDojang.Apply`

If the goal is a `Π`/`→` type, introduce one (or more) lambda abstractions and leave
the codomain as the new goal.

```agda
-- Before:
foo : {A : Set} → A → A
foo = {!!}                     -- goal: {A : Set} → A → A

-- After `intro`:
foo = λ x → {!!}              -- goal: A   (with x : A in context)
```

`intro₂` introduces exactly two lambdas; `intros⟨ n ⟩` introduces `n` lambdas in one shot.

---

#### `showGoalType` / `showTypeNFvsWHNF` — Debugging Helpers

**Defined in**: `AgdaDojang.Debug`

Inspect the goal type (raw, WHNF, and fully normalised forms).  Useful for debugging
but not part of the automated loop.

```agda
example : ⊤
example = showGoalType ?        -- stderr: "GOAL TYPE: ⊤"
```

---

### How These Map to `agda-mcp` Tools

The macros above correspond to the planned `agda-mcp` tool surface as follows:

| `agda-mcp` tool             | Underlying macro / action                            | Phase            |
|-----------------------------|------------------------------------------------------|------------------|
| `get-goal`                  | `reportGoalCtx`                                      | Observe          |
| `fill-hole`                 | direct substitution + Agda typecheck (≈ `refine⟨_⟩`) | Validate         |
| `check-file`                | `agda <file>` (full typecheck)                       | Validate         |
| `get-diagnostics`           | parse Agda stderr for errors/warnings                | Observe          |
| `apply-tactic` (future)     | `apply⟨_⟩`, `intro`, `intros⟨_⟩`                     | Propose+Validate |
| `preview-subgoals` (future) | `applyReport⟨_⟩`                                     | Observe          |

The first four tools constitute the v0 tool surface for M1-2.  The remaining two are
candidates for v1 once the basic loop is stable.

---

### Evaluator Output Artifacts

Running `make eval-proof-completion` produces the following in
`agda-dojang/_build/eval-proof-completion/<run-id>/`:

```
<run-id>/
├── fixtures.jsonl              # one row per fixture (summary)
├── results.jsonl               # one row per candidate attempt (detail)
├── logs/
│   └── <FixtureId>/
│       └── hole-<N>/
│           ├── policy_request.json    # exact request sent to policy
│           ├── policy_response.json   # exact response from policy
│           └── cand-01.txt            # Agda output for candidate #1
└── solved/
    └── <FixtureId>.agda        # hole-free file (only if fully solved)
```

See the "Result schema (v0)" section below for the JSONL field definitions.

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
    │   ├── test_agda_probe.py                  -- tests the Agda-probing primitives in utils/agda_probe.py
    │   ├── test_eval_fixture_policy_request.py -- tests policy request in eval_fixtures.py has right shape/content
    │   ├── test_goal_report.py                 -- tests the marker-block parser in utils/goal_report.py
    │   ├── test_parse_request.py               -- tests request parsing/validation in policy_contract.py
    │   ├── test_policy_contract.py             -- tests policy contract in policy_contract.py
    │   ├── test_policy_fixture.py              -- tests policy fixture in policy_fixture.py adheres to contract
    │   └── test_rendering.py                   -- tests for the rendering.py utilities
    ├── tools
    │   ├── dojang_extract.py  -- AgdaDojang trace extractor
    │   ├── eval_fixtures.py   -- deterministic Agda-check evaluator + fixtures scoreboard
    │   ├── policy_contract.py -- canonical, versioned request/response contract for policy backends
    │   ├── policy_fixture.py  -- simple deterministic policy backend for tests and demos
    │   ├── prompt_baseline.py -- turn list of tasks into list of (context, goal, completion) attempts
    │   └── search.py          -- AgdaDojang search loop (BFS/beam)
    └── utils
        ├── agda_probe.py      -- probe Agda about one hole: source surgery, invocation, verdict
        ├── command_runner.py  -- functional command execution utilities
        ├── file_ops.py        -- functional wrappers for file system operations
        ├── goal_report.py     -- parse the AGDADOJANG_REQ marker block into {goal, context}
        ├── rendering.py       -- pure rendering helpers for building scratch modules
        ├── result.py          -- tiny Result type
        ├── run_unittests.py   -- pretty-ish unittest runner (stdlib only)
        └── types.py           -- data classes for config, command results, errors, reports
```

The `Everything` module re-exports the full AgdaDojang action vocabulary.

---

## Python-side Tooling

AgdaDojang includes lightweight Python tools that orchestrate interaction with Agda.

**Retired (Issue #109)**.  The deterministic "report → policy → patch → check"
bridge that once lived here (`agent_bridge.py`, the marker parser
`report_parser.py`, and the `dojang_try.py` CLI front) has been removed.
[`agda-mcp`](../agda-mcp/README.md) is its successor and the only agent-facing
route into Agda: it is the Haskell port of the same loop, speaking the same
marker protocol, with truthful verdicts and structured diagnostics on top.  The
primitives the evaluator still needs moved to `python/utils/agda_probe.py` and
`python/utils/goal_report.py`, with their tests.

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
make eval-proof-completion-smoke   # Fast proof-completion run on one fixture
make eval-proof-completion         # Full run over every fixture
```

These demos serve as executable documentation.

---

## Proof-completion evaluator (Issue #85)

AgdaDojang includes a deterministic **Agda-check evaluator** for "proof completion" fixtures.
It runs a small **propose → check** loop:

1. For each `{!!}` hole in a fixture module, inject a reporting macro (e.g. `reportGoalCtx`)
   to extract a `(goal, context)` request from Agda output.
2. Call a **policy backend** (local process) to obtain top-k candidate terms.
3. Check each candidate in Agda (Agda is the oracle).
4. Patch the fixture with the first candidate that typechecks.
5. If all holes are solved, run a strict final typecheck.


### Run it

```bash
make eval-proof-completion
```

This uses the scripted fixture policy backend (`python/tools/policy_fixture.py`) and runs
over the committed fixtures (default glob: `data/fixtures/Fixture*.agda`).


### Output artifacts

Artifacts are written under: `agda-dojang/_build/eval-proof-completion/<run-id>/`

The Make target uses `run-id = latest` and cleans it each run.

Key outputs:

+ `results.jsonl` — **one JSON object per candidate attempt** (the main "score log")
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
reportGoalCtx _ hole = do
  goalTy  ← inferType hole
  goalNF  ← normalise goalTy
  goalStr ← formatErrorParts (termErr goalNF ∷ [])
  ...
```

desugars (morally) to

```agda
reportGoalCtx _ hole =
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


