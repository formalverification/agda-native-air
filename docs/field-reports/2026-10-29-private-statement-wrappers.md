<!-- File: docs/field-reports/2026-10-29-private-statement-wrappers.md -->

# 2026-10-29, a private repository: wrapper definitions over an existing library

+  **Date**: 2026-10-29.
+  **Harness**: Claude Code 2.1.310.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 27.

The session added about two dozen new definitions to sixteen existing
literate modules and one new module: each a level-polymorphic statement
(a plain type, or a record with one field per part) beside a proof assembled
from names the library already had, plus three short new lemmas.  Every
module was developed by writing the whole addition and checking the file,
then fixing what the check reported; the library's own make target was the
final gate, run from the shell.  All 27 checks ran against prebuilt
interfaces; 20 were green and 7 red, and each red one was fixed on the next
call.

+  **Tools used**.  Only `check_file`: 2.1 to 4.2 s per call with the
   dependencies' interfaces present (the slowest was the new module that
   imports fifteen others, 4.2 s).  The other tools were loaded and not
   needed, since nothing was developed a hole at a time.
+  **What worked**.  The diagnostic codes named the fix every time.  An
   `UnequalTypes` with expected `Level` and actual `Type ι` pointed straight
   at an eta-reduced proof that had lost a generalized level argument (fixed by
   writing the lambda out).  A `CannotApply` said that a lemma took its
   arguments implicitly.  An `UnequalTerms` on a `sym` showed the direction of
   an equality was reversed.  The server picked up the checkout's Agda wrapper
   although the dev shell was first entered after the session (and the server)
   had started; no restart was needed.  A failing check of a module that
   imports an edited one compiled the edited one on the way, and the next
   check of the edited module reported `checkedFromSource: false`, correctly.
+  **What was awkward or missing**.  Two red checks were
   `UnsolvedConstraints` followed by `UnsolvedMetaVariables`, from list
   arguments that a fold had hidden from unification.  The message was cut at
   about twenty lines ("4 more lines"), and `involved.metaTypes` held the
   pretty-printed constraint broken into its display lines (fragments such as
   `"(blocked on _xs_741)"` and `"= foldr"`) rather than one entry per meta,
   so the array was no easier to read than the message.  The useful datum was
   the range of the unsolved metas, which named the call to fix; a per-meta
   entry with its expected type would have saved reading the dump.
+  **Command line comparison**.  About even for this work.  A per-file check
   costs the same through the server as from the shell with interfaces present,
   and the structured verdict (exit code, code, range) spared parsing Agda's
   prose, which helped on the seven red checks.  The library-wide gate, the
   per-module profile and the release checks ran from the shell, where the
   project's make targets live; the server's `check_project` would have run the
   same gate, but the profile needs a flag the gate does not pass.
