<!-- File: docs/field-reports/2026-10-22-private-indexed-family-inference.md -->

# 2026-10-22, a private repository: three new modules, whole-file checks only

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded (the kickoff asked for high).
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 2 (plus 1 probe of an existing module),
   get_diagnostics 8, check_project 1.

The session wrote three new literate modules (about 520, 720 and 110 lines)
from a written plan, each drafted whole and then checked file by file through
the server until green, and closed with the project gate.  All three checked
in at most four rounds each; the final gate passed.  No hole was opened: the
proofs were written out in full from the plan, so the goal and refinement
tools were never needed.

+  **Tools used**.  `check_file` once on an unchanged existing module (2.2 s,
   to confirm the server accepted this worktree's files), then `check_file`
   and `get_diagnostics` on the new modules: every call answered in 2.4 to
   3.7 s with interfaces warm.  `check_project` ran the server's configured
   gate in 16.1 s (110 modules re-checked from source, exit 0).
+  **What worked**.  The diagnostic codes named each fix directly:
   `ConstructorDoesNotFitInData` (a universe level on an indexed family),
   `AmbiguousName` with both candidates and where each came into scope (an
   `open` of a record that exported a field named like a standard function),
   `NotInScope` with the line (a missing `open`).  The `InversionDepthReached`
   warning that accompanied an `UnsolvedConstraints` error was the real root
   cause, and it was ordered after the error but carried the decisive text:
   Agda refusing to invert a function defined by pattern matching on a list,
   which meant an implicit list argument could not be inferred.  Turning the
   function into an inductive family (so the list became an index) fixed
   every site at once.
+  **What was awkward or missing**.  For `UnsolvedConstraints`, the
   `involved.metaTypes` field is Agda's constraint dump split at line breaks
   into an array of fragments (one constraint spread over five or six array
   elements, `"(blocked on _G_684)"` as an element of its own), about 150
   elements in one answer; it was unreadable as structure and no shorter
   than the message.  Ranking the `InversionDepthReached` warning first, or
   tagging it as the likely cause of the unsolved metas at the same ranges,
   would have saved reading the dump.  A second instance of the same root
   cause came back the same way after one module's fix: a function defined by
   cases on a list, used with an implicit list argument at concrete lists,
   produced only `UnsolvedConstraints` and `UnsolvedMetaVariables`, this time
   without the inversion warning, and the fix (pass the list explicitly, or
   route the argument through an indexed family) came from recognizing the
   pattern, not from the answer.  `check_project` re-checked dependency
   modules from source because the server's gate used the worktree's own
   dependency copy rather than the one the session's shell pointed at; it
   was fast enough not to matter, but its 110 is not this repository's module
   count.
+  **Command line comparison**.  About even.  Each server check took the time
   a command-line `agda` on the same file takes with warm interfaces, and the
   whole-library gate was run from the command line too, for the timing and
   per-module profile the work needed.  The server's advantage was the
   structured codes and ranges, which made each round a direct edit; its
   disadvantage was the constraint dump, worse to read as JSON fragments than
   as the command line's plain text.  For whole-file drafting with no holes,
   neither loop was clearly more efficient.
