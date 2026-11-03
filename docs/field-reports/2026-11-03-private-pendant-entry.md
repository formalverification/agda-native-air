<!-- File: docs/field-reports/2026-11-03-private-pendant-entry.md -->

# 2026-11-03, a private repository: a derived catalog entry over a restated lemma

+  **Date**: 2026-11-03.
+  **Harness**: Claude Code (version not recorded).
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 6.

The session wrote one new literate module of about 360 lines and changed
three existing ones: a record of lattice-side hypotheses, a module of
transport lemmas along an order isomorphism (seven small lemmas, each a few
lines), a restatement of one module parameter with a derivation of the new
form from the old and from a library theorem, and the entry itself, which
composes the three and instantiates itself on a concrete seven-element
lattice by decision procedures.  Every term was written from the sources
and checked a whole file at a time; the final gate was the Makefile's
check, which was green on the first run after the files were, and the
Python test suite.

+  **Tools used**.  `check_file` six times, each in 2.9 to 3.1 seconds: the
   module the work built on, before any change (`checkedFromSource` false,
   the interfaces of a baseline `make check` of 224 modules, 9 minutes 47
   seconds cold, reused); the transport module after its new section; the
   restated module; the new entry twice (one error, then green); and the
   entry once more after prose-only edits.  No `get_goal`, `fill_hole` or
   `type_of`: the lemmas were short enough to write whole, and a file check
   at three seconds was the cheaper loop than a hole at a time.
+  **What worked**.  The one error was an `AmbiguousName` between a record
   field opened from a certificate and a standard-library decider of the
   same name; the diagnostic named both candidates and where each came into
   scope (the `open` of the record at a line and column, the standard
   library import at another), so the fix was one `renaming` and the next
   check was green.  The warm lane kept every later check at three seconds
   though each rebuilt the file and its stale dependents from source.
+  **What was awkward or missing**.  Nothing blocked.  Two small things: a
   `checkedFromSource: true` answer does not say which dependents it
   rebuilt, so the cost of a change to a widely imported module was
   invisible until the Makefile's check ran (it took under four minutes
   warm, against the server's three seconds for the one file); and the
   server and `make check` write the same interface files, so the session
   serialized them by hand rather than risk running both at once, which the
   tool descriptions do not warn about.
+  **Command line comparison**.  The server was the more efficient loop for
   the per-file checks: three seconds against the Makefile's aggregator,
   which regenerates its module list and checks every stale dependent.  The
   command line stayed the final gate.  For writing whole lemmas from the
   sources, neither loop was in the way; a hole-driven session would have
   used `get_goal`, which this one never needed.
