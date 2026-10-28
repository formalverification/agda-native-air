<!-- File: docs/field-reports/2026-10-27-private-whole-module-checks.md -->

# 2026-10-27, a private repository: two new modules, written whole and checked whole

+  **Date**: 2026-10-27.
+  **Harness**: Claude Code 2.1.310.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 6, type_of 3.

The session added two literate Agda modules to a private library, one of
about 200 lines and one of about 520 lines that imports it, and changed the
prose of three others.  Each module was written whole and checked through
agda-mcp, with no holes; the larger one needed one fix, an implicit argument
Agda could not infer, and then checked.  The library's own gate (`make
check`, 160 modules) passed from the command line, and so did a profile and
an import-closure check that the server has no tool for.

+  **Tools used**.  `check_file` six times: on the first module cold (6.6 s,
   its imports' interfaces already built), then 2.1 to 3.2 s for every later
   check of either module or of the barrel that re-exports them.  `type_of`
   three times, to read back the types of the three main statements after
   they checked: 2.1 s for the lane's first load, then 3 ms each.  The server
   resolved the worktree as its project root through the nearest `.agda-lib`
   file, with no root mismatch.
+  **What worked**.  The one failed check named its fix.  It returned three
   diagnostics: `UnsolvedConstraints` (error), `UnsolvedMetaVariables`
   (error, with the range of two metas on one line), and
   `InversionDepthReached` (warning).  The warning's message carried the
   expression and the expected type with the unsolved meta in it, which
   showed that an implicit argument of a lemma was not inferred; making it
   explicit was a one-token edit, and the next check passed.  `type_of`
   confirmed that each statement's type took exactly the hypotheses intended,
   which is the check that mattered here, since a statement with an extra or
   missing hypothesis would still type-check.
+  **What was awkward or missing**, as follows.
   +  The first diagnostic of the failed check, `UnsolvedConstraints`, came
      without a file, line or range; only the second and third located the
      problem, and the most useful of the three, the warning with the
      expected type, came last.  Attaching the range of the meta the
      constraint is blocked on, or ranking a same-line warning that shows the
      expected type beside the error, would have saved reading all three.
   +  `type_of` in the default `Simplified` mode printed one statement with a
      recursive definition unfolded by one clause (the source wrote it
      applied to a successor), and printed an operator the file does not
      import with its full module path; `Normalised` expanded two standard
      library synonyms into their definitions.  Neither was wrong, but
      neither read as the source does; `AsIs` was not tried.
   +  No tool answers "which modules does this module import, transitively".
      The session needed exactly that, to show that two given modules are not
      in the import closure of the new ones, and ran `agda
      --dependency-graph` from the command line (350 modules in the graph),
      beside a script that follows the import lines through the source tree.
      `get_dependencies` is about definitions in the corpus, not module
      imports.
+  **Command line comparison**.  For writing whole modules and checking them
   whole, `check_file` was the efficient loop: 2 to 3 s per check with warm
   interfaces, about what a command-line run on the same file costs, and the
   diagnostics came structured.  The command line was the better tool for
   the library gate with its timing (`make check` under `/usr/bin/time`, 2 min
   28 s from a cold worktree build), for `make profile`, and for the import
   graph, which the server cannot produce.
