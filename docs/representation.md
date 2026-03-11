<!-- File: docs/representation.md -->

# Data Representation (JSONL → Derived Views) — agda-native-air

This document specifies the **data contract** for artifacts emitted by the Haskell `agda-strux` backend (JSONL) and the **derived views** produced by converters/ETL (Parquet, edge lists, training datasets).

It is intentionally **versioned and incremental**: consumers should tolerate *unknown fields*, and producers should avoid breaking existing fields without a version bump + converter.

This document also records a small number of **operational contracts** used by interactive tooling (e.g. AgdaDoJang ↔ policy backend), which are *not* derived from canonical JSONL rows.

---

## 0. Goals and non-goals

### Goals

- Define **canonical JSONL row schema** (backend output).
- Define **versioning rules** (`typeAstVersion`, schema evolution).
- Specify **derived views** (ports/wires graph, training datasets) and how they are computed.
- Provide **examples** that are stable and copy/pasteable for tests.
- Record **operational interfaces** needed for end-to-end demos (e.g. policy backend request/response).

### Non-goals (for now)

- Perfect name resolution across modules (token → canonical name).
- Full-fidelity surface syntax reconstruction.
- Storing full proof state traces for every definition (that’s a later “derived dataset”).

---

## 1. Terminology

+  **Definition**: any Agda entity emitted as one JSON object in the JSONL stream
   (functions/theorems, records, data types, constructors, postulates, etc.).
+  **Canonical row**: one JSON object emitted by the backend for a definition.
+  **Derived view**: any computed artifact that can be regenerated from canonical
   rows (graphs, training datasets, indices).
+  **Operational contract**: a versioned request/response schema used by tooling at
   runtime (e.g. Agda goal/context → policy candidates). Not derived from canonical rows.
+  **Pretty name**:  normalized `prettyQname` intended as the stable join key.
+  **Wire**: a dependency edge from a definition to some referenced identifier (type deps ∪ body deps).

---

## 2. Canonical JSONL output

### 2.1 Output formats

The backend emits JSONL in two formats (CLI-controlled).

+  **Full (`Cli.Full`)**: machine-oriented; stable contract; used by ETL.
+  **Human (`Cli.Human`)**: debug-oriented; not a stable contract.

This doc mainly specifies **Full**.

### 2.2 Status of downstream consumers

**Current State** (as of February 2026)

+  **Canonical extraction**.  `agda-strux` backend emits Full JSONL format with
   `typeAst` structural encoding (version `0.3-v0`).
