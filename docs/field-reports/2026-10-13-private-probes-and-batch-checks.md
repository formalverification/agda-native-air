<!-- File: docs/field-reports/2026-10-13-private-probes-and-batch-checks.md -->

# 2026-10-13, a private repository: language-feature probes and batch checks of generated modules

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 7, type_of 2.

The session wrote a program that generates Agda declarations, and settled
the Agda rules it relies on with small probe files (how a data type's or a
record's parameters appear in its constructors and projections, record
fields bound implicitly or as instances, records without eta and pattern
matching on them, nesting and mutual blocks, positivity).  It then checked
the generated modules, from a few dozen declarations to several thousand,
with the command line, driven by a script that removes each refused
declaration and reruns Agda.  Every probe question was answered, and the
generated modules checked except for refusals the script pinned.

+  **Tools used**.  `check_file` on seven probe files in a scratch
   directory outside any project, each answered in 60 to 513 ms; `type_of`
   twice, once to read a record projection's type (119 ms, with the
   file's first load of 59 ms) and once to see that a constructor applied
   to nothing triggers instance search (4 ms, reusing the load).
+  **What worked**.  The diagnostics' codes and messages answered the
   questions directly.  A first probe passed an instance parameter as an
   implicit argument, and `WrongNamedArgument` came back with "possible
   arguments: C", which named the visibility Agda gives such a parameter.
   A probe matching on a record without eta returned `SplitOnNonEtaRecord`
   with Agda's advice to add the `pattern` declaration, which was the fix.
   `type_of` on a schematic projection `R.f` printed its full type, hidden
   and instance parameters included, in one call where a probe would have
   needed a typed definition.  A file outside any project was checked
   against the server's own configuration, with nothing to set up.
+  **What was awkward or missing**.  Nothing blocked the work.  The batch
   checks needed several Agda runs on each generated module (5 to 9),
   driven by a script that reads Agda's first error, rewrites the module
   and reruns; that loop is outside what the tools do, so it ran on the
   command line.  One command-line run of a probe by absolute path from
   another directory failed with `ModuleNameDoesntMatchFileName`, a
   mistake `check_file` cannot make.
+  **Command line comparison**.  For the probes, the tools were at least as
   efficient: one call per question, with the error's code and its
   message separated, and no working directory to get right.  For the
   generated modules the command line was the only practical loop, since
   the checking script runs Agda tens of times and parses its output
   itself; a 4 MB module took Agda nearly five minutes to scope-check,
   which a tool call would not have shortened.
