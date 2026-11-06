<!-- File: docs/field-reports/2026-11-01-private-rebuilds-behind-one-check.md -->

# 2026-11-01, a private repository: three new modules and a restructured base module, with one check that hid a dozen rebuilds

+  **Date**: 2026-11-01.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: type_of 1, check_file 3.

The session restructured a base module of a large development (a section
split so that one of its two assumptions could be dropped for half of its
contents, with the original module opening the section publicly so that
its twenty-odd importers stayed untouched), added three new literate
modules of 120 to 320 lines each (two theorems stated as one definition
each, and an example module with a seven-element lattice given by its
tables), and extended two existing modules, all under
`--without-K --exact-split --safe` on Agda 2.9.0.  Everything checked;
the project's `make check` (183 modules, cold) and a per-module profile
were the final gate, from the command line.  The server was used for the
first probe and three whole-file checks, the command line for the rest.

+  **Tools used**.  `type_of` once, on a small example module, to see that
   the server resolved the worktree (2.9 s, the lane's first load).
   `check_file` three times: 7.0 s on the restructured base module (which
   rebuilt its two changed imports), 3.4 s on a new module whose one error
   was a `ClashingDefinition`, and 139.4 s on an example module that
   imports the whole development.
+  **What worked**.  Two things.  First, as an earlier report found, the
   session was launched from a worktree before the dev shell had written
   the checkout's wrapper and library registry; one `nix develop` from
   the command line was enough, and the first call resolved the project
   root with no restart.  Second, the `ClashingDefinition` diagnostic
   named the earlier definition and where it came from, "brought into
   scope by the application of" a parameterized module at a given line, so
   the fix (a rename of the new definition) was known before the message
   was finished reading.
+  **What was awkward or missing**.  The 139 s answer.  The example module
   itself costs 2.6 s, almost all of it loading interfaces, as the
   command line's `--profile=definitions` later showed; the time went into
   rebuilding every module between the restructured base module and the
   example, a dozen of them, two of which take 32 s and 19 s on their own.
   `check_file`'s answer carried the elapsed time and a green verdict and
   nothing about what had been re-checked from source, so the session read
   the figure as the module's own cost, suspected a known trap of the
   library (a module applied at a concrete table with its implicit tables
   inferred, which has cost minutes and gigabytes before), and spent a
   profiling round ruling it out.  `check_project` reports
   `modulesChecked`; `check_file` could report the same count, and better
   the names of the modules re-checked from source with their times, which
   Agda prints under `--trace-imports`.  A second, smaller point: the three
   checks ran one at a time because each depended on the previous edit,
   and the harness moved the long one to the background after 120 s, so a
   chain of edit-then-check steps was simpler to run as one shell command
   than as alternating tool calls.
+  **Command line comparison**.  The command line was the more efficient
   loop for this work.  The modules were short and most rounds were a
   whole-file check after a batch of edits, 2 to 3 s each from the
   wrapper, against 3 to 7 s through the server for the same check, and
   the shell let an edit and its check, or several checks in dependency
   order, run as one command.  The measurements (cold whole-library
   profile, per-definition profiles, two routes to one lemma timed at a
   concrete instance, interface counts under `--trace-imports`) are
   command-line work by nature.  The server earned its place on the first
   probe, which confirmed the worktree's root in one call, and on the
   clash diagnostic.