+  **ETL alignment**.  Integration of `typeAst` and structural schema into downstream
   ETL pipeline is tracked in [Issue
   #58](https://github.com/formalverification/agda-ai-prover/issues/58).
+  **Legacy migration**.  Issue #58 is complete, so legacy ETL components should no longer
   assume older field names or schemas; converter logic to normalize old → new
   formats is already developed. **TODO**: check/confirm.
+  **Production status**.  Backend fully supports current schema; ETL pipeline
   integration is done. **TODO**: check/confirm.

---

## 3. Full-row schema (v0.01)

### 3.1 Required fields (Full)

| Field | Type | Meaning |
|------:|------|---------|
| `file` | string | Source file path used by extractor (may be absolute). |
| `module` | string | Module name for the definition (as seen by Agda). |
| `name` | string | Unqualified name component. |
| `qname` | string | Qualified name (raw-ish, Agda internal pretty). |
| `prettyModule` | string | Normalized module name (drops certain anonymous segments). |
| `prettyName` | string | Normalized name. |
| `prettyQname` | string | `prettyModule.prettyName` (the primary join key). |
| `type` | string | Pretty-printed type (Agda internal pretty printer). |
| `typeAstVersion` | string | Version tag for `typeAst` encoding (e.g. `"0.3-v0"`). |
| `typeAst` | object | Structural AST encoding of the type (versioned). |
| `kind` | string | Currently `"definition"` (reserved for future). |
| `defKind` | string | Enum: `function`, `data`, `record`, `constructor`, `postulate`, `primitive`, `other`. |
| `dependencies` | array[string] | Heuristic tokens extracted from `type` (type-level deps). |
| `astSize` | number | Character length of the `type` string: `astSize = length(type)`. Used for sanity checks and debugging. |

**Stability guarantee:** required fields must not disappear in v0.01.


### 3.2 Optional fields (Full)

| Field | Type | Meaning |
|------:|------|---------|
| `body` | null \| string | Pretty-printed clause bodies (Agda internal terms), if available. |
| `hasBody` | bool | True iff `body` is present/non-empty. |
| `ports` | object | **[Planned v1.0]** Optional interface extraction (`inputs`/`outputs`), see §6. May be emitted by backend or derived by ETL. Tracked in [Issue #61](https://github.com/formalverification/agda-ai-prover/issues/61). |
| `refsFromBody` | array[string] | **[Planned v1.0]** Optional tokens extracted from `body` (body-level deps), see §6. May be emitted by backend or derived by ETL. |
| `wires` | array[string] | **[Planned v1.0]** Optional union of type deps and body deps, deduped, see §6. May be emitted by backend or derived by ETL. |

**Compatibility rule:** consumers must ignore unknown fields.

---

## 4. Naming invariants and known edge cases

### 4.1 `prettyQname` is the join key
Downstream joins (graph, dataset merges, indexing) should use:
- `prettyQname` (preferred)
- fallback: `qname` when needed for debugging

### 4.2 Operator names and “pretty-name collapse”
Operators like `_+_` can surface naming/pathological normalization issues.
- Track bug fixes and regression tests in: **Issue #53**.
- Add fixtures in tests that assert stable `prettyName`/`prettyQname` for operators.

---

## 5. Structural AST (`typeAst`) contract

### 5.1 Versioning

+  `typeAstVersion` is mandatory.
+  Consumers must branch by version:
   + `"0.3-v0"`: current encoder described here.
+  Breaking changes require

   1. bump `typeAstVersion`
   2. add a converter in ETL to normalize old → new when needed,
   3. update this doc + add regression fixtures.

### 5.2 Common node tags (0.3-v0)

*This section is deliberately partial; unknown constructors are bucketed as `Other*`.*

- `Type`: `{ tag, sort, term }`
- `Pi`: `{ tag, binder, dom, cod }`
- `Lam`: `{ tag, hiding, nameHint, body }`
- `Def`: `{ tag, qname, elims }`
- `Var`: `{ tag, ix, elims }`
- `Con`: `{ tag, qname, elims }`
- `Apply` elim: `{ tag, hiding, term }`
- `Proj` elim: `{ tag, qname }`
- `Sort`, `Set`, `Prop`, `Inf`, `OtherSort`
- `Other`, `OtherElim`, `OtherLevel`, etc.

### 5.3 Invariants

-  Encoder is **total**: never throws; unknown nodes become `Other*`.
-  Application structure is represented via elimination lists (`elims`) on `Def/Var/Con`.

---

## 6. Ports and wires (knowledge-graph/DAG view)

**Status:** Planned for v1.0. Schema is defined below but fields are **not yet emitted** by the current backend.

This is a **derived-but-stored** view: it can be emitted by the backend (preferred) or computed in ETL from canonical data.

**Tracking**.  Implementation tracked in [Issue #61](https://github.com/formalverification/agda-ai-prover/issues/61).


### 6.1 Ports schema (v0)

```json
"ports": {
  "inputs": [
    { "nameHint": "x", "hiding": "explicit", "type": "A" },
    { "nameHint": "ℓ", "hiding": "implicit", "type": "Level" }
  ],
  "outputs": [
    { "nameHint": null, "type": "B" }
  ]
}
```

+  `inputs` are extracted by peeling top-level `Pi` binders of the type.
+  `outputs` is the remaining codomain (after peeling).
+  `type` strings in ports are produced via Agda pretty printer (v0). Future versions may add `typeAst`.


### 6.2 Wires schema (v0)

```json
"refsFromBody": ["Data.List.map", "Foo.Bar.whereLemma"],
"wires": ["Data.List.map", "Foo.Bar.whereLemma", "Foo.Alpha", "Setoid"]
```

+  `refsFromBody`: heuristic identifier tokens from `body`.
+  `wires`: `dedupe(dependencies ∪ refsFromBody)`.


### 6.3 Intended uses

+  Graph building: edges `(prettyQname → wireToken)`.
+  Retrieval: "neighbors in dependency graph".
+  Curriculum: sample by fan-in/fan-out, depth, interface complexity.
+  Training tasks:

   +  **Interface completion**: predict `ports` from statement.
   +  **Missing wire**: predict masked edge in `wires`.

### 6.4 Non-goals (v0)

+  Perfect token → canonical name resolution.
+  Trace/feedback/categorical semantics baked into storage.

---

## 7. Derived views (ETL artifacts)

### 7.1 Graph artifacts

+  **Edge list**: `(srcPrettyQname, depToken, depKind)` where `depKind ∈ {type, body, union}`.
+  **Reverse index**: token → list of definitions that mention it.
+  **Graph stats**: SCCs, degrees, depth estimates, module clustering.

---

### 7.2 Training datasets (examples)

+  **Next-step dataset** (planned): `(goal/context) → tactic/step`.
+  **Ports dataset** (planned): `(typeAst + defKind) → ports`.
+  **Missing-wire dataset** (planned): `(ports + partial wires) → missing wire`.
+  **Proof-completion dataset** (Phase 1, Issue #84): `(goal/context) → proof term/body` (scored by Agda typechecking).

---

#### 7.2.1 Next-step dataset (planned)

---

#### 7.2.2 Ports dataset (planned)

---

#### 7.2.3 Missing-wire dataset (planned)

---

#### 7.2.4 Proof-completion dataset (Phase 1) — `proof-completion.v0`

This derived view targets the **fastest end-to-end demo**: given a goal (type) and a local context,
predict a proof term/body that Agda can type-check.

**Producer:** `ml-pipeline/etl/src/main/scala/etl/BuildProofCompletionDataset.scala`

**Input:** canonical **Full** JSONL rows (§3) filtered to examples with `hasBody=true`.

**Output:** JSONL rows with stable keys and a version tag.

##### 7.2.4.1 Output schema

| Field | Type | Meaning |
|------:|------|---------|
| `schemaVersion` | string | Dataset schema version. **Must equal** `"proof-completion.v0"`. |
| `sourcePrettyQname` | string | Join key / provenance: the original definition `prettyQname`. |
| `sourceFile` | string | Provenance: original `file`. |
| `type` | string | Provenance/debug: original pretty-printed type string. |
| `goal` | string | Best-effort goal (codomain) extracted from `type`. |
| `context` | array[object] | Best-effort telescope of local binders derived from `type` (see below). |
| `context[i].name` | string | Binder name used in this dataset row (may be generated). |
| `context[i].type` | string | Pretty-printed binder type (best-effort segment from `type`). |
| `context[i].hiding` | string | `"implicit"` or `"explicit"` (best-effort). |
| `targetRaw` | string | The extracted `body` **exactly** (trimmed), i.e. the canonical training target before normalization. |
| `target` | string | Resolved/normalized target when possible; else equal to `targetRaw`. |
| `targetResolver` | string | Resolver applied to compute `target`. One of: `atIndex` \| `anonModuleNormalize` \| `raw` *(see below)*. |
| `targetHead` | string *(optional)* | A **derived** head symbol for simple applications (e.g. `f` from `f x`), when the builder can extract it without changing `targetRaw`. |

**Compatibility rule:** consumers must ignore unknown fields (dataset evolves by additive extension).

##### 7.2.4.2 Context/goal extraction (best-effort)

The producer constructs `(context, goal)` from the **string** `type`, using a minimal parser:

- Parses a leading telescope of binders `{x : T}` and `(x : T)` (multiple names per type allowed).
- Splits the remaining type on **top-level** arrows (`→` or `->`), ignoring arrows nested inside `()`, `{}`, `[]`.
- Treats the last arrow segment as `goal`; preceding arrow segments become additional explicit context entries.

**Important:** this is **not** a full Agda parser. It is intentionally “good enough” for Phase-1
and designed to be deterministic and CI-friendly.

##### 7.2.4.3 Target resolution policy (v0)

The producer builds `target` from `targetRaw` using a deliberately small resolver pipeline:

1) **De Bruijn `@i` resolution (`targetResolver = "atIndex"`)**

If `targetRaw` matches `^@\\d+$`, the producer attempts to resolve it using the top-level Π-binder list
from `typeAst`/`typeAstJson`. Agda de Bruijn indices count from the **innermost** binder:

- `@0` = most recently introduced binder (innermost)
- `@1` = next-outer binder
- …

The Π-binders in `typeAst` are naturally encountered **outermost → innermost**, so the resolver reverses
the index appropriately.

2) **Anonymous-module normalization (`targetResolver = "anonModuleNormalize"`)**

If `targetRaw` is a dotted identifier containing anonymous module segments `"_"`, e.g.
`Foo._.bar`, the producer drops those `"_"` segments to get `Foo.bar`.

3) **Fallback (`targetResolver = "raw"`)**

If neither of the above applies, then `target = targetRaw`.

##### 7.2.4.4 Determinism / operational contract (builder CLI)

The dataset builder is designed to be reproducible:

- Streaming read/write (does not load the entire corpus).
- Deterministic input order: consumes JSONL in the order given on disk.
- Bounded outputs: stops after `--limit` **emitted** rows.
- Default “simple body” filter: keeps only bodies with **no whitespace** (overrideable).

For diagnostics, the builder may support a `--strict` mode that aborts nonzero on parse errors
instead of skipping malformed lines).

