<!-- File: docs/field-reports/2026-11-24-private-check-time-decisions-on-a-second-worktree.md -->

# 2026-11-24, a private library: check-time decisions in a second working tree

+  **Date**: 2026-11-24.
+  **Harness**: Claude Code 2.1.331.
+  **Model**: Claude Fable 5.2 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: type_of 2, definition_of 3, search_by_name 1.

The session added about 2,900 lines of literate Agda to a private library,
in six new modules and five extended ones: proofs over finite types, two of
which rest on a decision that the type checker evaluates and accepts by
`refl` (the larger sweeps about ten thousand cases through a search tree it
builds first).  Everything type-checks under the project's heap cap.  The
server gave five answers, all from the main checkout and four of them about
a dependency's definitions; every verdict came from the command line, in
several dozen batch runs, because the server refused the tree the work was
in.

+  **Tools used**.  One `type_of` on a file of the working tree, refused
   with `rootMismatch`; the same question on the main checkout's copy of the
   file, answered in 11.0 s (a first load of 10.9 s).  Three `definition_of`
   calls for a dependency's records and one of its lemmas: 4.5 s for the
   first, then 1 ms each on the reused load.  One `search_by_name` for a
   name prefix, with a limit of 40.
+  **What worked**.  `definition_of` returns the definition's source text
   with its file and lines, found from a client module that only imports
   it; for a record that is the list of fields with their types, which is
   what decides how a theorem about it must be stated, and it was faster
   than finding the defining module by search.  The reuse of a load is
   real: the second and third answers cost a millisecond.  The refusal is
   the right behavior and says so in its own words: it names the two roots,
   says that an answer would be "about a tree you did not ask about", and
   names the fix.
+  **What was awkward or missing**.
    +  The launch-location limit, once more (the report of 2026-11-22 has
       it), with one new datum: here the working tree existed before the
       session began, with its own registry and wrapper beside its library
       file, so everything needed to answer was on disk, and the fix the
       refusal names (restart the server against that tree) is not one a
       running session can apply.  A per-call root, or a server that takes
       the registry beside the file's nearest library file when one is
       there, would have put this whole session on the server.
    +  `search_by_name` matched the pattern anywhere in a name and without
       regard to case, listed the hits in the alphabetical order of their
       modules, and printed each type with every name fully qualified:
       21,000 characters for 40 hits, which the limit cut off inside a
       legacy subtree of the dependency, before the modules the client
       imports.  A names-only mode, a module prefix, or hits in scope first
       would make it answer the question "what does the dependency call
       this?".
    +  Nothing, on the server or on the command line, says which
       declaration a failing run was in when the failure is the heap.  One
       module exhausted a 6 GB cap after eight minutes; `-v tc.decl:5`
       printed no line per declaration under Agda 2.9.0, and
       `--profile=definitions` prints only when a run ends well.  The
       declaration was found by checking truncated copies of the module, one
       run for each cut.  A check that stops at a given line, or a profile
       that survives a failed run, would have named it in one.  (The cause
       was a type that mentioned a value computed from a hypothesis, which
       the type checker unfolded while it solved implicit arguments; passing
       the value to a helper lemma as a variable took the check to five
       seconds.)
    +  A decision accepted by `refl` has no partial verdict: when it is
       false the error is a failed unification of `false` with `true`, with
       no word on which case failed.  The work kept a twin of each decision
       in Python, run first.  A `normalize` of the decision's subterms would
       do it in Agda, and was out of reach for the reason above.  It would
       also have priced at once a fact the session measured only at its
       end: the evaluator shares the value of an argument and evaluates a
       named constant again at every use, so a table built at check time
       must reach the sweep that reads it as an argument (820 lookups took
       58 ms that way, and 12.9 s with the table named inside the sweep).
+  **Command line comparison**.  The command line was the only loop for the
   working tree, so the comparison is with what the server would have
   added.  For this kind of work, which is whole proofs written against
   known lemmas and then timed, the batch run under the heap cap is the
   measurement that counts, and the server's verdict tools run the same
   process; the gain would have been in the knowledge lane, for goals inside
   long case analyses and for `normalize` on the terms a decision evaluates.
   The five answers the server did give replaced about as many searches of
   the dependency's sources.
