---
name: typechecking-agda
description: Type-check Agda in the agda-native-air repository — the agda-dojang library modules (agda-dojang/agda/), example modules under data/agda/, and (once Issue #13 lands) the benchmark obligation/gold fixtures under data/benchmarks/ — against the pinned toolchain. Use whenever Agda source has been added or modified and needs validation before commit.
---

# Type-checking Agda in agda-native-air

A gold solution or Agda module is not done until it type-checks under the pinned toolchain (Agda 2.8.0 + standard-library 2.3).  Type-checking is the test.

## Procedure

1. All Agda runs inside the flake shell, which registers `standard-library` and the repo-local `agda-dojang` library and defines an `agda` wrapper: `nix develop .#backend --command agda <file>`.  Never call a bare system `agda`.
2. Check a single file first — it is fast and localizes errors.  Targets that type-check today: a library module, `nix develop .#backend --command agda agda-dojang/agda/AgdaDojang/Debug.agda`, or an example, `... agda data/agda/SimpleTheorems.agda`.
3. Fixtures that intentionally carry `{!!}` holes are validated differently: the proof-completion fixtures under `agda-dojang/data/fixtures/*.agda` are exercised by `make eval-proof-completion-smoke` (needs `.#all`), not by a plain type-check.
4. The Issue #13 benchmark (`data/benchmarks/`, PR #50) adds gold solutions that must type-check cleanly.  Once it lands, check a gold file with `nix develop .#backend --command agda data/benchmarks/agda-stdlib-v0/gold/<Name>.agda`, iterating the `gold` paths in `benchmark-index.jsonl`.
5. Do not stage generated artifacts: `*.agdai` and the nix-generated `agda/libraries` are gitignored.

## Notes specific to this repo

+  Modules that import `AgdaDojang.Debug` — the `agda-dojang` fixtures, and the Issue #13 benchmark obligations — resolve only inside the flake shell, where the `agda-dojang` library is registered; that is why a bare `agda` fails.
+  A file with a `{!!}` hole does not type-check clean by design: the `agda-dojang/data/fixtures/*.agda` holes are checked via `make eval-proof-completion-smoke`, while a benchmark obligation's hole is filled by its `gold/` counterpart, and only the gold must type-check.
+  `agda-algebras` work needs a local checkout: set `AGDA_ALGEBRAS_ROOT=/path/to/agda-algebras` before entering the shell so the flake registers the library.

## Reading common Agda errors

+  Unsolved metas / yellow: a term's type is under-determined; add an explicit type signature or annotate the ambiguous argument.
+  `x != y of type T`: a definitional-equality mismatch; check the lemma names and argument order in the equational chain.
+  "not in scope" after an import change: confirm the name and module path exist in standard-library 2.3, since names drift between stdlib versions.

## Quality gate (verify before declaring done)

+  The gold file type-checks with no errors and no unsolved metas.
+  Every definition has an explicit type signature, and the proof is the simplest correct term, not a token-count golf.
+  The obligation/gold pair, the `benchmark-index.jsonl` line, and the declared difficulty tier are mutually consistent.