##### 7.2.4.5 Example output row (schematic)

```json
{
  "schemaVersion": "proof-completion.v0",
  "sourcePrettyQname": "Example.secId",
  "sourceFile": "/path/to/Example.agda",
  "type": "{A : Set} → A → A",
  "goal": "A",
  "context": [
    { "name": "A",  "type": "Set", "hiding": "implicit" },
    { "name": "x0", "type": "A",   "hiding": "explicit" }
  ],
  "targetRaw": "@0",
  "target": "x0",
  "targetResolver": "atIndex",
  "targetHead": "x0"
}
```

---

### 7.3 Inlining knob (storage policy)

+  Canonical rows remain small and stable.
+  Derived views are materialized as:

  +  Parquet for model training
  +  JSONL/CSV for graphs
  +  optional caches for fast iteration

### 7.4 Policy backend contract (v0) — operational interface

AgdaDojang’s end-to-end “propose → check” loop queries a **policy backend** using a small JSON request/response schema.
This is an **operational contract** (not derived from canonical JSONL rows).

- Request schema: `agda-native-air/policy-request@v0`
- Response schema: `agda-native-air/policy-response@v0`
- Hard requirement: response contains `candidates[*].term` (ranked proof term/body candidates).

Preferred version key is `schema` (string). Legacy `schemaVersion` may appear during transition but should be removed once all backends are updated.

