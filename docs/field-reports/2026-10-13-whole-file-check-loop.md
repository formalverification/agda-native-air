<!-- File: docs/field-reports/2026-10-13-whole-file-check-loop.md -->

# 2026-10-13, a private repository: four new modules and an example, checked whole file by whole file

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 15.

The session wrote four new library modules and one example module of an Agda
library (about 1 200 lines of literate Agda), extended one existing module, and
cherry-picked a commit from a sibling branch.  It wrote each module as a whole
file, from a plan worked out in advance, and used `check_file` as the loop:
write, check, read the first diagnostic, edit, check again.  No holes were
written, so `get_goal` and `fill_hole` were never called; the project's gates
(`make check` and `make profile` under its Nix shell) ran on the command line.
Every module reached a green `check_file`, and the whole-library gate then
passed from an empty build.

+  **Tools used**.  `check_file`, 15 calls over five files, each 2.1 to 3.4 s
   of wall time (a cold `agda` per call, loading the dependency interfaces).
   Three of the five files were green on the first call.  The other two took
   six calls each; every intermediate call returned exactly one error, and the
   session fixed it and called again.  The diagnostic codes seen, with what the
   answer carried: `UnequalTerms` three times (the `involved.expected` and
   `involved.actual` fields named the two terms, which located the fix at once:
   a multiplication written in the order the standard library does not reduce,
   an identity substitution that is equal to the identity only up to a lemma,
   and a chain of equalities assembled in the wrong order); `NotInScope` once
   (a module parameter lost by re-indenting a block into a new module);
   `UnsolvedMetaVariables` with `UnsolvedConstraints` once (three absurdity
   lemmas stated on `0F ≡ 1F` without the `Fin 3` annotation; the constraint
   list named the blocked `Fin` equations, which was enough); `AmbiguousName`
   once (a top-level definition sharing its name with a record field brought
   into scope by `open`); and a generalized-variable error reported as
   `UnequalTerms` between `X` and `X₁`, from a `where`-bound helper whose
   signature re-generalized a variable of the enclosing definition.  One call
   returned `success: true` with a `ModuleDoesntExport` *warning* for a name in
   a `using` list that the module did not export, with a "did you mean"
   candidate; that is Agda's own classification and the verdict was right.
+  **What worked**.  The honest verdict: a file was done exactly when
   `success` said so, and the gate agreed on all 33 modules.  The
   `involved.expected` and `involved.actual` fields made the three term
   mismatches one-glance fixes; no output had to be parsed or scrolled.  The
   server resolved every file against the worktree it was launched from, so
   the session never met a library-registry or module-name error, which the
   same loop on the command line in a fresh worktree sometimes does.  Each
   call's cost (2 to 3 s) was small enough that checking after every edit was
   the natural rhythm.
+  **What was awkward or missing**.  The `UnsolvedMetaVariables` answer listed
   the metas by position only (`metaTypes` held ranges, no types), because no
   warm lane held the file; the constraint list of the companion
   `UnsolvedConstraints` diagnostic is what carried the information.  The
   `AmbiguousName` answer printed the same qualified name twice in
   `involved.candidates` (a record field and a definition print alike), and
   only the message's prose told them apart.  Nothing was missing for this
   loop; a hole-driven session would have exercised `get_goal` and `fill_hole`,
   which this one did not.
+  **Command line comparison**.  About equal for this way of working, with a
   small edge to the server.  Writing whole files and checking them is the
   same loop on the command line (`agda <file>` under the project's shell), at
   the same cost per call; what the server added was the structured answer
   (the code, the range, the two terms of a mismatch) in place of a page of
   output, and freedom from the registry and working-directory traps of a new
   worktree.  The gates stayed on the command line because the project's
   Makefile is the gate, and `make profile` from an empty build, pinned to one
   core, gave the per-module costs the project's barrel policy asks for.
