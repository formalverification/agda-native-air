<!-- File: docs/field-reports/2026-10-11-cubical-compatible-modules-second-session.md -->
<!--
  Recovered under issue #252.  Written on 2026-10-11 as a section of
  docs/mcp-field-reports.md in the main checkout and never committed there;
  recovered from main's stash of 2026-10-11 23:17.  The title is the
  section's heading in this directory's form (the date, then the repository
  and the work, with "#N" written "issue N"), and the header was added from
  the section's own text, "not recorded" marking what it does not say.  The
  body is the section's, unchanged.
-->

# 2026-10-11, a private repository: four more modules under `--cubical-compatible`, a second session (Claude Opus 5.5)

+  **Date**: 2026-10-11.
+  **Harness**: Claude Code (version not recorded).
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 13.

A second session in the same private repository wrote four modules
(`--safe --cubical-compatible`, Agda 2.8.0, agda-stdlib 2.3) under Claude
Code with the agda-mcp server connected.  As in the first, each module was
written whole and repaired from the diagnostics, and the project's own gate
ran on the command line at the end and passed.

+  **Tools used**.  `check_file` 13 calls, nothing else.  No module had a
   hole, and standard-library names came from grep over the Nix store, so
   `get_goal`, `fill_hole`, `search_by_name` and `type_of` were not needed.
   One module imports another; after an edit to the imported one,
   `check_file` on the importer re-checked both (3.9 s) with no
   `reload` asked.
+  **Speed**.  170 ms for a 124-line module with warm library interfaces,
   about 600 ms for a 273-line one, 2 to 3.4 s for a 495-line one, and 5.8
   to 8.4 s for a 421-line module whose first check included its
   dependency.
+  **Diagnostics that named the fix**.  `AmbiguousName` listed both
   candidates (`Level.suc` and `Fin.suc`, both opened); `ClashingDefinition`
   named the earlier definition's file and line, an imported operator with
   the name of a record field; `UnequalHiding` gave `expected` and `actual`,
   an implicit function type against an explicit lambda, which a
   type-annotated `where` clause fixed; `NotInScope` listed the
   candidates, and the module to import from was among them.
+  **One diagnostic that did not**.  An `UnsolvedMetaVariables` error came
   with `involved.metaTypes` holding the meta's file and range, not its
   type, and with no `metas` (no warm lane held the file).  The meta was a
   universe level that `u ⊔ w ⊔ p = u ⊔ w ⊔ q` does not determine; the
   range pointed at the right argument, and passing the arguments
   explicitly fixed it, but the type had to be inferred by hand.
+  **Warnings on a passing file**.  One `check_file` answered
   `success: true` with five `UnsupportedIndexedMatch` warnings, for
   clauses matching on the constructors of `Fin` and of `Dec` (whose
   `Reflects` is indexed by `Bool`).  The project's gate hides warnings of
   passing files, so only the server showed them; the module was rewritten
   (cases on `Fin` through agda-stdlib's `∀-cons`, decisions through `does`)
   until `check_file` returned no diagnostic at all.
+  **Command line comparison**.  Four runs went to the command line: one
   on a repository module, to look for warnings the gate hides, before a
   later `check_file` showed that the server reports them; and three in
   scratch directories outside the repository, two controls (a clause
   removed to see a proof fail, and an example whose expected value was
   changed to see `refl` reject it) and the example itself.  Each took
   about 9 seconds, most of it entering the dev
   shell, against the server's answers of under a second to 8 seconds on
   the repository's files, and its output had to be filtered by hand.  The
   server was the more efficient loop for every module in the repository;
   the command line was used out of habit for the scratch controls, which
   the first session reports the server also accepts.