See: <docs/policy_contract.md>.


---

## 8. Validation and regression tests

### 8.1 Scala validator expectations

+  Must accept extra keys.
+  Must enforce presence of required keys for Full rows.
+  (Optional future) if `ports/wires` exist, validate shape.

### 8.2 Backend regression fixtures

Maintain small fixtures that test:

+  at least one function/theorem emits `typeAst`
+  `body/hasBody` behavior for function clauses
+  operator naming stability (`_+_`)
+  ports/wires include where-lemma references when present

---

## 9. Examples

### 9.1 Real example: Example.secId (from agda-algebras test fixture)

This example demonstrates **Pi binders with implicit arguments** and the nested `typeAst` structure.

**Source code** (`Example.agda`):
```agda
module _ {A : Set} where
  secId : A → A
  secId x = x
```

**Generated JSONL row:**
```json
{
  "file": "/path/to/Example.agda",
  "module": "Example._",
  "name": "secId",
  "qname": "Example._.secId",
  "prettyModule": "Example",
  "prettyName": "secId",
  "prettyQname": "Example.secId",
  "type": "{A : Set} → A → A",
  "typeAstVersion": "0.3-v0",
  "typeAst": {
    "tag": "Type",
    "sort": {
      "tag": "Set",
      "n": 0
    },
    "term": {
      "tag": "Pi",
      "binder": {
        "hiding": "implicit",
        "nameHint": "A"
      },
      "dom": {
        "tag": "Type",
        "sort": { "tag": "Set", "n": 0 },
        "term": { "tag": "Sort", "sort": { "tag": "Set", "n": 0 } }
      },
      "cod": {
        "tag": "Type",
        "sort": { "tag": "Set", "n": 0 },
        "term": {
          "tag": "Pi",
          "binder": {
            "hiding": "explicit",
            "nameHint": "_"
          },
          "dom": {
            "tag": "Type",
            "sort": { "tag": "Set", "n": 0 },
            "term": { "tag": "Var", "ix": 0, "elims": [] }
          },
          "cod": {
            "tag": "Type",
            "sort": { "tag": "Set", "n": 0 },
            "term": { "tag": "Var", "ix": 1, "elims": [] }
          }
        }
      }
    }
  },
  "kind": "definition",
  "defKind": "function",
  "dependencies": ["Set", "A"],
  "astSize": 19,
  "body": "@0",
  "hasBody": true
}
```

