<!-- File: docs/field-reports/2026-10-28-private-batch-checks-new-modules.md -->

# 2026-10-28, a private repository: five new modules written whole and checked file by file

+  **Date**: 2026-10-28.
+  **Harness**: Claude Code 2.1.310.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 21, normalize 5, exports_of 1.

The session wrote five new literate Agda modules (about 1,660 lines: one
general development and four smaller modules, one of which consumes it) in a
library that sits on a pinned dependency, and edited one barrel.  Each module
was written whole from the existing API, then driven to green with
`check_file`, one error at a time; the project gate (`make check`) ran from the
shell after each batch, and profiling ran from the shell because the server
has no profiling call.  All five check under `--safe`; one module that first
cost 7.3 s of its own came down to 0.19 s after a definition profile named the
culprit.

+  **Tools used**.  `check_file` was the loop: 21 calls, 1.7 to 3.0 s each
   with the dependency's interfaces already built, and one of 11.7 s the
   first time a module pulled in a larger import closure.  Ten calls returned
   an error and eleven were green; every error was fixed by the next edit.
   The first diagnostic was always the one to fix, and its code named the
   class of fix: AmbiguousName (two opened modules exported one name, both
   binding sites listed), UnequalTypes (an operator whose module parameter
   had to be applied before it could be used infix), UnsolvedConstraints with
   UnsolvedMetaVariables (implicit list arguments that unification cannot
   recover through a map; the dump showed the blocked `f ?xs = f ys` shape
   directly), NoParseForApplication (twice, a Σ or a negation under an
   operator of higher precedence), NotInScope with ModuleDoesntExport (a
   standard-library name that lives in a different module from its
   neighbours), CannotApply (a lemma given an argument it takes implicitly),
   MetaCannotDependOn, and SplitError.BlockedType (a pattern-matching `let`
   inside an untyped lambda).  `exports_of` on a barrel listed its 614
   exported names in 0.5 s, which answered whether the new modules added a
   name that clashed.
+  **What worked**.  Batch verdicts were exact and cheap enough to serve as
   the inner loop for whole-file development: no call timed out, and a green
   `check_file` always agreed with the next `make check`.  The diagnostic
   codes are the useful part: branching on them was faster than reading the
   prose, and `involved.candidates` (for AmbiguousName) and
   `involved.metaTypes` (for unsolved constraints) carried exactly the
   information needed.
+  **What was awkward or missing**.  `normalize` was hard to aim: four of its
   five calls failed on scope or parsing (a fully qualified name the file
   imports only under a renaming, a type the chosen file does not import, a
   qualified operator the parser would not take), so one definitional
   question (does an operation of a derived structure reduce to the original
   one?) cost several probes for one answer; a way to add imports for a
   single query, or to name a scratch scope, would have saved them.  The
   UnsolvedConstraints dump ran to about a hundred lines of metas for one root
   cause; a count with the first blocked constraint would be easier to read.
   Profiling has no tool, so a module's own cost (the 7.3 s above, found with
   `--profile=definitions`) needed the shell.  Once, a shell command entered
   the dev shell without the environment variable that points the project at
   a shared copy of the dependency, and the shell hook rewrote the libraries
   file the server reads to point at a fresh local copy.  Re-entering with the
   variable restored it before the next call, but nothing in the server's
   answers would have shown the switch except a slower first check; a field
   naming the resolved library roots in every answer would make it visible.
+  **Command line comparison**.  For writing whole modules against a known
   API, `check_file` was the more efficient loop: it returned the first error
   with a code and a range in about 2 s, against the shell's undifferentiated
   compiler output, and it never rebuilt anything the gate would not.  No
   hole-driven development was needed (`get_goal` and `fill_hole` went
   unused), since every error was local to one definition.  The shell stayed
   the better tool for the project gate, for profiling, and for the release
   checks, which the server does not run.
