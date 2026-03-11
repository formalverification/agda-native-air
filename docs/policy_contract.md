<!-- File: docs/policy_contract.md -->

# Policy backend contract (v0)

This document defines the **stable request/response JSON contract** used by AgdaJang
to query a policy backend (scripted baseline, LLM, fine-tuned model, etc.).

The goal is to keep the *agent loop* stable: as long as a backend adheres to this
contract, AgdaJang can propose candidates and check them with Agda.

---

## Versioning rules

Contract versions are identified by a schema string:

+ **Request schema**: `agda-ai-prover/policy-request@v0`
+ **Response schema**: `agda-ai-prover/policy-response@v0`

Breaking changes MUST bump `@v0` to `@v1`, etc.

---

## Request (policy-request@v0)

AgdaJang sends:

```json
{
  "schema": "agda-ai-prover/policy-request@v0",
  "goal": "…pretty goal…",
  "context": [
    {"name": "x", "type": "…"},
    {"name": "f", "type": "…"}
  ],
  "module": "Optional.Module.Name",
  "meta": { "prettyQname": "Optional.Name", "holeId": "optional" }
}
```

+  **Required keys**.

   + `schema` (string)
   + `goal` (string)
   + `context` (array of `{name,type}` objects; may be empty)
+  **Optional keys**.

   + `module` (string)
   + `meta` (object)

---

## Response (policy-response@v0)

The backend returns:

```json
{
  "schema": "agda-ai-prover/policy-response@v0",
  "candidates": [
    {"term": "refl", "score": 1.0, "meta": {"kind": "builtin"}},
    {"term": "x", "score": 0.5, "meta": {"kind": "ctx-var"}}
  ],
  "meta": { "policy": "fixture", "deterministic": true }
}
```

+  **Required keys**.

   +  `schema` (string)
   +  `candidates` (array)

      +  **Required candidate key**. Each candidate must have:

         + `term` (string; **required**)

      +  **Optional candidate keys**.

         +  `score` (number)
         +  `meta` (object)

---

## CLI integration (current)

AgdaJang currently invokes a policy backend as a local process.

```sh
python3 python/tools/policy_fixture.py --in request.json --out - --k 5
```

Any backend that adheres to the contract can be swapped in without changing the bridge.