**Validation of `astSize`:**
- `type = "{A : Set} → A → A"` has 19 characters (including spaces and arrows).
- `astSize = 19` ✓

**Key features demonstrated:**
- Nested `Pi` binders: outer Pi for implicit `{A : Set}`, inner Pi for explicit `A → A`.
- `hiding` field: `"implicit"` vs `"explicit"`.
- `Var` nodes with de Bruijn indices (`ix`: 0 for the parameter, 1 for the return type).
- Complete structural AST with version `"0.3-v0"`.

---

### 9.2 Minimal Full row (schematic)

```json
{
  "file": ".../Foo.agda",
  "module": "Foo",
  "name": "lemma",
  "qname": "Foo.lemma",
  "prettyModule": "Foo",
  "prettyName": "lemma",
  "prettyQname": "Foo.lemma",
  "type": "...",
  "typeAstVersion": "0.3-v0",
  "typeAst": { "tag": "Type", "sort": {...}, "term": {...} },
  "kind": "definition",
  "defKind": "function",
  "dependencies": ["Foo.Bar", "Setoid"],
  "astSize": 1234,
  "body": null,
  "hasBody": false
}
```

### 9.3 Full row with ports/wires (schematic — planned v1.0)

```json
{
  "...": "...",
  "ports": {
    "inputs": [{ "nameHint": "A", "hiding": "implicit", "type": "Set" }],
    "outputs": [{ "nameHint": null, "type": "Set" }]
  },
  "refsFromBody": ["Foo.helper"],
  "wires": ["Foo.helper", "Set"]
}
```

---

## 10. Changelog

### 0.3-v0

+  Introduced `typeAst` structural encoding for types.
+  Total encoder with `Other*` buckets.
+  (Optional) `body/hasBody` for function clause bodies.

### proof-completion.v0 (derived dataset; Phase 1)

+  Introduced the `proof-completion.v0` derived JSONL view:
   `(goal/context) → target` using definition rows with `hasBody=true`.
+  Added a minimal, deterministic resolver policy for `target` (`@i` and anon-module normalization).


### 1.0 (planned; optional fields)

+  `ports`, `refsFromBody`, `wires` introduced as optional fields.

---

## 11. Open questions / future extensions

+  Add resolved wire IDs (`wiresResolved`) using a per-module symbol table.
+  Add `typeAst` per port (`ports.inputs[i].typeAst`).
+  Add term AST for bodies (`bodyAstVersion`, `bodyAst`) when useful.
+  Add proof-step traces as a derived dataset (not as canonical row fields).
+  Explore lattice/Heyting derived views over small slices for retrieval/ranking experiments.


