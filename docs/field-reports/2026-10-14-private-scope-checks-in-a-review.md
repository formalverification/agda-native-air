<!-- File: docs/field-reports/2026-10-14-private-scope-checks-in-a-review.md -->

# 2026-10-14, a private repository: reviewing another model's finished proof, with scope queries

+  **Date**: 2026-10-14.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: type_of 1, exports_of 1, resolve_name 4, check_file 1.

The session took over a task that a session of another model, in another
harness, had left half done: a new module of about 300 lines, its proof
complete and type-checked, with a pull request open.  The work here was a
review rather than a construction: confirm the main theorem's type, look at
the module's public surface as a barrel module of the library re-exports it,
rename three exported definitions whose short names a consumer opening the
barrel would have to avoid, rewrite some prose, and re-measure the library's
check.  The renames checked on the first try, and the whole-library gate
stayed green.

+  **Tools used**.  `type_of` on the theorem's name in the barrel's scope:
   the type as Agda prints it, with a first load of 2.3 s (the barrel opens
   about two dozen modules publicly).  `exports_of` on the new module, with
   `limit: 0`: all 15 exports with their types in one answer, 12 ms on the
   reused lane.  `resolve_name` four times, in the barrel's scope, on the
   names most likely to clash (two one-letter names, a common word, a
   generic predicate): each came back with one candidate and its provenance
   chain (the barrel's `open ... public`, then the definition's line), in
   about 1 ms.  `check_file` once on the module after the renames: green,
   exit code 0, 2.5 s.
+  **What worked**.  `resolve_name` settled a question that grep could not.
   A grep for one of the names found a second definition in another module
   of the barrel; it was a local binding inside a `where` block, invisible
   from outside, and the one-candidate answer, with provenance, showed that
   in a millisecond.  `exports_of` gave the review its list: every public
   name with its full type, which is how the two one-letter exports came to
   notice, and how the types that mention them could be read before
   renaming.  The `project.root` and `rootSource` fields confirmed at the
   first call that the server was bound to the worktree the session ran in.
+  **What was awkward or missing**.  Checking a barrel for clashes takes one
   `resolve_name` per name, and a new module can export dozens; a query that
   takes several names at once, or that lists the names ambiguous in a
   scope, would make the check one call and complete, where four calls
   sampled it.  The same holds for the renames: no tool says where a name is
   used across the library, so the session grepped for each old name, which
   also matches prose and comments.  `exports_of` prints types with full
   module paths (`Agda.Builtin.Nat.Nat`, `Data.Fin.Base.Fin n`), precise but
   long; a display that uses the names in scope at the file would read
   faster.
+  **Command line comparison**.  For the scope questions the server was the
   more efficient loop: the command line has no equivalent of `resolve_name`
   or `exports_of` short of a scratch module that uses each name, one batch
   check per question.  For the measurement, the command line was the right
   instrument, and the server was never asked: three cold whole-library
   checks under GNU time, alternated with the base commit in a scratch
   worktree; two per-module profiles pinned to one core with `taskset`; and
   one run with `+RTS -s` per arm, whose sampled maximum residency showed
   that a 0.95 GB jump in peak memory between the two arms was the garbage
   collector's schedule, not the new module.  `check_project` gives a verdict
   and no time or memory, and it blocks, so it could not have served there.
